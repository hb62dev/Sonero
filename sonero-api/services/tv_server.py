"""
Sonero TV: lets Android TV devices on the same WiFi browse and stream the
library, without internet.

* TV API on TV_PORT (default 8091), bound to 0.0.0.0 only while the user has
  enabled "Sonero TV" in the app. Every endpoint except /tv/info and /tv/pair
  needs a device token.
* Pairing: the user opens a 5-minute pairing window in the app, which shows a
  6-digit PIN; the TV sends it once and receives a long-lived token. Only a
  SHA-256 of each token is stored, and devices can be revoked.
* Discovery: a UDP responder on TV_DISCOVERY_PORT (default 8092) answers the
  broadcast "SONERO_DISCOVER" with this server's name and TV API port.
"""

import asyncio
import contextlib
import hashlib
import hmac
import json
import logging
import secrets
import socket
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import uvicorn
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, HTMLResponse, Response
from pydantic import BaseModel, Field

from config import settings
from database import SessionLocal
from models import Media, PlaybackEvent, SystemSetting
from services.wifi_transfer import AUDIO_EXTS, _EmbeddedServer, get_lan_ip

logger = logging.getLogger("sonero.tv")

DISCOVERY_REQUEST = b"SONERO_DISCOVER"
PIN_TTL_SECONDS = 300
PIN_MAX_ATTEMPTS = 5
LIBRARY_CACHE_SECONDS = 30
API_VERSION = 1

_ENABLED_KEY = "tv_enabled"
_DEVICES_KEY = "tv_devices"


# ── Persistent settings ───────────────────────────────────────────────────────

def _get_setting(key: str) -> str | None:
    db = SessionLocal()
    try:
        record = db.query(SystemSetting).filter(SystemSetting.key == key).first()
        return record.value if record else None
    finally:
        db.close()


def _set_setting(key: str, value: str) -> None:
    db = SessionLocal()
    try:
        record = db.query(SystemSetting).filter(SystemSetting.key == key).first()
        if record is None:
            record = SystemSetting(key=key)
            db.add(record)
        record.value = value
        db.commit()
    finally:
        db.close()


def is_enabled() -> bool:
    return _get_setting(_ENABLED_KEY) == "1"


def _load_devices() -> list[dict]:
    try:
        return json.loads(_get_setting(_DEVICES_KEY) or "[]")
    except json.JSONDecodeError:
        return []


def _save_devices(devices: list[dict]) -> None:
    _set_setting(_DEVICES_KEY, json.dumps(devices))


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def list_devices() -> list[dict]:
    out = []
    for d in _load_devices():
        public = {k: v for k, v in d.items() if k != "token_hash"}
        public.setdefault("kind", "tv")
        public["online"] = d["id"] in state.connections
        public["now_playing"] = state.tv_states.get(d["id"]) if public["online"] else None
        out.append(public)
    return out


def revoke_device(device_id: str) -> bool:
    devices = _load_devices()
    remaining = [d for d in devices if d["id"] != device_id]
    if len(remaining) == len(devices):
        return False
    _save_devices(remaining)
    ws = state.connections.pop(device_id, None)
    state.tv_states.pop(device_id, None)
    if ws is not None:
        asyncio.ensure_future(_close_quietly(ws, 4401))
    return True


async def _close_quietly(ws: WebSocket, code: int = 1000) -> None:
    with contextlib.suppress(Exception):
        await ws.close(code=code)


def server_name() -> str:
    name = socket.gethostname()
    return name.removesuffix(".local").replace("-", " ")


# ── Pairing ───────────────────────────────────────────────────────────────────

@dataclass
class _Pairing:
    pin: str
    expires_at: float
    attempts: int = 0


