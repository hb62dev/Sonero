import asyncio
import csv
import re
from datetime import datetime
from pathlib import Path
from typing import Optional

import yt_dlp

from schemas.song import TrackInfo
from config import settings
from database import SessionLocal
from models import Media, Playlist, PlaylistMedia
from services.benrio_client import benrio_client
from services.cookies import CookieManager

class PauseDownload(Exception):
    pass


def _sanitize(name: str) -> str:
    """Remove characters that are invalid in filenames."""
    return re.sub(r'[\\/:*?"<>|]', "_", name).strip()


def _log_to_db(track: TrackInfo, filename: str, playlist_name: str | None, media_type: str = "music", fmt: str = "mp3") -> None:
    """
    Appends a downloaded track to the SQLite database.
    """
    db = SessionLocal()
    try:
        # Check if already exists by filename
        existing = db.query(Media).filter(Media.filename == filename).first()
        if existing:
            return

        media = Media(
            type=media_type,
            title=track.title,
            artist=track.artist,
            album=track.album or "",
            genre=track.genre or "",
            year=str(track.year) if track.year else "",
            filename=filename,
            format=fmt,
            cover_url=track.cover_url or "",
            shazam_url=track.shazam_url or "",
            added_at=datetime.utcnow()
        )
        db.add(media)
        db.flush()

        if playlist_name:
            playlist = db.query(Playlist).filter(Playlist.name == playlist_name).first()
            if not playlist:
                playlist = Playlist(name=playlist_name, is_smart=False)
                db.add(playlist)
                db.flush()
            
            pm = PlaylistMedia(
                playlist_id=playlist.id,
                media_id=media.id,
                added_at=datetime.utcnow()
            )
            db.add(pm)

        db.commit()
    except Exception as e:
        print(f"Error saving to DB: {e}")
        db.rollback()
    finally:
        db.close()


async def download_mp3(
    url: str,
    track: TrackInfo,
    playlist: str | None = None,
    progress_callback=None,
    check_pause_callback=None,
) -> Path:
    """
    Downloads audio from `url` and converts it to MP3 (320 kbps) via FFmpeg.

    Args:
        url:      YouTube URL to download from.
        track:    Track metadata from Shazam.
        playlist: Optional subfolder name inside DOWNLOADS_DIR.
                  If provided, the file is saved to DOWNLOADS_DIR/playlist/.
                  If None, saved to DOWNLOADS_DIR root.

    Returns the path to the downloaded .mp3 file.
    Also appends the track to music_library.csv automatically.
    """
    # Resolve destination directory
    dest_dir = settings.MUSIC_DIR / playlist if playlist else settings.MUSIC_DIR
    dest_dir.mkdir(parents=True, exist_ok=True)

    filename = _sanitize(f"{track.artist} - {track.title}")
    output_template = str(dest_dir / filename)

    ydl_opts = {
        "format": "bestaudio/best",
        "keepvideo": False,
        "outtmpl": output_template,
        "writethumbnail": True,
        "retries": 5,
        "socket_timeout": 30,
        "nocheckcertificate": True,
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "320",
            },
            {
                "key": "FFmpegThumbnailsConvertor",
                "format": "jpg",
            },
            {
                "key": "FFmpegMetadata",
                "add_metadata": True,
            },
            {
                "key": "EmbedThumbnail",
                "already_have_thumbnail": False,
            }
        ],
        "quiet": True,
        "no_warnings": True,
        "http_headers": {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            )
        },
    }

    if progress_callback or check_pause_callback:
        def my_hook(d):
            if check_pause_callback and check_pause_callback():
                raise PauseDownload("Download paused by user")
            if d['status'] == 'downloading':
                if progress_callback:
                    dl = d.get('downloaded_bytes', 0)
                    total = d.get('total_bytes') or d.get('total_bytes_estimate')
                    if total and total > 0:
                        percent = dl / total
                        progress_callback(70 + int(percent * 28))
            elif d['status'] == 'finished':
                if progress_callback:
                    progress_callback(99)
        ydl_opts["progress_hooks"] = [my_hook]

    ydl_opts.update(CookieManager.get_cookie_opts())

    def _download() -> None:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])

    await asyncio.to_thread(_download)

    mp3_path = Path(output_template).with_suffix(".mp3")

    # Log to DB
    _log_to_db(track, mp3_path.name, playlist, media_type="music", fmt="mp3")

    return mp3_path


