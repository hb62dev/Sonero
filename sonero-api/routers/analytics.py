from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime, timedelta
from pydantic import BaseModel

from database import get_db
from models import PlaybackEvent, Media
from services.gemini_service import check_activity_and_maybe_curate

router = APIRouter()

class PlaybackLogRequest(BaseModel):
    media_id: int
    duration_watched: float
    completed: bool

class PlaybackLogByFilenameRequest(BaseModel):
    filename: str
    duration_watched: float
    completed: bool

@router.post(
    "/analytics/log",
    summary="Log playback event",
    description="Records the duration a user watched or listened to a specific media file."
)
async def log_playback(request: PlaybackLogRequest, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    media = db.query(Media).filter(Media.id == request.media_id).first()
    if not media:
        raise HTTPException(status_code=404, detail="Media not found")
        
    event = PlaybackEvent(
        media_id=request.media_id,
        duration_watched=request.duration_watched,
        completed=request.completed,
        start_time=datetime.utcnow()
    )
    db.add(event)
    db.commit()
    
    # Check if user activity threshold triggers AI playlist curation in background
    check_activity_and_maybe_curate(db, background_tasks)
    
    return {"message": "Playback logged successfully", "event_id": event.id}

@router.post(
    "/analytics/log-by-filename",
    summary="Log playback event by filename",
)
async def log_playback_by_filename(request: PlaybackLogByFilenameRequest, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    media = db.query(Media).filter(Media.filename == request.filename).first()
    if not media:
        return {"message": "Media not found, skipping", "event_id": None}
        
    event = PlaybackEvent(
        media_id=media.id,
        duration_watched=request.duration_watched,
        completed=request.completed,
        start_time=datetime.utcnow()
    )
    db.add(event)
    db.commit()
    
    # Check if user activity threshold triggers AI playlist curation in background
    check_activity_and_maybe_curate(db, background_tasks)
    
    return {"message": "Playback logged successfully", "event_id": event.id}


@router.get(
    "/analytics/history",
    summary="Get playback history",
)
async def get_history(limit: int = 50, db: Session = Depends(get_db)):
    events = db.query(PlaybackEvent).order_by(PlaybackEvent.start_time.desc()).limit(limit).all()
    return [{
        "id": e.id,
        "media_id": e.media_id,
        "title": e.media.title if e.media else "Unknown",
        "duration_watched": e.duration_watched,
        "completed": e.completed,
        "start_time": e.start_time
    } for e in events]


@router.get(
    "/analytics/stats",
    summary="Get download and library statistics",
)
async def get_stats(db: Session = Depends(get_db)):
    """Returns real statistics from the downloaded media library."""
    # Total counts
    total_songs = db.query(func.count(Media.id)).filter(Media.type == "music").scalar() or 0
    total_videos = db.query(func.count(Media.id)).filter(Media.type == "video").scalar() or 0
    total_media = db.query(func.count(Media.id)).scalar() or 0

    # Top artists (by number of downloads)
    top_artists_query = (
        db.query(Media.artist, func.count(Media.id).label("count"))
        .filter(Media.artist.isnot(None), Media.artist != "")
        .group_by(Media.artist)
        .order_by(func.count(Media.id).desc())
        .limit(10)
        .all()
    )
    top_artists = [{"artist": a, "count": c} for a, c in top_artists_query]

    # Top genres
    top_genres_query = (
        db.query(Media.genre, func.count(Media.id).label("count"))
        .filter(Media.genre.isnot(None), Media.genre != "")
        .group_by(Media.genre)
        .order_by(func.count(Media.id).desc())
        .limit(10)
        .all()
    )
    top_genres = [{"genre": g, "count": c} for g, c in top_genres_query]

    # Recent downloads (last 20)
    recent = (
        db.query(Media)
        .order_by(Media.added_at.desc())
        .limit(20)
        .all()
    )
    recent_downloads = [{
        "id": m.id,
        "title": m.title,
        "artist": m.artist or "Desconocido",
        "type": m.type,
        "format": m.format,
        "cover_url": m.cover_url or "",
        "added_at": m.added_at.isoformat() if m.added_at else None,
    } for m in recent]

    # Downloads by format
    format_stats = (
        db.query(Media.format, func.count(Media.id).label("count"))
        .group_by(Media.format)
        .all()
    )
    formats = {f: c for f, c in format_stats}

    # Downloads this week
    week_ago = datetime.utcnow() - timedelta(days=7)
    this_week = db.query(func.count(Media.id)).filter(Media.added_at >= week_ago).scalar() or 0

    # Downloads today
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    today_count = db.query(func.count(Media.id)).filter(Media.added_at >= today_start).scalar() or 0

    return {
        "total_songs": total_songs,
        "total_videos": total_videos,
        "total_media": total_media,
        "this_week": this_week,
        "today": today_count,
        "top_artists": top_artists,
        "top_genres": top_genres,
        "recent_downloads": recent_downloads,
        "formats": formats,
    }


@router.get(
    "/analytics/stats/advanced",
    summary="Get comprehensive analytics with patterns, mood, and trends",
)
async def get_advanced_stats(db: Session = Depends(get_db)):
    """Returns advanced analytics: library, listening time, patterns, mood, trends."""
    from config import settings
    from pathlib import Path
    import os

    now = datetime.utcnow()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_ago = now - timedelta(days=7)
    month_ago = now - timedelta(days=30)

    # ═══════════════════════════════════════════
    # 📚 BIBLIOTECA
    # ═══════════════════════════════════════════
    total_songs = db.query(func.count(Media.id)).filter(Media.type == "music").scalar() or 0
    total_videos = db.query(func.count(Media.id)).filter(Media.type == "video").scalar() or 0
    total_media = db.query(func.count(Media.id)).scalar() or 0

    # Count playlists (folders)
    from models import Playlist
    total_playlists = db.query(func.count(Playlist.id)).scalar() or 0

    # Calculate total size on disk
    total_size_bytes = 0
    for folder in [settings.MUSIC_DIR, settings.VIDEO_DIR]:
        if folder.exists():
            for f in folder.rglob("*"):
                if f.is_file():
                    try:
                        total_size_bytes += f.stat().st_size
                    except OSError:
                        pass
    total_size_gb = round(total_size_bytes / (1024 ** 3), 2)

    # Downloads counts
    downloads_today = db.query(func.count(Media.id)).filter(Media.added_at >= today_start).scalar() or 0
    downloads_this_week = db.query(func.count(Media.id)).filter(Media.added_at >= week_ago).scalar() or 0
    downloads_this_month = db.query(func.count(Media.id)).filter(Media.added_at >= month_ago).scalar() or 0

    # ═══════════════════════════════════════════
    # ⏱️ TIEMPO DE ESCUCHA
    # ═══════════════════════════════════════════
    total_seconds = db.query(func.sum(PlaybackEvent.duration_watched)).scalar() or 0
    total_hours = round(total_seconds / 3600, 1)
    total_days = round(total_seconds / 86400, 1)
    total_weeks = round(total_seconds / 604800, 1)

    # Hours today
    seconds_today = db.query(func.sum(PlaybackEvent.duration_watched)).filter(
        PlaybackEvent.start_time >= today_start
    ).scalar() or 0
    hours_today = round(seconds_today / 3600, 2)
    minutes_today = round(seconds_today / 60)

    # Hours this week
    seconds_week = db.query(func.sum(PlaybackEvent.duration_watched)).filter(
        PlaybackEvent.start_time >= week_ago
    ).scalar() or 0
    hours_this_week = round(seconds_week / 3600, 1)

    # Hours this month
    seconds_month = db.query(func.sum(PlaybackEvent.duration_watched)).filter(
        PlaybackEvent.start_time >= month_ago
    ).scalar() or 0
    hours_this_month = round(seconds_month / 3600, 1)

    # Average daily hours (over last 30 days)
    avg_daily_hours = round(hours_this_month / 30, 2) if hours_this_month > 0 else 0

    # Total plays count
    total_plays = db.query(func.count(PlaybackEvent.id)).scalar() or 0
    plays_today = db.query(func.count(PlaybackEvent.id)).filter(
        PlaybackEvent.start_time >= today_start
    ).scalar() or 0
    completed_plays = db.query(func.count(PlaybackEvent.id)).filter(
        PlaybackEvent.completed == True
    ).scalar() or 0

    # ═══════════════════════════════════════════
    # 🎵 TOP CONTENIDO
    # ═══════════════════════════════════════════
    # Top 10 songs by play count
    top_songs_query = (
        db.query(
            Media.title,
            Media.artist,
            Media.cover_url,
            func.count(PlaybackEvent.id).label("plays"),
            func.sum(PlaybackEvent.duration_watched).label("total_time")
        )
        .join(PlaybackEvent, PlaybackEvent.media_id == Media.id)
        .group_by(Media.id)
        .order_by(func.count(PlaybackEvent.id).desc())
        .limit(10)
        .all()
    )
    top_songs = [{
        "title": t, "artist": a or "Desconocido", "cover_url": c or "",
        "plays": p, "total_hours": round((tt or 0) / 3600, 1)
    } for t, a, c, p, tt in top_songs_query]

    # Top 10 artists by play count
    top_artists_query = (
        db.query(
            Media.artist,
            func.count(PlaybackEvent.id).label("plays"),
            func.sum(PlaybackEvent.duration_watched).label("total_time")
        )
        .join(PlaybackEvent, PlaybackEvent.media_id == Media.id)
        .filter(Media.artist.isnot(None), Media.artist != "")
        .group_by(Media.artist)
        .order_by(func.count(PlaybackEvent.id).desc())
        .limit(10)
        .all()
    )
    top_artists = [{
        "artist": a, "plays": p, "total_hours": round((tt or 0) / 3600, 1)
    } for a, p, tt in top_artists_query]

    # Top genres
    top_genres_query = (
        db.query(Media.genre, func.count(Media.id).label("count"))
        .filter(Media.genre.isnot(None), Media.genre != "")
        .group_by(Media.genre)
        .order_by(func.count(Media.id).desc())
        .limit(10)
        .all()
    )
    top_genres = [{"genre": g, "count": c} for g, c in top_genres_query]

    # Top albums by play count
    top_albums_query = (
        db.query(
            Media.album,
            Media.artist,
            func.count(PlaybackEvent.id).label("plays"),
            func.sum(PlaybackEvent.duration_watched).label("total_time")
        )
        .join(PlaybackEvent, PlaybackEvent.media_id == Media.id)
        .filter(Media.album.isnot(None), Media.album != "")
        .group_by(Media.album)
        .order_by(func.count(PlaybackEvent.id).desc())
        .limit(10)
        .all()
    )
    top_albums = [{
        "album": al, "artist": ar or "Desconocido", "plays": p, "total_hours": round((tt or 0) / 3600, 1)
    } for al, ar, p, tt in top_albums_query]

    # Most played today
    most_played_today_query = (
        db.query(
            Media.title, Media.artist, Media.cover_url,
            func.count(PlaybackEvent.id).label("plays")
        )
        .join(PlaybackEvent, PlaybackEvent.media_id == Media.id)
        .filter(PlaybackEvent.start_time >= today_start)
        .group_by(Media.id)
        .order_by(func.count(PlaybackEvent.id).desc())
        .limit(5)
        .all()
    )
    most_played_today = [{
        "title": t, "artist": a or "Desconocido", "cover_url": c or "", "plays": p
    } for t, a, c, p in most_played_today_query]

    # ═══════════════════════════════════════════
    # 📅 PATRONES DE USO
    # ═══════════════════════════════════════════
    # Listening by hour of day (0-23)
    hour_query = (
        db.query(
            func.strftime('%H', PlaybackEvent.start_time).label("hour"),
            func.count(PlaybackEvent.id).label("count")
        )
        .group_by("hour")
        .all()
    )
    listening_by_hour = {int(h): c for h, c in hour_query}
    # Fill missing hours with 0
    listening_by_hour_full = [listening_by_hour.get(h, 0) for h in range(24)]

    # Peak hour
    peak_hour = max(range(24), key=lambda h: listening_by_hour.get(h, 0)) if listening_by_hour else 0
    peak_hour_label = f"{peak_hour}:00"

    # Listening by day of week (0=Sunday to 6=Saturday)
    day_query = (
        db.query(
            func.strftime('%w', PlaybackEvent.start_time).label("dow"),
            func.count(PlaybackEvent.id).label("count")
        )
        .group_by("dow")
        .all()
    )
    day_names = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
    listening_by_day = {int(d): c for d, c in day_query}
    listening_by_day_full = [{"day": day_names[d], "count": listening_by_day.get(d, 0)} for d in range(7)]

    # Peak day
    peak_day_idx = max(range(7), key=lambda d: listening_by_day.get(d, 0)) if listening_by_day else 0
    peak_day = day_names[peak_day_idx]

    # Daily streak (consecutive days with at least 1 play)
    streak = 0
    check_date = today_start
    while True:
        day_plays = db.query(func.count(PlaybackEvent.id)).filter(
            PlaybackEvent.start_time >= check_date,
            PlaybackEvent.start_time < check_date + timedelta(days=1)
        ).scalar() or 0
        if day_plays > 0:
            streak += 1
            check_date -= timedelta(days=1)
        else:
            break
        if streak > 365:  # safety limit
            break

    # ═══════════════════════════════════════════
    # 💭 SENTIMIENTO / MOOD
    # ═══════════════════════════════════════════
    # Analyze mood based on genres and listening patterns
    genre_mood_map = {
        # High energy
        "reggaeton": {"energy": 0.85, "valence": 0.75},
        "trap": {"energy": 0.8, "valence": 0.5},
        "edm": {"energy": 0.95, "valence": 0.8},
        "electronic": {"energy": 0.9, "valence": 0.7},
        "dance": {"energy": 0.9, "valence": 0.85},
        "pop": {"energy": 0.7, "valence": 0.8},
        "hip hop": {"energy": 0.75, "valence": 0.55},
        "rap": {"energy": 0.75, "valence": 0.5},
        "rock": {"energy": 0.8, "valence": 0.6},
        "metal": {"energy": 0.95, "valence": 0.3},
        # Medium energy
        "r&b": {"energy": 0.5, "valence": 0.65},
        "latin": {"energy": 0.7, "valence": 0.75},
        "salsa": {"energy": 0.8, "valence": 0.8},
        "bachata": {"energy": 0.55, "valence": 0.7},
        "cumbia": {"energy": 0.7, "valence": 0.8},
        # Low energy
        "ballad": {"energy": 0.3, "valence": 0.4},
        "classical": {"energy": 0.3, "valence": 0.5},
        "jazz": {"energy": 0.4, "valence": 0.6},
        "acoustic": {"energy": 0.3, "valence": 0.55},
        "lofi": {"energy": 0.25, "valence": 0.5},
        "ambient": {"energy": 0.2, "valence": 0.5},
    }

    # Get all genres in library with counts
    all_genres = (
        db.query(Media.genre, func.count(Media.id))
        .filter(Media.genre.isnot(None), Media.genre != "")
        .group_by(Media.genre)
        .all()
    )

    total_genre_count = sum(c for _, c in all_genres) if all_genres else 1
    avg_energy = 0.5
    avg_valence = 0.5

    for genre, count in all_genres:
        genre_lower = genre.lower().strip()
        for key, values in genre_mood_map.items():
            if key in genre_lower:
                weight = count / total_genre_count
                avg_energy += (values["energy"] - 0.5) * weight
                avg_valence += (values["valence"] - 0.5) * weight
                break

    avg_energy = round(max(0, min(1, avg_energy)), 2)
    avg_valence = round(max(0, min(1, avg_valence)), 2)

    # Determine mood label
    if avg_energy > 0.7 and avg_valence > 0.6:
        mood_label = "Energético 🔥"
        mood_emoji = "🔥"
    elif avg_energy > 0.6 and avg_valence > 0.5:
        mood_label = "Activo ⚡"
        mood_emoji = "⚡"
    elif avg_energy < 0.4 and avg_valence > 0.5:
        mood_label = "Relajado 😌"
        mood_emoji = "😌"
    elif avg_energy < 0.4 and avg_valence < 0.4:
        mood_label = "Melancólico 🌧️"
        mood_emoji = "🌧️"
    elif avg_valence > 0.7:
        mood_label = "Feliz 😄"
        mood_emoji = "😄"
    elif avg_valence < 0.3:
        mood_label = "Intenso 💀"
        mood_emoji = "💀"
    else:
        mood_label = "Equilibrado ✨"
        mood_emoji = "✨"

    # ═══════════════════════════════════════════
    # 📈 TENDENCIAS
    # ═══════════════════════════════════════════
    # Listening trend last 7 days (hours per day)
    listening_trend_7d = []
    for i in range(6, -1, -1):
        day_start = (now - timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
        day_end = day_start + timedelta(days=1)
        day_seconds = db.query(func.sum(PlaybackEvent.duration_watched)).filter(
            PlaybackEvent.start_time >= day_start,
            PlaybackEvent.start_time < day_end
        ).scalar() or 0
        day_plays = db.query(func.count(PlaybackEvent.id)).filter(
            PlaybackEvent.start_time >= day_start,
            PlaybackEvent.start_time < day_end
        ).scalar() or 0
        listening_trend_7d.append({
            "date": day_start.strftime("%Y-%m-%d"),
            "day_name": day_names[(day_start.weekday() + 1) % 7],  # Convert to our index
            "hours": round(day_seconds / 3600, 2),
            "plays": day_plays,
        })

    # Downloads trend last 30 days
    downloads_trend_30d = []
    for i in range(29, -1, -1):
        day_start = (now - timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
        day_end = day_start + timedelta(days=1)
        count = db.query(func.count(Media.id)).filter(
            Media.added_at >= day_start,
            Media.added_at < day_end
        ).scalar() or 0
        downloads_trend_30d.append({
            "date": day_start.strftime("%Y-%m-%d"),
            "count": count,
        })

    # New artists this month
    month_start = (now - timedelta(days=30)).replace(hour=0, minute=0, second=0, microsecond=0)
    new_artists = (
        db.query(Media.artist)
        .filter(
            Media.added_at >= month_start,
            Media.artist.isnot(None),
            Media.artist != ""
        )
        .distinct()
        .count()
    )

    # Recent downloads (last 10)
    recent = (
        db.query(Media)
        .order_by(Media.added_at.desc())
        .limit(10)
        .all()
    )
    recent_downloads = [{
        "id": m.id, "title": m.title, "artist": m.artist or "Desconocido",
        "type": m.type, "cover_url": m.cover_url or "",
        "added_at": m.added_at.isoformat() if m.added_at else None,
    } for m in recent]

    # Formats distribution
    format_stats = (
        db.query(Media.format, func.count(Media.id).label("count"))
        .group_by(Media.format)
        .all()
    )
    formats = {f: c for f, c in format_stats}

    return {
        # 📚 Biblioteca
        "library": {
            "total_songs": total_songs,
            "total_videos": total_videos,
            "total_media": total_media,
            "total_playlists": total_playlists,
            "total_size_gb": total_size_gb,
            "downloads_today": downloads_today,
            "downloads_this_week": downloads_this_week,
            "downloads_this_month": downloads_this_month,
            "formats": formats,
            "recent_downloads": recent_downloads,
        },
        # ⏱️ Tiempo de escucha
        "listening": {
            "total_hours": total_hours,
            "total_days": total_days,
            "total_weeks": total_weeks,
            "hours_today": hours_today,
            "minutes_today": minutes_today,
            "hours_this_week": hours_this_week,
            "hours_this_month": hours_this_month,
            "avg_daily_hours": avg_daily_hours,
            "total_plays": total_plays,
            "plays_today": plays_today,
            "completed_plays": completed_plays,
            "completion_rate": round(completed_plays / total_plays * 100, 1) if total_plays > 0 else 0,
        },
        # 🎵 Top contenido
        "top_content": {
            "top_songs": top_songs,
            "top_artists": top_artists,
            "top_genres": top_genres,
            "top_albums": top_albums,
            "most_played_today": most_played_today,
        },
        # 📅 Patrones
        "patterns": {
            "listening_by_hour": listening_by_hour_full,
            "listening_by_day": listening_by_day_full,
            "peak_hour": peak_hour_label,
            "peak_day": peak_day,
            "daily_streak": streak,
        },
        # 💭 Mood
        "mood": {
            "avg_energy": avg_energy,
            "avg_valence": avg_valence,
            "mood_label": mood_label,
            "mood_emoji": mood_emoji,
        },
        # 📈 Tendencias
        "trends": {
            "listening_trend_7d": listening_trend_7d,
            "downloads_trend_30d": downloads_trend_30d,
            "new_artists_this_month": new_artists,
        },
    }


@router.post(
    "/analytics/sync",
    summary="Sync downloads folder with DB and clean up junk files",
)
async def sync_downloads(db: Session = Depends(get_db)):
    """
    Scans the downloads folder for real audio/video files,
    registers any missing ones in the DB, and cleans up
    leftover thumbnails and failed downloads.
    """
    from config import settings
    from pathlib import Path
    import os

    music_dir = settings.MUSIC_DIR
    video_dir = settings.VIDEO_DIR

    audio_exts = {".mp3", ".m4a", ".opus", ".ogg", ".wav", ".aac", ".flac", ".wma", ".webm"}
    video_exts = {".mp4", ".mkv", ".webm", ".avi", ".mov"}
    junk_exts = {".webp", ".jpg", ".jpeg", ".png", ".part", ".ytdl", ".temp"}

    added = 0
    cleaned = 0
    errors = []

    for folder, media_type, valid_exts in [
        (music_dir, "music", audio_exts),
        (video_dir, "video", video_exts),
    ]:
        if not folder.exists():
            continue

        for f in folder.iterdir():
            if f.is_dir():
                continue

            ext = f.suffix.lower()

            # Clean up junk files
            if ext in junk_exts:
                try:
                    f.unlink()
                    cleaned += 1
                except Exception as e:
                    errors.append(f"Could not delete {f.name}: {e}")
                continue

            # Skip non-media files
            if ext not in valid_exts:
                # Check if it's a file with no extension but too small (failed download)
                if ext == "" and f.stat().st_size < 10000:
                    try:
                        f.unlink()
                        cleaned += 1
                    except Exception:
                        pass
                continue

            # Skip tiny files (< 10KB = probably failed)
            if f.stat().st_size < 10000:
                try:
                    f.unlink()
                    cleaned += 1
                except Exception:
                    pass
                continue

            # Check if already in DB
            existing = db.query(Media).filter(Media.filename == f.name).first()
            if existing:
                continue

            # Parse artist - title from filename
            stem = f.stem.lstrip("- ").strip()
            if " - " in stem:
                parts = stem.split(" - ", 1)
                artist = parts[0].strip()
                title = parts[1].strip()
            else:
                artist = ""
                title = stem

            media = Media(
                type=media_type,
                title=title,
                artist=artist,
                album="",
                genre="",
                year="",
                filename=f.name,
                format=ext.lstrip("."),
                cover_url="",
                shazam_url="",
                added_at=datetime.fromtimestamp(os.path.getmtime(f)),
            )
            db.add(media)
            added += 1

    db.commit()

    return {
        "added": added,
        "cleaned": cleaned,
        "errors": errors,
        "message": f"Sincronización completa: {added} archivos añadidos, {cleaned} archivos basura eliminados.",
    }
