import base64
from typing import List, Optional
from fastapi import APIRouter, HTTPException, Query
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TIT2, TPE1, TALB, TDRC, APIC
from pathlib import Path
from fastapi.responses import Response

import urllib.request

from config import settings
from schemas.metadata import MetadataResponse, MetadataBatchUpdateRequest, AutoFillRequest
from services.recognizer import recognize

router = APIRouter()

def read_mp3_metadata(file_path: Path) -> MetadataResponse:
    try:
        audio = MP3(file_path, ID3=ID3)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error reading {file_path.name}: {str(e)}")

    tags = audio.tags
    if tags is None:
        return MetadataResponse(filename=file_path.name)

    title = tags.get("TIT2").text[0] if tags.get("TIT2") else None
    artist = tags.get("TPE1").text[0] if tags.get("TPE1") else None
    album = tags.get("TALB").text[0] if tags.get("TALB") else None
    
    year_tag = tags.get("TDRC")
    year = str(year_tag.text[0]) if year_tag else None

    cover_art_base64 = None
    apic_frames = tags.getall("APIC")
    if apic_frames:
        cover_art_base64 = base64.b64encode(apic_frames[0].data).decode('utf-8')

    return MetadataResponse(
        filename=file_path.name,
        title=str(title) if title else None,
        artist=str(artist) if artist else None,
        album=str(album) if album else None,
        year=year,
        cover_art_base64=cover_art_base64
    )

def read_mp3_basic_info(file_path: Path) -> dict:
    try:
        audio = MP3(file_path, ID3=ID3)
    except Exception:
        return {}

    tags = audio.tags
    if tags is None:
        return {}

    title = tags.get("TIT2").text[0] if tags.get("TIT2") else None
    artist = tags.get("TPE1").text[0] if tags.get("TPE1") else None
    album = tags.get("TALB").text[0] if tags.get("TALB") else None
    
    year_tag = tags.get("TDRC")
    year = str(year_tag.text[0]) if year_tag else None

    has_cover = False
    if tags.getall("APIC"):
        has_cover = True

    return {
        "title": str(title) if title else None,
        "artist": str(artist) if artist else None,
        "album": str(album) if album else None,
        "year": year,
        "has_cover": has_cover
    }

@router.get(
    "/metadata",
    response_model=List[MetadataResponse],
    summary="Get metadata for all or specific downloaded MP3 files",
)
async def get_metadata(
    filenames: Optional[List[str]] = Query(None, description="List of filenames to get metadata for. Can be repeated.")
):
    settings.MUSIC_DIR.mkdir(exist_ok=True)
    responses = []
    
    if filenames:
        files_to_process = [settings.MUSIC_DIR / f for f in filenames]
    else:
        files_to_process = sorted(settings.MUSIC_DIR.iterdir(), key=lambda x: x.stat().st_ctime, reverse=True)
        files_to_process = [f for f in files_to_process if f.suffix == ".mp3"]
        
    for file_path in files_to_process:
        if not file_path.exists() or file_path.suffix != ".mp3":
            if filenames:
                raise HTTPException(status_code=404, detail=f"File {file_path.name} not found or not an MP3.")
            continue
        responses.append(read_mp3_metadata(file_path))
        
    return responses

@router.get(
    "/metadata/cover/{filename:path}",
    summary="Get cover art image for an MP3 file",
)
async def get_cover_art(filename: str):
    file_path = settings.MUSIC_DIR / filename
    if not file_path.exists() or file_path.suffix != ".mp3":
        raise HTTPException(status_code=404, detail=f"File {filename} not found")
        
    try:
        audio = MP3(file_path, ID3=ID3)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error reading MP3: {str(e)}")
        
    tags = audio.tags
    if tags is None:
        raise HTTPException(status_code=404, detail="No metadata found")
        
    apic_frames = tags.getall("APIC")
    if not apic_frames:
        raise HTTPException(status_code=404, detail="No cover art found")
        
    cover_data = apic_frames[0].data
    mime_type = apic_frames[0].mime or "image/jpeg"
    
    return Response(content=cover_data, media_type=mime_type)