async def get_video_info(url: str) -> dict:
    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": 15,
        "noplaylist": True,
        "nocheckcertificate": True,
        "http_headers": {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            )
        },
    }
    
    ydl_opts.update(CookieManager.get_cookie_opts())

    def _extract():
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            return ydl.extract_info(url, download=False)

    info = await asyncio.to_thread(_extract)
    if not info:
        raise ValueError("No info found")

    formats = []
    # Add Audio Only option
    formats.append({
        "format_id": "bestaudio/best",
        "resolution": "Audio Only",
        "ext": "mp3",
        "filesize_mb": None,
        "is_audio_only": True
    })

    # Find video resolutions
    seen_heights = set()
    for f in reversed(info.get("formats", [])):
        if f.get("vcodec") != "none" and f.get("height"):
            h = f["height"]
            if h not in seen_heights and h in [144, 240, 360, 480, 720, 1080, 1440, 2160]:
                seen_heights.add(h)
                fs = f.get("filesize") or f.get("filesize_approx")
                fs_mb = round(fs / 1024 / 1024, 2) if fs else None
                
                has_audio = f.get("acodec") != "none"
                video_format = f['format_id']
                final_format = video_format if has_audio else f"{video_format}+bestaudio/best"

                formats.append({
                    "format_id": final_format,
                    "resolution": f"{h}p",
                    "ext": "mp4",
                    "filesize_mb": fs_mb,
                    "is_audio_only": False
                })

    formats.sort(key=lambda x: int(x["resolution"].replace("p", "")) if "p" in x["resolution"] else 0, reverse=True)

    return {
        "title": info.get("title", "Unknown Title"),
        "thumbnail": info.get("thumbnail", ""),
        "formats": formats
    }


async def download_video(url: str, format_id: str, progress_callback=None, check_pause_callback=None) -> tuple[Path, str | None]:
    dest_dir = settings.VIDEO_DIR
    dest_dir.mkdir(parents=True, exist_ok=True)
    
    def _get_title():
        with yt_dlp.YoutubeDL({"quiet": True, "nocheckcertificate": True}) as ydl:
            return ydl.extract_info(url, download=False).get("title", "video")
            
    title = await asyncio.to_thread(_get_title)
    filename = _sanitize(title)
    
    is_audio = format_id == "bestaudio/best"
    final_ext = "mp3" if is_audio else "mp4"
    output_template = str(dest_dir / f"{filename}.%(ext)s")
    
    class YTDLPLogger:
        def __init__(self):
            self.has_warning = False
            self.warning_msg = None
        def debug(self, msg): pass
        def info(self, msg): pass
        def warning(self, msg):
            if "HTTP Error 429" in msg or "Unable to download video subtitles" in msg:
                self.has_warning = True
                self.warning_msg = "Advertencia: YouTube bloqueó temporalmente la descarga de subtítulos (HTTP 429)."
        def error(self, msg):
            self.warning(msg)

    logger = YTDLPLogger()
    
    ydl_opts = {
        "format": format_id,
        "outtmpl": output_template,
        "quiet": True,
        "no_warnings": False,
        "logger": logger,
        "socket_timeout": 30,
        "noplaylist": True,
        "nocheckcertificate": True,
        "writesubtitles": True,
        "writeautomaticsub": True,
        "subtitleslangs": ["en", "es", "es-419"],
        "ignoreerrors": True,
    }
    
    if progress_callback or check_pause_callback:
        def my_hook(d):
            if check_pause_callback and check_pause_callback():
                raise PauseDownload("Download paused by user")
            if d['status'] == 'downloading':
                if progress_callback:
                    dl = d.get('downloaded_bytes', 0)
                    total = d.get('total_bytes') or d.get('total_bytes_estimate')
                    if total and total > 0:
                        percent = dl / total
                        progress_callback(int(percent * 98)) # 0 to 98
            elif d['status'] == 'finished':
                if progress_callback:
                    progress_callback(99)
        ydl_opts["progress_hooks"] = [my_hook]
    
    postprocessors = []
    if is_audio:
        postprocessors.append({
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "320",
        })
    else:
        postprocessors.append({
            "key": "FFmpegEmbedSubtitle",
        })
        
    if postprocessors:
        ydl_opts["postprocessors"] = postprocessors

    ydl_opts.update(CookieManager.get_cookie_opts())

    def _download():
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])
            
    await asyncio.to_thread(_download)
    
    # Call Benrio to analyze the video and get a playlist suggestion
    benrio_response = await benrio_client.analyze_media(title=title, artist="")
    suggested_playlist = benrio_response.get("suggested_playlist")
    
    # Save video to db
    track_info = TrackInfo(
        title=title,
        artist="", # Video channel name could go here, but keep empty for now
        cover_url=""
    )
    # The actual filename relative to the videos folder or just the name
    saved_filename = f"videos/{filename}.{final_ext}"
    _log_to_db(track_info, saved_filename, suggested_playlist, media_type="music" if is_audio else "video", fmt=final_ext)
    
    return dest_dir / f"{filename}.{final_ext}", logger.warning_msg


async def get_playlist_info(url: str) -> dict:
    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": 15,
        "extract_flat": True,
        "nocheckcertificate": True,
        "http_headers": {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            )
        },
    }
    ydl_opts.update(CookieManager.get_cookie_opts())

    def _extract():
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            return ydl.extract_info(url, download=False)

    info = await asyncio.to_thread(_extract)
    if not info:
        raise ValueError("No playlist info found")

    entries = info.get("entries", [])
    videos = []
    for entry in entries:
        if not entry:
            continue
        v_url = entry.get("url") or f"https://www.youtube.com/watch?v={entry.get('id')}"
        duration = entry.get("duration")
        videos.append({
            "url": v_url,
            "title": entry.get("title") or "Unknown Video",
            "duration": int(duration) if duration is not None else None,
        })

    return {
        "title": info.get("title") or "Unknown Playlist",
        "thumbnail": info.get("thumbnail") or "",
        "videos": videos
    }

