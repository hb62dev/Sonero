"""
WiFi transfer between Sonero devices on the same local network.

The receiver is a small HTTP server on TRANSFER_PORT (default 8090) bound to
0.0.0.0. It only runs while the user enables "Iniciar Recepción", so the main
API (127.0.0.1:8000) is never exposed to the network.

Wire protocol (compatible with the Flutter native implementation used on
Android, see sonero-app/lib/services/wifi_transfer_service.dart):

    POST /prepare            JSON {filename, type, playlist, size, title, artist, ...}
    POST /upload?filename=X  raw file bytes (application/octet-stream)

GET / serves a small upload page so any phone browser can send files without
installing the app.
"""

import asyncio
import contextlib
import filecmp
import ipaddress
import logging
import re
import socket
import time
import uuid
from pathlib import Path
from typing import AsyncIterator

import httpx
import psutil
import uvicorn
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from config import settings
from services.wifi_upload_page import UPLOAD_PAGE_HTML

logger = logging.getLogger("sonero.wifi_transfer")

AUDIO_EXTS = {".mp3", ".m4a", ".opus", ".ogg", ".wav", ".aac", ".flac", ".wma", ".webm"}
VIDEO_EXTS = {".mp4", ".webm", ".mkv", ".mov"}
COVER_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
ALLOWED_EXTS = {"music": AUDIO_EXTS, "video": VIDEO_EXTS, "cover": COVER_EXTS}

MAX_FILE_BYTES = 4 * 1024 * 1024 * 1024  # 4 GB
PENDING_TTL_SECONDS = 600
CHUNK_SIZE = 256 * 1024

_INVALID_CHARS = re.compile(r'[\\/:*?"<>|\x00-\x1f]')


# ── Helpers ───────────────────────────────────────────────────────────────────

def sanitize_name(name: str | None) -> str | None:
    """Return a safe single path component, or None if nothing usable is left."""
    if not name:
        return None
    # Keep only the last component of either separator style
    name = re.split(r"[\\/]", name)[-1]
    name = _INVALID_CHARS.sub("_", name).strip().strip(".")
    if not name or name in {".", ".."}:
        return None
    return name[:200]


def detect_type(filename: str) -> str | None:
    ext = Path(filename).suffix.lower()
    if ext in VIDEO_EXTS - {".webm"}:
        return "video"
    if ext in AUDIO_EXTS:
        return "music"
    if ext in COVER_EXTS:
        return "cover"
    return None


def get_lan_ips() -> list[str]:
    """
    IPv4 addresses other devices on the WiFi/Ethernet network can reach,
    best candidate first.

    Point-to-point interfaces (VPN tunnels like utun/tun/wg) are skipped: when a
    VPN is active it owns the default route, so asking the OS "which IP would I
    use to go out" returns the tunnel address, which phones on the LAN can't reach.
    """
    candidates: list[tuple[int, str]] = []
    try:
        stats = psutil.net_if_stats()
        for name, addrs in psutil.net_if_addrs().items():
            if name in stats and not stats[name].isup:
                continue
            for a in addrs:
                if a.family != socket.AF_INET or a.ptp:
                    continue
                ip = ipaddress.ip_address(a.address)
                if ip.is_loopback or ip.is_link_local or not ip.is_private:
                    continue
                # Prefer typical home/office WiFi ranges, and broadcast-capable interfaces
                rank = 0 if a.address.startswith("192.168.") else 1 if a.address.startswith("10.") else 2
                if not a.broadcast:
                    rank += 3
                candidates.append((rank, a.address))
    except Exception as e:
        logger.warning("Could not enumerate network interfaces: %s", e)
    return [ip for _, ip in sorted(candidates)]


def get_lan_ip() -> str | None:
    ips = get_lan_ips()
    return ips[0] if ips else None


def _unique_path(path: Path) -> Path:
    if not path.exists():
        return path
    stem, suffix = path.stem, path.suffix
    for i in range(1, 1000):
        candidate = path.with_name(f"{stem} ({i}){suffix}")
        if not candidate.exists():
            return candidate
    return path.with_name(f"{stem} ({uuid.uuid4().hex[:6]}){suffix}")