@dataclass
class _State:
    server: _EmbeddedServer | None = None
    server_task: asyncio.Task | None = None
    discovery: asyncio.DatagramTransport | None = None
    pairing: _Pairing | None = None
    library: list[dict] = field(default_factory=list)
    library_index: dict[str, Path] = field(default_factory=dict)
    library_built_at: float = 0.0
    # Phase 2: TVs connected over WebSocket (device id -> socket) and what they report playing
    connections: dict[str, WebSocket] = field(default_factory=dict)
    tv_states: dict[str, dict] = field(default_factory=dict)

    @property
    def running(self) -> bool:
        return self.server is not None and self.server.started and not self.server.should_exit


state = _State()


def start_pairing() -> dict:
    state.pairing = _Pairing(pin=f"{secrets.randbelow(1_000_000):06d}", expires_at=time.time() + PIN_TTL_SECONDS)
    return pairing_status()


def cancel_pairing() -> None:
    state.pairing = None


def pairing_status() -> dict | None:
    p = state.pairing
    if p is None or time.time() > p.expires_at or p.attempts >= PIN_MAX_ATTEMPTS:
        state.pairing = None
        return None
    return {"pin": p.pin, "expires_in": int(p.expires_at - time.time())}


def _pair(pin: str, device_name: str, kind: str = "tv") -> dict:
    p = state.pairing
    if p is None or time.time() > p.expires_at:
        state.pairing = None
        raise HTTPException(status_code=403, detail="El emparejamiento no está activo. Ábrelo en Sonero en tu computadora.")
    p.attempts += 1
    if not hmac.compare_digest(pin.strip(), p.pin):
        if p.attempts >= PIN_MAX_ATTEMPTS:
            state.pairing = None
            raise HTTPException(status_code=403, detail="Demasiados intentos. Genera un nuevo PIN en Sonero.")
        raise HTTPException(status_code=401, detail="PIN incorrecto.")

    token = secrets.token_urlsafe(32)
    devices = _load_devices()
    devices.append({
        "id": uuid.uuid4().hex[:12],
        "name": (device_name or ("Android TV" if kind == "tv" else "Control remoto")).strip()[:60],
        "kind": kind,
        "token_hash": _hash_token(token),
        "paired_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "last_seen": None,
    })
    _save_devices(devices)
    state.pairing = None  # one PIN pairs one device
    return {"token": token, "server_name": server_name()}


def _device_for_token(token: str | None) -> dict | None:
    if not token:
        return None
    token_hash = _hash_token(token)
    devices = _load_devices()
    for d in devices:
        if hmac.compare_digest(d["token_hash"], token_hash):
            now = datetime.now().astimezone().isoformat(timespec="seconds")
            if (d.get("last_seen") or "")[:16] != now[:16]:  # write at most once a minute
                d["last_seen"] = now
                _save_devices(devices)
            d.setdefault("kind", "tv")
            return d
    return None


def _require_device(
    authorization: str | None = Header(default=None),
    t: str | None = Query(default=None, description="Token fallback for clients that can't set headers"),
) -> dict:
    token = authorization[7:] if authorization and authorization.lower().startswith("bearer ") else t
    if not token:
        raise HTTPException(status_code=401, detail="Falta el token del dispositivo.")
    device = _device_for_token(token)
    if device is None:
        raise HTTPException(status_code=401, detail="Dispositivo no autorizado. Vuelve a emparejarlo.")
    return device


# ── Library ───────────────────────────────────────────────────────────────────

def _track_id(rel_path: str) -> str:
    return hashlib.sha1(rel_path.encode("utf-8")).hexdigest()[:16]


def _read_tags(path: Path) -> dict:
    try:
        from mutagen import File as MutagenFile

        audio = MutagenFile(path, easy=True)
        if audio is None:
            return {}
        first = lambda k: (audio.get(k) or [None])[0]
        info = {
            "title": first("title"),
            "artist": first("artist"),
            "album": first("album"),
            "genre": first("genre"),
            "duration": round(audio.info.length, 1) if getattr(audio, "info", None) else None,
        }
        raw = MutagenFile(path)
        tags = getattr(raw, "tags", None)
        info["has_cover"] = bool(
            tags is not None and (
                (hasattr(tags, "getall") and tags.getall("APIC"))
                or "covr" in tags
                or getattr(raw, "pictures", None)
            )
        )
        return info
    except Exception:
        return {}