import urllib.parse
import aiohttp
import logging

logger = logging.getLogger(__name__)

def _find_local_lrc(title: str, artist: str) -> str | None:
    """Search MUSIC_DIR for a .lrc file whose stem matches title or 'artist - title'."""
    search_dirs = [settings.MUSIC_DIR]
    if settings.MUSIC_DIR != settings.VIDEO_DIR:
        search_dirs.append(settings.VIDEO_DIR)
    
    candidates = [
        title.lower(),
        f"{artist} - {title}".lower(),
        f"{title} - {artist}".lower(),
    ]
    for d in search_dirs:
        if not d.exists():
            continue
        for lrc_file in d.rglob("*.lrc"):
            stem = lrc_file.stem.lower()
            if any(c in stem for c in candidates if c.strip()):
                logger.info(f"Found local .lrc: {lrc_file}")
                return lrc_file.read_text(encoding="utf-8", errors="replace")
    return None


import re

# Patterns to strip from YouTube/download video titles before searching lrclib
_YOUTUBE_SUFFIXES = re.compile(
    r'[\(\[\|]'
    r'(?:official\s+)?(?:hd\s+|4k\s+|full\s+)?'
    r'(?:music\s+)?(?:hd\s+)?(?:video|audio|lyric(?:s)?|visualizer|'
    r'animated\s+video|performance|live|clip|hq|remaster(?:ed)?|'
    r'version|vevo|mv|official|remake|cover)\b.*',
    re.IGNORECASE,
)
_FEATURING = re.compile(r'\s+(?:ft\.?|feat\.?|featuring)\s+.+', re.IGNORECASE)
_EXTRA_PARENS = re.compile(r'\s*\([^)]*\)\s*$')  # trailing (anything)
_ARTIST_PREFIX = re.compile(r'^([^-\u2013]+?)\s*[-\u2013]\s*(.+)$')  # "Artist - Title"


def _clean_title(title: str) -> str:
    """Strip YouTube noise from a track title to get the bare song name."""
    t = title.strip()
    t = _YOUTUBE_SUFFIXES.sub('', t)
    t = _FEATURING.sub('', t)
    t = _EXTRA_PARENS.sub('', t)
    return t.strip(' -|')


def _extract_artist_title(raw_title: str, raw_artist: str) -> tuple[str, str]:
    """
    If raw_title looks like 'Artist - Song Title (Official …)', return
    (cleaned_artist, cleaned_song). Otherwise return (raw_artist, cleaned_title).
    """
    cleaned = _clean_title(raw_title)
    m = _ARTIST_PREFIX.match(cleaned)
    if m:
        extracted_artist = m.group(1).strip()
        extracted_title  = _clean_title(m.group(2))
        # Prefer the embedded artist if raw_artist is generic / empty
        use_artist = raw_artist.strip() if raw_artist.strip() else extracted_artist
        return use_artist, extracted_title
    return raw_artist.strip(), cleaned