def _covers_dir() -> Path:
    d = settings.TMP_DIR / "wifi_covers"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _apply_mp3_metadata(path: Path, info: dict) -> None:
    """Fill missing ID3 tags / cover art in a received MP3 from sender metadata."""
    if path.suffix.lower() != ".mp3":
        return
    try:
        from mutagen.id3 import ID3, ID3NoHeaderError, TIT2, TPE1, TALB, TCON, TDRC, APIC

        try:
            tags = ID3(path)
        except ID3NoHeaderError:
            tags = ID3()

        changed = False
        for frame_cls, key in ((TIT2, "title"), (TPE1, "artist"), (TALB, "album"),
                               (TCON, "genre"), (TDRC, "year")):
            value = (info.get(key) or "").strip()
            if value and not tags.get(frame_cls.__name__):
                tags.add(frame_cls(encoding=3, text=value))
                changed = True

        cover_name = sanitize_name(info.get("cover_url"))
        if cover_name and not tags.getall("APIC"):
            cover_path = _covers_dir() / cover_name
            if cover_path.is_file():
                mime = "image/png" if cover_path.suffix.lower() == ".png" else "image/jpeg"
                tags.add(APIC(encoding=3, mime=mime, type=3, desc="Cover", data=cover_path.read_bytes()))
                changed = True

        if changed:
            tags.save(path)
    except Exception as e:  # metadata is best-effort, never fail the transfer
        logger.warning("Could not write metadata to %s: %s", path.name, e)


# ── State ─────────────────────────────────────────────────────────────────────

class _EmbeddedServer(uvicorn.Server):
    """uvicorn server that runs inside the main event loop without touching signals."""

    @contextlib.contextmanager
    def capture_signals(self):
        yield

    def install_signal_handlers(self) -> None:  # uvicorn < 0.29
        pass


class TransferState:
    def __init__(self) -> None:
        self.server: _EmbeddedServer | None = None
        self.server_task: asyncio.Task | None = None
        self.pending: dict[str, dict] = {}
        self.receive_items: dict[str, dict] = {}
        self.send_items: dict[str, dict] = {}
        self.send_task: asyncio.Task | None = None

    @property
    def receiving(self) -> bool:
        return self.server is not None and self.server.started and not self.server.should_exit

    @property
    def sending(self) -> bool:
        return self.send_task is not None and not self.send_task.done()


state = TransferState()


def _set_item(items: dict, filename: str, **fields) -> None:
    item = items.setdefault(filename, {"filename": filename, "progress": 0, "status": "preparing", "error": None})
    item.update(fields)
    item["updated_at"] = time.time()


def _prune_pending() -> None:
    cutoff = time.time() - PENDING_TTL_SECONDS
    for key in [k for k, v in state.pending.items() if v["created_at"] < cutoff]:
        state.pending.pop(key, None)


# ── Receiver app (exposed on the LAN) ─────────────────────────────────────────

receiver_app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
receiver_app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


@receiver_app.get("/", response_class=HTMLResponse)
async def upload_page() -> str:
    return UPLOAD_PAGE_HTML


@receiver_app.get("/info")
async def receiver_info() -> dict:
    root = settings.MUSIC_DIR
    video_dir = settings.VIDEO_DIR.resolve()
    playlists = sorted(
        d.name for d in root.iterdir()
        if d.is_dir() and not d.name.startswith(".") and d.resolve() != video_dir
    ) if root.exists() else []
    return {
        "app": "sonero",
        "device": socket.gethostname(),
        "playlists": playlists,
        "max_file_bytes": MAX_FILE_BYTES,
    }


@receiver_app.post("/prepare")
async def prepare(request: Request) -> dict:
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="JSON inválido.")

    filename = sanitize_name(data.get("filename"))
    if not filename:
        raise HTTPException(status_code=400, detail="Nombre de archivo inválido.")

    file_type = data.get("type") or detect_type(filename)
    if file_type not in ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail=f"Tipo no soportado: {file_type}")
    if Path(filename).suffix.lower() not in ALLOWED_EXTS[file_type]:
        raise HTTPException(status_code=400, detail=f"Extensión no permitida para {file_type}.")

    try:
        size = int(data.get("size") or 0)
    except (TypeError, ValueError):
        size = 0
    if size < 0 or size > MAX_FILE_BYTES:
        raise HTTPException(status_code=413, detail="Archivo demasiado grande.")

    _prune_pending()
    state.pending[filename] = {
        "type": file_type,
        "playlist": sanitize_name(data.get("playlist")) if file_type == "music" else None,
        "size": size,
        "title": str(data.get("title") or ""),
        "artist": str(data.get("artist") or ""),
        "album": str(data.get("album") or ""),
        "genre": str(data.get("genre") or ""),
        "year": str(data.get("year") or ""),
        "cover_url": data.get("cover_url"),
        "created_at": time.time(),
    }
    _set_item(state.receive_items, filename, type=file_type, status="preparing", progress=0, error=None)
    return {"status": "ready"}


