from fastapi import APIRouter, HTTPException, File, UploadFile
from fastapi.responses import FileResponse
from pathlib import Path
from pydantic import BaseModel
from config import settings
from routers.metadata import read_mp3_basic_info

router = APIRouter()


def _get_root() -> Path:
    p = settings.MUSIC_DIR
    p.mkdir(exist_ok=True)
    return p


def _count_tracks(d: Path) -> int:
    valid_extensions = {".mp3", ".m4a", ".mp4", ".webm", ".mkv", ".avi", ".mov"}
    try:
        return len([
            f for f in d.iterdir()
            if f.is_file() and f.suffix.lower() in valid_extensions
        ])
    except Exception:
        return 0


@router.get(
    "/playlists",
    summary="List playlists",
    description="Returns all sub-folders inside the downloads directory. Each folder is a playlist.",
)
async def list_playlists() -> dict:
    root = _get_root()
    playlists = []
    for d in sorted(root.iterdir()):
        if d.is_dir():
            cover_file = d / "cover.jpg"
            has_cover = cover_file.exists()
            playlists.append({
                "name": d.name,
                "path": str(d),
                "track_count": _count_tracks(d),
                "cover_url": f"/api/v1/playlists/{d.name}/cover" if has_cover else None,
            })
    return {"root": str(root), "playlists": playlists}


# ── Create playlist ───────────────────────────────────────────────────────────

class CreatePlaylistRequest(BaseModel):
    name: str


@router.post("/playlists", summary="Create a playlist folder")
async def create_playlist(body: CreatePlaylistRequest) -> dict:
    name = body.name.strip()
    if not name or any(c in name for c in r'\/:*?"<>|'):
        raise HTTPException(status_code=400, detail="Invalid playlist name.")
    playlist_dir = _get_root() / name
    if playlist_dir.exists():
        raise HTTPException(status_code=409, detail=f"Playlist '{name}' already exists.")
    playlist_dir.mkdir()
    return {"message": f"Playlist '{name}' created.", "path": str(playlist_dir)}


# ── Rename playlist ───────────────────────────────────────────────────────────

class RenamePlaylistRequest(BaseModel):
    old_name: str
    new_name: str


@router.patch("/playlists/rename", summary="Rename a playlist folder")
async def rename_playlist(body: RenamePlaylistRequest) -> dict:
    root = _get_root()
    old = root / body.old_name
    new = root / body.new_name.strip()
    if not old.exists() or not old.is_dir():
        raise HTTPException(status_code=404, detail=f"Playlist '{body.old_name}' not found.")
    if new.exists():
        raise HTTPException(status_code=409, detail=f"Playlist '{body.new_name}' already exists.")
    old.rename(new)
    return {"message": f"Renamed '{body.old_name}' to '{body.new_name}'"}


# ── Delete playlist ───────────────────────────────────────────────────────────

@router.delete(
    "/playlists/{name}",
    summary="Delete a playlist folder",
    description="Deletes the folder and moves its files back to the library root.",
)
async def delete_playlist(name: str) -> dict:
    root = _get_root()
    playlist_dir = root / name
    if not playlist_dir.exists() or not playlist_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Playlist '{name}' not found.")
    moved = []
    valid_extensions = {".mp3", ".m4a", ".mp4", ".webm", ".mkv", ".avi", ".mov"}
    for f in playlist_dir.iterdir():
        if f.is_file() and f.suffix.lower() in valid_extensions:
            f.rename(root / f.name)
            moved.append(f.name)
    playlist_dir.rmdir()
    return {"message": f"Playlist '{name}' deleted.", "moved_tracks": moved}


# ── Move track ────────────────────────────────────────────────────────────────

class MoveTrackRequest(BaseModel):
    filename: str
    from_playlist: str | None = None  # None = library root
    to_playlist: str | None = None    # None = library root


@router.post(
    "/tracks/move",
    summary="Move a track between playlists",
    description="Use null for from_playlist/to_playlist to refer to the library root.",
)
async def move_track(body: MoveTrackRequest) -> dict:
    root = _get_root()
    src_dir = root / body.from_playlist if body.from_playlist else root
    dst_dir = root / body.to_playlist   if body.to_playlist   else root
    src = src_dir / body.filename
    dst = dst_dir / body.filename
    if not src.exists():
        raise HTTPException(status_code=404, detail=f"Track '{body.filename}' not found.")
    if not dst_dir.exists():
        raise HTTPException(status_code=404, detail=f"Destination '{body.to_playlist}' not found.")
    if dst.exists():
        raise HTTPException(status_code=409, detail=f"'{body.filename}' already exists in destination.")
    src.rename(dst)
    return {"message": f"Moved '{body.filename}'", "new_path": str(dst)}