async def _lrclib_fetch(session: aiohttp.ClientSession, title: str, artist: str) -> dict | None:
    """
    Multi-strategy search against lrclib.net:
    1. Exact lookup with cleaned title + artist
    2. Fuzzy search with cleaned title + artist
    3. Fuzzy search with cleaned title only (no artist filter)
    Returns a dict with 'plain' and 'synced' keys, or None if nothing found.
    """
    timeout = aiohttp.ClientTimeout(total=12)

    # Sanitize before searching
    use_artist, use_title = _extract_artist_title(title, artist)
    logger.info(f"lrclib search: '{use_title}' by '{use_artist}' (raw: '{title}' / '{artist}')")

    async def _exact(t: str, a: str) -> dict | None:
        url = (
            f"https://lrclib.net/api/get"
            f"?track_name={urllib.parse.quote(t)}"
            f"&artist_name={urllib.parse.quote(a)}"
        )
        async with session.get(url, timeout=timeout) as resp:
            logger.info(f"  /api/get {resp.status} '{t}' – '{a}'")
            if resp.status == 200:
                data = await resp.json()
                plain  = data.get("plainLyrics")
                synced = data.get("syncedLyrics")
                if plain or synced:
                    return {"plain": plain, "synced": synced}
        return None

    async def _fuzzy(t: str, a: str = "") -> dict | None:
        url = (
            f"https://lrclib.net/api/search"
            f"?track_name={urllib.parse.quote(t)}"
            + (f"&artist_name={urllib.parse.quote(a)}" if a.strip() else "")
        )
        async with session.get(url, timeout=timeout) as resp:
            logger.info(f"  /api/search {resp.status} '{t}' – '{a}'")
            if resp.status == 200:
                results = await resp.json()
                if isinstance(results, list):
                    for hit in results:
                        plain  = hit.get("plainLyrics")
                        synced = hit.get("syncedLyrics")
                        if plain or synced:
                            logger.info(f"  fuzzy match: '{hit.get('trackName')}' by '{hit.get('artistName')}'")
                            return {"plain": plain, "synced": synced}
        return None

    # Strategy 1: exact with cleaned title + artist
    result = await _exact(use_title, use_artist)
    if result:
        return result

    # Strategy 2: fuzzy with cleaned title + artist
    result = await _fuzzy(use_title, use_artist)
    if result:
        return result

    # Strategy 3: fuzzy with cleaned title only (broadest)
    result = await _fuzzy(use_title)
    if result:
        return result

    return None


@router.get(
    "/metadata/lyrics",
    summary="Get lyrics for a track using LRCLIB",
)
async def get_lyrics(title: str, artist: str = ""):
    # 1. Try local .lrc file first (offline-friendly)
    local_lrc = _find_local_lrc(title, artist)
    if local_lrc:
        return {"plain": None, "synced": local_lrc, "source": "local"}

    # 2. Fetch from lrclib.net (exact + fuzzy fallback)
    try:
        async with aiohttp.ClientSession() as session:
            result = await _lrclib_fetch(session, title, artist)
            if result:
                return {"plain": result["plain"], "synced": result["synced"], "source": "lrclib"}
            return {
                "plain": None,
                "synced": None,
                "error": "No se encontraron letras para esta canción en lrclib.net.",
            }
    except aiohttp.ClientConnectorError:
        return {
            "plain": None,
            "synced": None,
            "error": "Sin conexión a internet. No se pueden obtener las letras en este momento.",
        }
    except Exception as e:
        logger.exception(f"Unexpected error fetching lyrics: {e}")
        return {"plain": None, "synced": None, "error": f"Error inesperado: {str(e)}"}


@router.post(
    "/metadata/lyrics/save",
    summary="Download and save .lrc file for a track from LRCLIB",
)
async def save_lyrics(filename: str, title: str, artist: str = ""):
    """
    Fetches synced (or plain) lyrics from lrclib.net and saves them as a .lrc
    file alongside the audio file in MUSIC_DIR (or VIDEO_DIR for videos).
    Returns the saved content on success.
    """
    # Determine which directory the file lives in
    media_file: Path | None = None
    for search_dir in [settings.MUSIC_DIR, settings.VIDEO_DIR]:
        candidate = search_dir / filename
        if candidate.exists():
            media_file = candidate
            break

    if media_file is None:
        raise HTTPException(status_code=404, detail=f"Archivo '{filename}' no encontrado.")

    # Fetch from lrclib (exact + fuzzy fallback)
    try:
        async with aiohttp.ClientSession() as session:
            result = await _lrclib_fetch(session, title, artist)

        if not result:
            return {"saved": False, "error": "No se encontraron letras para esta canción en lrclib.net."}

        synced: str | None = result["synced"]
        plain:  str | None = result["plain"]
        content = synced or plain

        lrc_path = media_file.with_suffix(".lrc")
        lrc_path.write_text(content, encoding="utf-8")
        logger.info(f"Saved .lrc to {lrc_path}")
        return {
            "saved": True,
            "path": str(lrc_path),
            "synced": synced,
            "plain": plain,
            "type": "synced" if synced else "plain",
        }

    except aiohttp.ClientConnectorError:
        return {"saved": False, "error": "Sin conexión a internet. No se pueden descargar las letras."}
    except Exception as e:
        logger.exception(f"Unexpected error saving lyrics: {e}")
        return {"saved": False, "error": f"Error inesperado: {str(e)}"}