@receiver_app.post("/upload")
async def upload(request: Request, filename: str = Query(...)) -> dict:
    filename = sanitize_name(filename)
    info = state.pending.pop(filename, None) if filename else None
    if info is None:
        raise HTTPException(status_code=400, detail="Subida no preparada.")

    file_type = info["type"]
    if file_type == "music":
        dest_dir = settings.MUSIC_DIR / info["playlist"] if info["playlist"] else settings.MUSIC_DIR
    elif file_type == "video":
        dest_dir = settings.VIDEO_DIR
    else:
        dest_dir = _covers_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)

    existing = dest_dir / filename
    part = dest_dir / f".{filename}.{uuid.uuid4().hex[:8]}.part"

    expected = info["size"]
    received = 0
    _set_item(state.receive_items, filename, type=file_type, status="transferring", progress=0)
    try:
        with part.open("wb") as fh:
            async for chunk in request.stream():
                received += len(chunk)
                if received > MAX_FILE_BYTES:
                    raise HTTPException(status_code=413, detail="Archivo demasiado grande.")
                fh.write(chunk)
                if expected:
                    _set_item(state.receive_items, filename, progress=min(99, received * 100 // expected))
        if expected and received != expected:
            raise HTTPException(status_code=400, detail=f"Transferencia incompleta ({received}/{expected} bytes).")
        if file_type == "cover":
            # Covers are referenced by name from the following music upload: overwrite them.
            target, duplicate = existing, False
            part.replace(target)
        elif existing.is_file() and filecmp.cmp(existing, part, shallow=False):
            # Same file already in the library (e.g. sent twice): keep the original.
            target, duplicate = existing, True
            part.unlink()
        else:
            target, duplicate = _unique_path(existing), False
            part.replace(target)
    except BaseException as e:
        part.unlink(missing_ok=True)
        detail = e.detail if isinstance(e, HTTPException) else str(e) or type(e).__name__
        _set_item(state.receive_items, filename, status="failed", error=detail)
        logger.warning("WiFi receive failed for %s: %s", filename, detail)
        raise

    if file_type == "music" and not duplicate:
        _apply_mp3_metadata(target, info)

    _set_item(state.receive_items, filename, status="done", progress=100,
              saved_as=target.name, duplicate=duplicate)
    logger.info("WiFi received %s -> %s%s", filename, target, " (duplicate, skipped)" if duplicate else "")
    return {"status": "success", "saved_as": target.name, "duplicate": duplicate}


# ── Receiver lifecycle ────────────────────────────────────────────────────────

async def start_receiver() -> None:
    if state.receiving:
        return
    server = _EmbeddedServer(uvicorn.Config(
        receiver_app,
        host="0.0.0.0",
        port=settings.TRANSFER_PORT,
        log_level="warning",
        lifespan="off",
    ))
    task = asyncio.create_task(server.serve())

    # Wait until it is listening (or failed, e.g. port already in use)
    for _ in range(100):
        if server.started or task.done():
            break
        await asyncio.sleep(0.05)

    if not server.started:
        server.should_exit = True
        exc = task.exception() if task.done() and not task.cancelled() else None
        raise RuntimeError(
            f"No se pudo abrir el puerto {settings.TRANSFER_PORT}"
            + (f": {exc}" if exc else " (¿está en uso por otra aplicación?)")
        )

    state.server, state.server_task = server, task
    logger.info("WiFi receiver listening on 0.0.0.0:%s", settings.TRANSFER_PORT)


async def stop_receiver() -> None:
    server, task = state.server, state.server_task
    state.server = state.server_task = None
    state.pending.clear()
    if server is None:
        return
    server.should_exit = True
    if task is not None:
        with contextlib.suppress(Exception, asyncio.CancelledError):
            await asyncio.wait_for(task, timeout=5)
    logger.info("WiFi receiver stopped")


# ── Sender ────────────────────────────────────────────────────────────────────

def validate_target_ip(target_ip: str) -> str:
    try:
        ip = ipaddress.ip_address(target_ip.strip())
    except ValueError:
        raise HTTPException(status_code=400, detail="IP inválida.")
    if not (ip.is_private or ip.is_link_local) or ip.is_loopback or ip.is_unspecified:
        raise HTTPException(status_code=400, detail="La IP debe ser de tu red local (ej. 192.168.x.x).")
    return str(ip)


def resolve_library_file(relative: str) -> tuple[Path, str, str | None]:
    """Map a library filename (as returned by /downloads) to (path, type, playlist)."""
    rel = relative.replace("\\", "/").lstrip("/")
    if rel.startswith("videos/") and settings.VIDEO_DIR != settings.MUSIC_DIR:
        base, rel, file_type = settings.VIDEO_DIR, rel[len("videos/"):], "video"
    else:
        base = settings.MUSIC_DIR
        file_type = "video" if Path(rel).suffix.lower() in VIDEO_EXTS - {".webm"} else "music"

    path = (base / rel).resolve()
    if not path.is_relative_to(base.resolve()) or not path.is_file():
        raise HTTPException(status_code=404, detail=f"Archivo no encontrado: {relative}")

    parts = Path(rel).parts
    playlist = parts[0] if file_type == "music" and len(parts) > 1 else None
    return path, file_type, playlist


async def _file_chunks(path: Path, filename: str, total: int) -> AsyncIterator[bytes]:
    sent = 0
    with path.open("rb") as fh:
        while chunk := fh.read(CHUNK_SIZE):
            sent += len(chunk)
            _set_item(state.send_items, filename, progress=min(99, sent * 100 // max(total, 1)))
            yield chunk


async def _send_all(target_ip: str, port: int, files: list[dict]) -> None:
    base = f"http://{target_ip}:{port}"
    timeout = httpx.Timeout(connect=5, read=120, write=120, pool=5)
    async with httpx.AsyncClient(timeout=timeout) as client:
        for f in files:
            path: Path = f["path"]
            filename = path.name
            size = path.stat().st_size
            _set_item(state.send_items, filename, type=f["type"], status="preparing", progress=0, error=None)
            try:
                res = await client.post(f"{base}/prepare", json={
                    "filename": filename,
                    "type": f["type"],
                    "playlist": f["playlist"],
                    "size": size,
                    "title": f.get("title") or "",
                    "artist": f.get("artist") or "",
                    "album": f.get("album") or "",
                    "genre": f.get("genre") or "",
                    "year": f.get("year") or "",
                    "cover_url": None,  # covers travel embedded in the MP3
                })
                res.raise_for_status()

                _set_item(state.send_items, filename, status="transferring")
                res = await client.post(
                    f"{base}/upload",
                    params={"filename": filename},
                    content=_file_chunks(path, filename, size),
                    headers={"Content-Type": "application/octet-stream", "Content-Length": str(size)},
                )
                res.raise_for_status()
                _set_item(state.send_items, filename, status="done", progress=100)
            except httpx.ConnectError:
                _set_item(state.send_items, filename, status="failed",
                          error=f"No se pudo conectar con {target_ip}:{port}. ¿Tiene la recepción activada?")
            except httpx.HTTPStatusError as e:
                detail = e.response.text[:200]
                with contextlib.suppress(Exception):
                    detail = e.response.json().get("detail") or e.response.json().get("error") or detail
                _set_item(state.send_items, filename, status="failed", error=str(detail))
            except Exception as e:
                _set_item(state.send_items, filename, status="failed", error=str(e) or type(e).__name__)


def start_sending(target_ip: str, port: int, files: list[dict]) -> None:
    if state.sending:
        raise HTTPException(status_code=409, detail="Ya hay un envío en curso.")
    for f in files:
        _set_item(state.send_items, f["path"].name, type=f["type"], status="preparing", progress=0, error=None)
    state.send_task = asyncio.create_task(_send_all(target_ip, port, files))


def clear_finished() -> None:
    for items in (state.receive_items, state.send_items):
        for key in [k for k, v in items.items() if v["status"] in {"done", "failed"}]:
            items.pop(key, None)