# ── List tracks in a playlist ─────────────────────────────────────────────────

@router.get("/playlists/{name}/tracks", summary="List tracks in a playlist")
async def list_playlist_tracks(name: str) -> dict:
    root = _get_root()
    playlist_dir = root / name
    if not playlist_dir.exists() or not playlist_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Playlist '{name}' not found.")
    
    tracks = []
    valid_extensions = {".mp3", ".m4a", ".mp4", ".webm", ".mkv", ".avi", ".mov"}
    
    for f in sorted(playlist_dir.iterdir(), key=lambda x: x.stat().st_ctime, reverse=True):
        if f.is_file() and f.suffix.lower() in valid_extensions:
            stat = f.stat()
            meta = read_mp3_basic_info(f) if f.suffix.lower() == ".mp3" else {}
            
            if f.is_relative_to(settings.VIDEO_DIR) and settings.VIDEO_DIR != settings.MUSIC_DIR:
                filename = f"videos/{str(f.relative_to(settings.VIDEO_DIR)).replace(chr(92), '/')}"
            else:
                filename = str(f.relative_to(settings.MUSIC_DIR)).replace(chr(92), '/')
                
            tracks.append({
                "filename": filename,
                "size_mb": round(stat.st_size / 1048576, 2),
                "created_at": stat.st_ctime,
                "title": meta.get("title") or f.stem,
                "artist": meta.get("artist") or "",
                "album": meta.get("album") or "",
                "year": meta.get("year") or "",
                "cover_url": f"/api/v1/metadata/cover/{filename}" if meta.get("has_cover") and f.suffix.lower() == ".mp3" else None,
            })
    return {"playlist": name, "total": len(tracks), "tracks": tracks}


# ── Playlist cover image ──────────────────────────────────────────────────────

_ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
_MAX_COVER_SIZE = 5 * 1024 * 1024  # 5MB

@router.post(
    "/playlists/{name}/cover",
    summary="Upload a cover image for a playlist",
    description="Accepts an image file (jpg, png, webp) and saves it as the playlist cover.",
)
async def upload_playlist_cover(name: str, file: UploadFile = File(...)) -> dict:
    root = _get_root()
    playlist_dir = root / name
    if not playlist_dir.exists() or not playlist_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Playlist '{name}' not found.")

    # Validate file extension
    ext = Path(file.filename).suffix.lower() if file.filename else ""
    if ext not in _ALLOWED_IMAGE_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Formato no válido. Usa JPG, PNG o WebP.")

    # Read with size limit
    content = await file.read(_MAX_COVER_SIZE + 1)
    if len(content) > _MAX_COVER_SIZE:
        raise HTTPException(status_code=413, detail="Imagen muy grande (máximo 5MB).")

    # Save as cover.jpg (always overwrite)
    cover_path = playlist_dir / "cover.jpg"
    with open(cover_path, "wb") as f:
        f.write(content)

    return {"message": f"Cover de '{name}' actualizado.", "cover_url": f"/api/v1/playlists/{name}/cover"}


@router.get(
    "/playlists/{name}/cover",
    summary="Get the cover image for a playlist",
)
async def get_playlist_cover(name: str):
    root = _get_root()
    playlist_dir = root / name
    if not playlist_dir.exists() or not playlist_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Playlist '{name}' not found.")

    cover_path = playlist_dir / "cover.jpg"
    if not cover_path.exists():
        raise HTTPException(status_code=404, detail="No cover image found.")

    return FileResponse(
        path=str(cover_path),
        media_type="image/jpeg",
        filename=f"{name}_cover.jpg",
    )


@router.delete(
    "/playlists/{name}/cover",
    summary="Delete the cover image for a playlist",
)
async def delete_playlist_cover(name: str) -> dict:
    root = _get_root()
    playlist_dir = root / name
    if not playlist_dir.exists() or not playlist_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"Playlist '{name}' not found.")

    cover_path = playlist_dir / "cover.jpg"
    if cover_path.exists():
        cover_path.unlink()

    return {"message": f"Cover de '{name}' eliminado."}