@router.patch(
    "/metadata",
    summary="Update metadata for specific MP3 files",
)
async def update_metadata(request: MetadataBatchUpdateRequest):
    settings.MUSIC_DIR.mkdir(exist_ok=True)
    results = []
    
    for update in request.updates:
        file_path = settings.MUSIC_DIR / update.filename
        if not file_path.exists() or file_path.suffix != ".mp3":
            raise HTTPException(status_code=404, detail=f"File {update.filename} not found or not an MP3.")
            
        try:
            audio = MP3(file_path, ID3=ID3)
            if audio.tags is None:
                audio.add_tags()
            tags = audio.tags
            
            if update.title is not None:
                tags.add(TIT2(encoding=3, text=update.title))
            if update.artist is not None:
                tags.add(TPE1(encoding=3, text=update.artist))
            if update.album is not None:
                tags.add(TALB(encoding=3, text=update.album))
            if update.year is not None:
                tags.add(TDRC(encoding=3, text=update.year))
            if update.cover_art_base64 is not None:
                # Remove existing APIC frames
                tags.delall("APIC")
                if update.cover_art_base64 != "":
                    try:
                        # Sometimes there is a data URI prefix, remove it if it exists
                        b64_data = update.cover_art_base64
                        if "," in b64_data:
                            b64_data = b64_data.split(",")[1]
                            
                        image_data = base64.b64decode(b64_data)
                        
                        import io
                        from PIL import Image
                        
                        img = Image.open(io.BytesIO(image_data))
                        if img.mode != 'RGB':
                            img = img.convert('RGB')
                        out_io = io.BytesIO()
                        img.save(out_io, format='JPEG', quality=90)
                        jpeg_data = out_io.getvalue()
                        
                        tags.add(APIC(
                            encoding=3,
                            mime='image/jpeg', 
                            type=3, # 3 is for the cover(front) image
                            desc='Cover',
                            data=jpeg_data
                        ))
                    except Exception as e:
                        raise HTTPException(status_code=400, detail=f"Invalid base64 image for {update.filename}: {str(e)}")
                
            tags.save(file_path)
            results.append({"filename": update.filename, "status": "updated"})
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Error updating {update.filename}: {str(e)}")
            
    return {"message": "Metadata updated successfully", "results": results}

import uuid
from typing import Dict
from fastapi import BackgroundTasks
from schemas.jobs import JobResponse, BatchJobStatus

metadata_jobs: Dict[str, BatchJobStatus] = {}

@router.get(
    "/metadata/auto/jobs/{job_id}",
    response_model=BatchJobStatus,
    summary="Get autofill job status",
)
async def get_autofill_job(job_id: str):
    if job_id not in metadata_jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    return metadata_jobs[job_id]

@router.post(
    "/metadata/auto",
    response_model=JobResponse,
    summary="AutoFill metadata for specific MP3 files using Shazam",
)
async def autofill_metadata(request: AutoFillRequest, background_tasks: BackgroundTasks):
    settings.MUSIC_DIR.mkdir(exist_ok=True)
    job_id = str(uuid.uuid4())[:8]
    metadata_jobs[job_id] = BatchJobStatus(
        job_id=job_id,
        status="pending",
        total=len(request.filenames),
        current="⏳ Iniciando escaneo...",
    )
    background_tasks.add_task(_run_autofill, job_id, request.filenames)
    return JobResponse(job_id=job_id, status="pending", message="Escaneo iniciado")

