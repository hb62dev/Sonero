import asyncio
import csv
import os
import re
import shutil
from datetime import datetime
from glob import escape as glob_escape
from pathlib import Path
from typing import Optional

import yt_dlp

from schemas.song import TrackInfo
from config import settings
from database import SessionLocal
from models import Media, Playlist, PlaylistMedia
from services.benrio_client import benrio_client
from services import youtube

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

    # Detect ffmpeg location
    ffmpeg_path = shutil.which("ffmpeg")
    has_ffmpeg = ffmpeg_path is not None

    # Check common Windows install paths if not in PATH
    if not has_ffmpeg:
        common_paths = [
            Path(r"C:\ffmpeg\bin"),
            Path(r"C:\Program Files\ffmpeg\bin"),
            Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft" / "WinGet" / "Links",
        ]
        for p in common_paths:
            if (p / "ffmpeg.exe").exists():
                ffmpeg_path = str(p)
                has_ffmpeg = True
                break
        # Also check C:\ffmpeg subfolders (winget/GitHub extracts)
        if not has_ffmpeg:
            ffmpeg_root = Path(r"C:\ffmpeg")
            if ffmpeg_root.exists():
                for exe in ffmpeg_root.rglob("ffmpeg.exe"):
                    ffmpeg_path = str(exe.parent)
                    has_ffmpeg = True
                    break

    # Fallback: try imageio-ffmpeg bundled binary
    if not has_ffmpeg:
        try:
            import imageio_ffmpeg
            exe = imageio_ffmpeg.get_ffmpeg_exe()
            if exe and Path(exe).exists():
                # imageio-ffmpeg has a non-standard exe name, so we need to
                # create a copy named 'ffmpeg.exe' in the same directory
                exe_path = Path(exe)
                standard_ffmpeg = exe_path.parent / "ffmpeg.exe"
                standard_ffprobe = exe_path.parent / "ffprobe.exe"
                if not standard_ffmpeg.exists():
                    import shutil as sh
                    sh.copy2(str(exe_path), str(standard_ffmpeg))
                    print(f"[Downloader] Created ffmpeg.exe copy at: {standard_ffmpeg}")
                if not standard_ffprobe.exists():
                    import shutil as sh
                    sh.copy2(str(exe_path), str(standard_ffprobe))
                    print(f"[Downloader] Created ffprobe.exe copy at: {standard_ffprobe}")
                ffmpeg_path = str(exe_path.parent)
                has_ffmpeg = True
                print(f"[Downloader] Using imageio-ffmpeg: {ffmpeg_path}")
        except ImportError:
            pass

    ydl_opts = {
        "format": "bestaudio/best",
        "keepvideo": False,
        "outtmpl": output_template,
        "writethumbnail": True,
        "retries": 10,
        "fragment_retries": 10,
        "socket_timeout": 30,
        "nocheckcertificate": True,
        "quiet": True,
        "no_warnings": True,
    }

    if has_ffmpeg:
        if ffmpeg_path and os.path.isdir(ffmpeg_path):
            ydl_opts["ffmpeg_location"] = ffmpeg_path
        ydl_opts["postprocessors"] = [
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
        ]
    else:
        # No ffmpeg: download best audio without conversion
        ydl_opts["format"] = "bestaudio[ext=m4a]/bestaudio/best"
        ydl_opts["postprocessors"] = []

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

    ydl_opts = youtube.apply_common(ydl_opts)

    # Don't write thumbnails if we can't embed them (no ffmpeg)
    if not has_ffmpeg:
        ydl_opts["writethumbnail"] = False

    # ── Fetch thumbnail URL from YouTube before downloading ──
    if not track.cover_url:
        try:
            extract_opts = {
                "quiet": True,
                "no_warnings": True,
                "socket_timeout": 10,
                "noplaylist": True,
                "nocheckcertificate": True,
            }
            extract_opts = youtube.apply_common(extract_opts)
            def _extract_thumb():
                with yt_dlp.YoutubeDL(extract_opts) as ydl:
                    info = ydl.extract_info(url, download=False)
                    return info.get("thumbnail", "") if info else ""
            thumb = await asyncio.to_thread(_extract_thumb)
            if thumb:
                track.cover_url = thumb
        except Exception as e:
            print(f"[Downloader] Could not fetch thumbnail: {e}")

    def _download() -> None:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])

    await youtube.pace()
    await asyncio.to_thread(_download)

    # Find the actual downloaded file (could be .mp3, .m4a, .webm, .opus, etc.)
    base_path = Path(output_template)
    actual_file = None
    actual_fmt = "mp3"

    # Check common audio extensions in priority order
    for ext in [".mp3", ".m4a", ".opus", ".webm", ".ogg", ".wav", ".aac"]:
        candidate = base_path.with_suffix(ext)
        if candidate.exists() and candidate.stat().st_size > 10000:  # > 10KB = real audio
            actual_file = candidate
            actual_fmt = ext.lstrip(".")
            break

    # Clean up leftover thumbnail files
    for ext in [".webp", ".jpg", ".png", ".jpeg"]:
        thumb = base_path.with_suffix(ext)
        if thumb.exists():
            try:
                thumb.unlink()
                print(f"[Downloader] Cleaned up thumbnail: {thumb.name}")
            except Exception:
                pass

    # Only log to DB if a real audio file was downloaded
    if actual_file and actual_file.exists():
        _log_to_db(track, actual_file.name, playlist, media_type="music", fmt=actual_fmt)
        return actual_file
    else:
        print(f"[Downloader] WARNING: No audio file found after download for: {track.title}")
        # Don't log failed downloads to DB
        return base_path.with_suffix(f".{actual_fmt}")