def _build_library(force: bool = False) -> list[dict]:
    if not force and state.library and time.time() - state.library_built_at < LIBRARY_CACHE_SECONDS:
        return state.library

    root = settings.MUSIC_DIR
    video_dir = settings.VIDEO_DIR.resolve()
    db = SessionLocal()
    try:
        genres = {m.filename: m.genre for m in db.query(Media.filename, Media.genre) if m.genre}
    finally:
        db.close()

    tracks, index = [], {}
    if root.exists():
        for f in root.rglob("*"):
            if not f.is_file() or f.suffix.lower() not in AUDIO_EXTS or f.name.startswith("."):
                continue
            if f.resolve().is_relative_to(video_dir):
                continue
            rel = f.relative_to(root).as_posix()
            tags = _read_tags(f)
            title, artist = tags.get("title"), tags.get("artist")
            if not title:
                stem = f.stem.lstrip("- ").strip()
                if " - " in stem:
                    artist = artist or stem.split(" - ", 1)[0].strip()
                    title = stem.split(" - ", 1)[1].strip()
                else:
                    title = stem
            parts = Path(rel).parts
            track_id = _track_id(rel)
            index[track_id] = f
            tracks.append({
                "id": track_id,
                "title": title,
                "artist": artist or "",
                "album": tags.get("album") or "",
                "genre": tags.get("genre") or genres.get(f.name) or "",
                "duration": tags.get("duration"),
                "playlist": parts[0] if len(parts) > 1 else "",
                "has_cover": bool(tags.get("has_cover")),
                "added_at": f.stat().st_mtime,
            })

    tracks.sort(key=lambda t: (t["artist"].lower(), t["title"].lower()))
    state.library, state.library_index, state.library_built_at = tracks, index, time.time()
    return tracks


def _resolve(track_id: str) -> Path:
    path = state.library_index.get(track_id)
    if path is None:
        _build_library(force=True)
        path = state.library_index.get(track_id)
    if path is None or not path.is_file():
        raise HTTPException(status_code=404, detail="Canción no encontrada.")
    return path


def _cover_bytes(path: Path) -> tuple[bytes, str] | None:
    try:
        from mutagen import File as MutagenFile

        audio = MutagenFile(path)
        tags = getattr(audio, "tags", None)
        if tags is not None and hasattr(tags, "getall"):
            frames = tags.getall("APIC")
            if frames:
                return frames[0].data, frames[0].mime or "image/jpeg"
        if tags is not None and "covr" in tags:
            return bytes(tags["covr"][0]), "image/jpeg"
        pictures = getattr(audio, "pictures", None)
        if pictures:
            return pictures[0].data, pictures[0].mime or "image/jpeg"
    except Exception:
        pass
    return None


# ── TV API (exposed on the LAN) ───────────────────────────────────────────────

tv_app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


class PairRequest(BaseModel):
    pin: str = Field(..., min_length=6, max_length=6)
    device_name: str = "Android TV"
    kind: Literal["tv", "remote"] = "tv"


class PlayedRequest(BaseModel):
    id: str
    seconds: float = Field(..., ge=0, le=24 * 3600)
    completed: bool = False


@tv_app.get("/tv/info")
async def tv_info() -> dict:
    return {"app": "sonero", "api": API_VERSION, "name": server_name(),
            "pairing_open": pairing_status() is not None}


@tv_app.post("/tv/pair")
async def tv_pair(body: PairRequest) -> dict:
    return _pair(body.pin, body.device_name, body.kind)


@tv_app.get("/tv/ping")
async def tv_ping(device: dict = Depends(_require_device)) -> dict:
    return {"ok": True, "device": device["name"], "server_name": server_name()}


