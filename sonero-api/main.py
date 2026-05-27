import os
import sys

# ── Force UTF-8 stdout/stderr on Windows ─────────────────────────────────────
# Without this, Python uses cp1252 by default, which crashes when yt-dlp
# returns video titles containing emojis or non-Latin characters.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
os.environ["PYTHONIOENCODING"] = "utf-8"

from contextlib import asynccontextmanager

# ── PyInstaller SSL fix ───────────────────────────────────────────────────────
# When bundled with PyInstaller, the certifi CA bundle is inside _internal/.
# We must set SSL_CERT_FILE so yt-dlp / httpx / aiohttp can verify SSL certs.
import certifi
os.environ.setdefault("SSL_CERT_FILE", certifi.where())
os.environ.setdefault("REQUESTS_CA_BUNDLE", certifi.where())

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import settings
from routers import listen, batch, downloads, devices, playlists, metadata, analytics, search, settings as settings_router, smart_music, auth, sync
from init_db import init_db


# ── Lifespan ──────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create required directories on startup."""
    settings.MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    settings.VIDEO_DIR.mkdir(parents=True, exist_ok=True)
    settings.TMP_DIR.mkdir(parents=True, exist_ok=True)
    settings.RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    # Initialize DB (creates tables and migrates if needed)
    init_db()
    yield


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="🎵 Sonero API",
    description=(
        "Microservicio que escucha el micrófono, reconoce canciones, "
        "las busca en YouTube y las descarga como MP3 a 320 kbps.\n\n"
        "**Endpoints principales:**\n"
        "- `POST /api/v1/listen` → Pipeline completo\n"
        "- `POST /api/v1/batch/from-csv` → Descargar toda tu librería\n"
        "- `GET /api/v1/downloads` → Ver archivos descargados\n"
        "- `GET /api/v1/playlists` → Gestionar playlists\n"
    ),
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Routers ───────────────────────────────────────────────────────────────────

app.include_router(listen.router,     prefix="/api/v1", tags=["🎙️ Listen & Recognize"])
app.include_router(batch.router,      prefix="/api/v1", tags=["📥 Batch CSV"])
app.include_router(downloads.router,  prefix="/api/v1", tags=["📂 Downloads"])
app.include_router(devices.router,    prefix="/api/v1", tags=["🎛️ Audio Devices"])
app.include_router(playlists.router,  prefix="/api/v1", tags=["🎵 Playlists"])
app.include_router(metadata.router,   prefix="/api/v1", tags=["🏷️ Metadata"])
app.include_router(analytics.router,  prefix="/api/v1", tags=["📊 Analytics"])
app.include_router(settings_router.router, prefix="/api/v1", tags=["⚙️ Settings"])
app.include_router(search.router,       prefix="/api/v1", tags=["🔍 Search"])
app.include_router(smart_music.router, prefix="/api/v1", tags=["🧠 Smart Music"])
app.include_router(auth.router, prefix="/api/v1", tags=["🔒 Authentication"])
app.include_router(sync.router, prefix="/api/v1", tags=["🔄 Sync"])


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health", tags=["❤️ Health"])
async def health() -> dict:
    return {
        "status": "ok",
        "service": "sonero-api",
        "version": "1.0.0",
        "music_dir": str(settings.MUSIC_DIR),
        "video_dir": str(settings.VIDEO_DIR),
    }


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    uvicorn.run(
        app,
        host=settings.HOST,
        port=settings.PORT,
    )