async def get_video_info(url: str) -> dict:
    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": 15,
        "noplaylist": True,
        "nocheckcertificate": True,
    }
    
    ydl_opts = youtube.apply_common(ydl_opts)

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
    
    def _get_info():
        with yt_dlp.YoutubeDL(youtube.apply_common({"quiet": True, "nocheckcertificate": True})) as ydl:
            info = ydl.extract_info(url, download=False)
            return (info.get("title", "video"), info.get("thumbnail", ""))
            
    title, thumbnail_url = await asyncio.to_thread(_get_info)
    filename = _sanitize(title)
    
    is_audio = format_id == "bestaudio/best"
    final_ext = "mp3" if is_audio else "mp4"
    output_template = str(dest_dir / f"{filename}.%(ext)s")
    
    class YTDLPLogger:
        def __init__(self):
            self.has_warning = False
            self.warning_msg = None
            self.last_error = None
        def debug(self, msg): pass
        def info(self, msg): pass
        def warning(self, msg):
            if "HTTP Error 429" in msg or "Unable to download video subtitles" in msg:
                self.has_warning = True
                self.warning_msg = "Advertencia: YouTube bloqueó temporalmente la descarga de subtítulos (HTTP 429)."
        def error(self, msg):
            self.last_error = msg
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
    
    # Detect ffmpeg for video postprocessing
    ffmpeg_path = shutil.which("ffmpeg")
    if not ffmpeg_path:
        common_paths = [
            Path(r"C:\ffmpeg\bin"),
            Path(r"C:\Program Files\ffmpeg\bin"),
        ]
        for p in common_paths:
            if (p / "ffmpeg.exe").exists():
                ffmpeg_path = str(p)
                break
        if not ffmpeg_path:
            try:
                import imageio_ffmpeg
                exe = imageio_ffmpeg.get_ffmpeg_exe()
                if exe and Path(exe).exists():
                    exe_path = Path(exe)
                    standard_ffmpeg = exe_path.parent / "ffmpeg.exe"
                    standard_ffprobe = exe_path.parent / "ffprobe.exe"
                    if not standard_ffmpeg.exists():
                        import shutil as sh
                        sh.copy2(str(exe_path), str(standard_ffmpeg))
                    if not standard_ffprobe.exists():
                        import shutil as sh
                        sh.copy2(str(exe_path), str(standard_ffprobe))
                    ffmpeg_path = str(exe_path.parent)
            except ImportError:
                pass
    else:
        ffmpeg_path = str(Path(ffmpeg_path).parent)
    
    if ffmpeg_path:
        ydl_opts["ffmpeg_location"] = ffmpeg_path
    
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

    ydl_opts = youtube.apply_common(ydl_opts)

    def _download():
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])

    await youtube.pace()
    await asyncio.to_thread(_download)
    # ignoreerrors keeps optional parts (subtitles) from failing the download,
    # but it also swallows real failures: make sure the file exists
    if not any(dest_dir.glob(f"{glob_escape(filename)}.*")):
        raise RuntimeError(logger.last_error or "YouTube no entregó el archivo.")
    
    # Call Benrio to analyze the video and get a playlist suggestion
    benrio_response = await benrio_client.analyze_media(title=title, artist="")
    suggested_playlist = benrio_response.get("suggested_playlist")
    
    # Save video to db
    track_info = TrackInfo(
        title=title,
        artist="", # Video channel name could go here, but keep empty for now
        cover_url=thumbnail_url or ""
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
    }
    ydl_opts = youtube.apply_common(ydl_opts)

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