@tv_app.get("/tv/library")
async def tv_library(device: dict = Depends(_require_device)) -> dict:
    tracks = await asyncio.to_thread(_build_library)
    playlists: dict[str, int] = {}
    for t in tracks:
        if t["playlist"]:
            playlists[t["playlist"]] = playlists.get(t["playlist"], 0) + 1
    return {
        "server_name": server_name(),
        "tracks": tracks,
        "playlists": [{"name": n, "count": c} for n, c in sorted(playlists.items())],
    }


@tv_app.get("/tv/stream/{track_id}")
async def tv_stream(track_id: str, device: dict = Depends(_require_device)):
    path = _resolve(track_id)
    media_type = {".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".aac": "audio/aac", ".flac": "audio/flac",
                  ".wav": "audio/wav", ".ogg": "audio/ogg", ".opus": "audio/ogg", ".webm": "audio/webm"}
    return FileResponse(path, media_type=media_type.get(path.suffix.lower(), "application/octet-stream"))


@tv_app.get("/tv/cover/{track_id}")
async def tv_cover(track_id: str, device: dict = Depends(_require_device)):
    cover = await asyncio.to_thread(_cover_bytes, _resolve(track_id))
    if cover is None:
        raise HTTPException(status_code=404, detail="Sin portada.")
    data, mime = cover
    return Response(content=data, media_type=mime, headers={"Cache-Control": "max-age=86400"})


@tv_app.post("/tv/played")
async def tv_played(body: PlayedRequest, device: dict = Depends(_require_device)) -> dict:
    """Count TV playback in Sonero's statistics (and therefore in the MCP server)."""
    path = _resolve(body.id)
    db = SessionLocal()
    try:
        media = db.query(Media).filter(Media.filename == path.name).first()
        if media is None:
            return {"logged": False}
        db.add(PlaybackEvent(media_id=media.id, duration_watched=body.seconds, completed=body.completed))
        db.commit()
        return {"logged": True}
    finally:
        db.close()


# ── Phase 2: remote control ───────────────────────────────────────────────────
#
# TVs keep a WebSocket open to the server (the TV is the client, so nothing
# listens on the TV). The server forwards commands from the desktop app or the
# phone remote, and TVs report what they are playing.

class TvCommand(BaseModel):
    action: Literal["play", "pause", "resume", "toggle", "next", "previous", "seek", "volume", "shuffle", "stop"]
    track_ids: list[str] | None = None
    # Library filenames (as the desktop app knows them); converted to track ids
    filenames: list[str] | None = None
    index: int = 0
    position: float | None = Field(default=None, ge=0, description="Seconds")
    shuffle: bool | None = None
    value: float | None = Field(default=None, ge=0, le=1, description="Volume 0-1")


def _ids_for_filenames(filenames: list[str]) -> list[str]:
    _build_library()
    known = set(state.library_index)
    ids = []
    for name in filenames:
        rel = name.replace("\\", "/").lstrip("/")
        tid = _track_id(rel)
        if tid not in known:
            # Desktop may send just the basename
            tid = next((i for i, p in state.library_index.items() if p.name == Path(rel).name), None)
        if tid:
            ids.append(tid)
    return ids


async def send_command(device_id: str, cmd: TvCommand) -> dict:
    ws = state.connections.get(device_id)
    if ws is None:
        raise HTTPException(status_code=409, detail="La TV no está conectada. Abre Sonero TV en el televisor.")
    payload = cmd.model_dump(exclude_none=True, exclude={"filenames"})
    if cmd.action == "play":
        ids = list(cmd.track_ids or [])
        if cmd.filenames:
            ids += await asyncio.to_thread(_ids_for_filenames, cmd.filenames)
        if not ids:
            raise HTTPException(status_code=400, detail="No hay canciones para reproducir.")
        payload["track_ids"] = ids[:1000]
        payload["index"] = max(0, min(cmd.index, len(payload["track_ids"]) - 1))
    try:
        await ws.send_json({"type": "command", **payload})
    except Exception:
        state.connections.pop(device_id, None)
        state.tv_states.pop(device_id, None)
        raise HTTPException(status_code=409, detail="Se perdió la conexión con la TV.")
    return {"sent": True}