async def _run_autofill(job_id: str, filenames: list[str]):
    metadata_jobs[job_id].status = "running"
    
    for filename in filenames:
        metadata_jobs[job_id].current = f"🔍 Escaneando {filename}..."
        file_path = settings.MUSIC_DIR / filename
        if not file_path.exists() or file_path.suffix != ".mp3":
            metadata_jobs[job_id].failed += 1
            metadata_jobs[job_id].errors.append(f"{filename}: File not found or not MP3")
            continue
            
        try:
            # 1. Recognize using Shazam
            track_info = await recognize(file_path)
            
            # Always search YouTube for the official thumbnail as requested
            from services import searcher
            import yt_dlp
            import asyncio
            from schemas.song import TrackInfo
            
            if track_info and track_info.title and track_info.artist:
                query = f"{track_info.artist} {track_info.title}"
            else:
                query = file_path.stem.replace("_", " ")
                
            yt_url = await searcher.search_youtube(query)
            if not yt_url and not track_info:
                metadata_jobs[job_id].failed += 1
                metadata_jobs[job_id].errors.append(f"{filename}: Not recognized by Shazam and no YouTube results")
                continue
                
            if yt_url:
                def _fetch_yt():
                    with yt_dlp.YoutubeDL({"quiet": True, "no_warnings": True, "noplaylist": True, "socket_timeout": 15, "nocheckcertificate": True}) as ydl:
                        return ydl.extract_info(yt_url, download=False)
                        
                yt_info = await asyncio.to_thread(_fetch_yt)
                if yt_info:
                    if not track_info:
                        track_info = TrackInfo(
                            title=yt_info.get("title", file_path.stem),
                            artist=yt_info.get("uploader", "Unknown"),
                            cover_url=yt_info.get("thumbnail")
                        )
                    else:
                        # Override Shazam's cover with YouTube's thumbnail
                        track_info.cover_url = yt_info.get("thumbnail")
                
            # 2. Open MP3
            audio = MP3(file_path, ID3=ID3)
            if audio.tags is None:
                audio.add_tags()
            tags = audio.tags
            
            # 3. Apply recognized metadata
            if track_info.title:
                tags.add(TIT2(encoding=3, text=track_info.title))
            if track_info.artist:
                tags.add(TPE1(encoding=3, text=track_info.artist))
            if track_info.album:
                tags.add(TALB(encoding=3, text=track_info.album))
            if track_info.year:
                tags.add(TDRC(encoding=3, text=str(track_info.year)))
                
            # 4. Download and apply Cover Art
            if track_info.cover_url:
                try:
                    import urllib.request
                    import io
                    from PIL import Image
                    
                    req = urllib.request.Request(
                        track_info.cover_url, 
                        headers={'User-Agent': 'Mozilla/5.0'}
                    )
                    with urllib.request.urlopen(req) as response:
                        img_data = response.read()
                    
                    try:
                        img = Image.open(io.BytesIO(img_data))
                        if img.mode != 'RGB':
                            img = img.convert('RGB')
                        out_io = io.BytesIO()
                        img.save(out_io, format='JPEG', quality=90)
                        jpeg_data = out_io.getvalue()
                        
                        tags.delall("APIC")
                        tags.add(APIC(
                            encoding=3, mime='image/jpeg', type=3, desc='Cover', data=jpeg_data
                        ))
                    except Exception as conv_e:
                        print(f"Error converting image for {filename}: {conv_e}")
                        tags.delall("APIC")
                        tags.add(APIC(
                            encoding=3, mime='image/jpeg', type=3, desc='Cover', data=img_data
                        ))
                except Exception as img_e:
                    print(f"Error downloading cover for {filename}: {img_e}")
                    
            tags.save(file_path)
            metadata_jobs[job_id].completed += 1
        except Exception as e:
            metadata_jobs[job_id].failed += 1
            metadata_jobs[job_id].errors.append(f"{filename}: {str(e)}")
            
    metadata_jobs[job_id].status = "done"
    metadata_jobs[job_id].current = f"✅ Completado: {metadata_jobs[job_id].completed} actualizados, {metadata_jobs[job_id].failed} fallidos."
