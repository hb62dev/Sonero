import asyncio
import sys
from fastapi import APIRouter, File, UploadFile, HTTPException, Query
from pathlib import Path
from config import settings
from pydantic import BaseModel
from services import cookies
from services.benrio_client import benrio_client

router = APIRouter()


@router.get(
    "/settings/pick-folder",
    summary="Open native OS folder picker dialog",
)
async def pick_folder(
    title: str = Query("Selecciona una carpeta", description="Title for the dialog"),
) -> dict:
    """
    Opens the native OS folder-picker dialog (Windows/macOS/Linux)
    and returns the selected path. Returns empty string if cancelled.
    Uses tkinter which ships with Python's standard library.
    """
    def _open_dialog() -> str:
        import tkinter as tk
        from tkinter import filedialog

        root = tk.Tk()
        root.withdraw()            # Hide the root window
        root.attributes('-topmost', True)  # Bring dialog to front
        root.update()              # Process events so it appears on top

        folder = filedialog.askdirectory(
            title=title,
            mustexist=False,
        )

        root.destroy()
        return folder or ""

    # Run in a thread to avoid blocking the event loop
    loop = asyncio.get_event_loop()
    selected = await loop.run_in_executor(None, _open_dialog)

    return {"path": selected}

class CookieBrowserUpdate(BaseModel):
    browser: str | None = None  # None / "" disables reading browser cookies


@router.get(
    "/settings/cookies",
    summary="Current YouTube cookie source",
)
async def get_cookie_settings() -> dict:
    return {
        "browser": cookies.get_cookie_browser(),
        "has_cookie_file": (settings.TMP_DIR / "cookies.txt").exists(),
        "supported_browsers": list(cookies.SUPPORTED_BROWSERS),
    }


@router.put(
    "/settings/cookies/browser",
    summary="Opt in/out of reading YouTube cookies from a browser",
    description="Off by default. Enabling tests the browser once; on macOS this is "
                "when the system asks for keychain access.",
)
async def set_cookie_browser(body: CookieBrowserUpdate) -> dict:
    browser = (body.browser or "").strip().lower() or None
    if browser is not None:
        if browser not in cookies.SUPPORTED_BROWSERS:
            raise HTTPException(status_code=400, detail=f"Navegador no soportado: {browser}")
        loop = asyncio.get_running_loop()
        try:
            await loop.run_in_executor(None, cookies.test_browser_cookies, browser)
        except Exception as e:
            raise HTTPException(
                status_code=400,
                detail=f"No se pudieron leer las cookies de {browser}: {e}",
            )
    cookies.set_cookie_browser(browser)
    return await get_cookie_settings()


@router.post(
    "/settings/cookies/benrio",
    summary="Fetch YouTube cookies from Benrio Cloud",
)
async def sync_benrio_cookies() -> dict:
    """
    Downloads the centralized cookies.txt from Benrio and saves it to tmp/cookies.txt
    """
    settings.TMP_DIR.mkdir(exist_ok=True)
    cookie_path = settings.TMP_DIR / "cookies.txt"
    
    success = await benrio_client.fetch_youtube_cookies(cookie_path)
    if not success:
        raise HTTPException(status_code=500, detail="No se pudieron sincronizar las cookies desde Benrio.")
        
    return {"message": "Cookies sincronizadas exitosamente desde Benrio.", "path": str(cookie_path)}


@router.post(
    "/settings/cookies/upload",
    summary="Manually upload a cookies.txt file",
)
async def upload_cookies(file: UploadFile = File(...)) -> dict:
    """
    Accepts a cookies.txt file and saves it for yt-dlp to use.
    """
    if not file.filename.endswith(".txt"):
        raise HTTPException(status_code=400, detail="El archivo debe ser un .txt válido.")
        
    settings.TMP_DIR.mkdir(exist_ok=True)
    cookie_path = settings.TMP_DIR / "cookies.txt"
    
    try:
        content = await file.read(1_048_576 + 1)  # Read up to 1MB + 1 byte
        if len(content) > 1_048_576:
            raise HTTPException(status_code=413, detail="Archivo muy grande (máximo 1MB).")
        with open(cookie_path, "wb") as f:
            f.write(content)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error al guardar el archivo: {str(e)}")
        
    return {"message": "Archivo de cookies cargado y guardado correctamente."}

from pydantic import BaseModel
import re

class PathsUpdate(BaseModel):
    music_dir: str | None = None
    video_dir: str | None = None

@router.post(
    "/settings/paths",
    summary="Update download directories for music and video",
)
async def update_paths(payload: PathsUpdate) -> dict:
    env_path = settings.BASE_DIR / ".env"
    
    # Read existing or create empty
    env_content = ""
    if env_path.exists():
        with open(env_path, "r", encoding="utf-8") as f:
            env_content = f.read()

    updates_made = False

    if payload.music_dir:
        # Update in memory
        settings.MUSIC_DIR = Path(payload.music_dir).resolve()
        settings.MUSIC_DIR.mkdir(parents=True, exist_ok=True)
        # Update env string
        music_posix = settings.MUSIC_DIR.as_posix()
        if re.search(r"^MUSIC_DIR=.*$", env_content, re.MULTILINE):
            env_content = re.sub(r"^MUSIC_DIR=.*$", f'MUSIC_DIR="{music_posix}"', env_content, flags=re.MULTILINE)
        else:
            env_content += f'\nMUSIC_DIR="{music_posix}"\n'
        updates_made = True

    if payload.video_dir:
        settings.VIDEO_DIR = Path(payload.video_dir).resolve()
        settings.VIDEO_DIR.mkdir(parents=True, exist_ok=True)
        video_posix = settings.VIDEO_DIR.as_posix()
        if re.search(r"^VIDEO_DIR=.*$", env_content, re.MULTILINE):
            env_content = re.sub(r"^VIDEO_DIR=.*$", f'VIDEO_DIR="{video_posix}"', env_content, flags=re.MULTILINE)
        else:
            env_content += f'\nVIDEO_DIR="{video_posix}"\n'
        updates_made = True
        
    if updates_made:
        with open(env_path, "w", encoding="utf-8") as f:
            f.write(env_content.strip() + "\n")
            
    return {
        "message": "Rutas actualizadas correctamente",
        "music_dir": str(settings.MUSIC_DIR),
        "video_dir": str(settings.VIDEO_DIR)
    }