@tv_app.websocket("/tv/ws")
async def tv_ws(ws: WebSocket, t: str | None = None):
    auth = ws.headers.get("authorization", "")
    token = auth[7:] if auth.lower().startswith("bearer ") else t
    device = _device_for_token(token)
    if device is None or device.get("kind", "tv") != "tv":
        await ws.close(code=4401)
        return
    await ws.accept()

    device_id = device["id"]
    previous = state.connections.get(device_id)
    state.connections[device_id] = ws
    if previous is not None:
        await _close_quietly(previous, 4000)  # superseded by this connection
    logger.info("TV connected: %s", device["name"])

    try:
        while True:
            msg = await ws.receive_json()
            if msg.get("type") == "state":
                track_id = msg.get("track_id")
                track = next((x for x in state.library if x["id"] == track_id), None) if track_id else None
                state.tv_states[device_id] = {
                    "track_id": track_id,
                    "title": track["title"] if track else msg.get("title"),
                    "artist": track["artist"] if track else msg.get("artist"),
                    "has_cover": bool(track and track["has_cover"]),
                    "playing": bool(msg.get("playing")),
                    "position": msg.get("position"),
                    "duration": msg.get("duration"),
                    "volume": msg.get("volume"),
                    "shuffle": bool(msg.get("shuffle")),
                    "updated_at": time.time(),
                }
            elif msg.get("type") == "ping":
                await ws.send_json({"type": "pong"})
    except (WebSocketDisconnect, RuntimeError, ValueError):
        pass
    finally:
        if state.connections.get(device_id) is ws:
            state.connections.pop(device_id, None)
            state.tv_states.pop(device_id, None)
        logger.info("TV disconnected: %s", device["name"])


def _online_tvs() -> list[dict]:
    return [d for d in list_devices() if d["kind"] == "tv" and d["online"]]


@tv_app.get("/", response_class=HTMLResponse)
async def remote_page() -> str:
    from services.tv_remote_page import REMOTE_PAGE_HTML
    return REMOTE_PAGE_HTML


@tv_app.get("/tv/remote/devices")
async def remote_devices(device: dict = Depends(_require_device)) -> dict:
    return {"server_name": server_name(), "tvs": _online_tvs()}


@tv_app.post("/tv/remote/devices/{device_id}/command")
async def remote_command(device_id: str, cmd: TvCommand, device: dict = Depends(_require_device)) -> dict:
    if not any(d["id"] == device_id for d in _online_tvs()):
        raise HTTPException(status_code=404, detail="TV no encontrada o desconectada.")
    return await send_command(device_id, cmd)


# ── Phase 3: lyrics and statistics for the TV ─────────────────────────────────

@tv_app.get("/tv/lyrics/{track_id}")
async def tv_lyrics(track_id: str, device: dict = Depends(_require_device)) -> dict:
    """
    Lyrics saved next to the song (.lrc). If there are none and this computer
    has internet, fetch them from lrclib once and save them for offline use.
    """
    path = _resolve(track_id)
    lrc = path.with_suffix(".lrc")
    if lrc.is_file():
        text = lrc.read_text(encoding="utf-8", errors="replace")
        return {"lyrics": text, "synced": "[" in text[:200], "source": "local"}

    track = next((x for x in await asyncio.to_thread(_build_library) if x["id"] == track_id), None)
    if track is None:
        return {"lyrics": None}
    try:
        from routers.metadata import _find_local_lrc, _lrclib_fetch
        import aiohttp

        local = await asyncio.to_thread(_find_local_lrc, track["title"], track["artist"])
        if local:
            return {"lyrics": local, "synced": "[" in local[:200], "source": "local"}
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=8)) as session:
            result = await _lrclib_fetch(session, track["title"], track["artist"])
        content = result and (result.get("synced") or result.get("plain"))
        if content:
            lrc.write_text(content, encoding="utf-8")
            return {"lyrics": content, "synced": bool(result.get("synced")), "source": "lrclib"}
    except Exception as e:  # offline or lrclib down: no lyrics, not an error
        logger.info("No lyrics for %s: %s", path.name, e)
    return {"lyrics": None}


@tv_app.get("/tv/stats")
async def tv_stats(days: int = Query(30, ge=1, le=3650), device: dict = Depends(_require_device)) -> dict:
    """Listening statistics for the TV's stats screen (same numbers the MCP server gives agents)."""
    from services import mcp_server

    summary = await asyncio.to_thread(mcp_server.get_listening_summary, days)
    top_tracks = (await asyncio.to_thread(mcp_server.get_top_tracks, days, 8))["tracks"]
    top_artists = (await asyncio.to_thread(mcp_server.get_top_artists, days, 8))["artists"]
    timeline = (await asyncio.to_thread(mcp_server.get_listening_timeline, min(days, 30), "day"))["series"]

    await asyncio.to_thread(_build_library)
    by_name = {p.name: tid for tid, p in state.library_index.items()}
    for t in top_tracks:
        t["track_id"] = by_name.get(Path(t.get("filename") or "").name)
    return {"summary": summary, "top_tracks": top_tracks, "top_artists": top_artists, "timeline": timeline}


# ── Discovery ─────────────────────────────────────────────────────────────────

class _DiscoveryProtocol(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        if data.strip() != DISCOVERY_REQUEST or not state.running:
            return
        reply = json.dumps({"app": "sonero", "api": API_VERSION, "name": server_name(),
                            "port": settings.TV_PORT}).encode()
        self.transport.sendto(reply, addr)


# ── Lifecycle ─────────────────────────────────────────────────────────────────

async def start() -> None:
    if state.running:
        return
    server = _EmbeddedServer(uvicorn.Config(
        tv_app, host="0.0.0.0", port=settings.TV_PORT, log_level="warning", lifespan="off",
    ))
    task = asyncio.create_task(server.serve())
    for _ in range(100):
        if server.started or task.done():
            break
        await asyncio.sleep(0.05)
    if not server.started:
        server.should_exit = True
        raise RuntimeError(f"No se pudo abrir el puerto {settings.TV_PORT} (¿está en uso por otra aplicación?)")
    state.server, state.server_task = server, task

    try:
        loop = asyncio.get_running_loop()
        transport, _ = await loop.create_datagram_endpoint(
            _DiscoveryProtocol, local_addr=("0.0.0.0", settings.TV_DISCOVERY_PORT), allow_broadcast=True,
        )
        state.discovery = transport
    except OSError as e:  # discovery is a convenience; manual IP still works
        logger.warning("TV discovery unavailable on UDP %s: %s", settings.TV_DISCOVERY_PORT, e)

    logger.info("Sonero TV listening on 0.0.0.0:%s", settings.TV_PORT)


async def stop() -> None:
    server, task, discovery = state.server, state.server_task, state.discovery
    state.server = state.server_task = state.discovery = None
    state.pairing = None
    for ws in list(state.connections.values()):
        await _close_quietly(ws, 1001)
    state.connections.clear()
    state.tv_states.clear()
    if discovery is not None:
        discovery.close()
    if server is not None:
        server.should_exit = True
        if task is not None:
            with contextlib.suppress(Exception, asyncio.CancelledError):
                await asyncio.wait_for(task, timeout=5)


async def set_enabled(enabled: bool) -> None:
    if enabled:
        await start()
    else:
        await stop()
    _set_setting(_ENABLED_KEY, "1" if enabled else "0")


async def start_if_enabled() -> None:
    if is_enabled():
        try:
            await start()
        except RuntimeError as e:
            logger.warning("Sonero TV could not start: %s", e)


def status() -> dict:
    return {
        "enabled": is_enabled(),
        "running": state.running,
        "ip": get_lan_ip(),
        "port": settings.TV_PORT,
        "server_name": server_name(),
        "pairing": pairing_status(),
        "devices": list_devices(),
    }
