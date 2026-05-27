from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime
from pydantic import BaseModel
from database import get_db
from models import User, Track, ListeningHistory, FocusSession, Media, Playlist, PlaylistMedia, PlaybackEvent
from typing import List, Optional, Dict, Any

router = APIRouter()

# ── Date Helpers ─────────────────────────────────────────────────────────────

def to_iso(dt) -> Optional[str]:
    return dt.isoformat() if dt else None

def from_iso(s) -> Optional[datetime]:
    if not s:
        return None
    # Handle 'Z' suffix by converting to +00:00
    if s.endswith('Z'):
        s = s[:-1] + '+00:00'
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        # Fallback for other formats
        try:
            return datetime.strptime(s, "%Y-%m-%dT%H:%M:%S.%f")
        except ValueError:
            return datetime.strptime(s, "%Y-%m-%dT%H:%M:%S")

# ── Request / Response Models ────────────────────────────────────────────────

class SyncDataPayload(BaseModel):
    version: int
    users: List[Dict[str, Any]]
    tracks: List[Dict[str, Any]]
    listening_history: List[Dict[str, Any]]
    focus_sessions: List[Dict[str, Any]]
    media: List[Dict[str, Any]]
    playlists: List[Dict[str, Any]]
    playlist_media: List[Dict[str, Any]]
    playback_events: List[Dict[str, Any]]

# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get(
    "/sync/export",
    summary="Export local database state for sync",
)
async def export_sync_data(user_id: str, db: Session = Depends(get_db)) -> dict:
    """
    Exports database records as JSON. If user_id is provided, filters user-specific data.
    """
    # 1. Users (Only export the current user to protect privacy)
    users = db.query(User).filter(User.id == user_id).all()
    users_data = []
    for u in users:
        users_data.append({
            "id": u.id,
            "name": u.name,
            "email": u.email,
            "password_hash": u.password_hash,
            "preferences": u.preferences,
        })

    # 2. Tracks (Export all tracks)
    tracks = db.query(Track).all()
    tracks_data = []
    for t in tracks:
        tracks_data.append({
            "id": t.id,
            "title": t.title,
            "artist": t.artist,
            "bpm": t.bpm,
            "valence": t.valence,
            "energy": t.energy,
            "instrumentalness": t.instrumentalness,
            "genre": t.genre,
        })

    # 3. Listening History (Filter by user_id)
    history = db.query(ListeningHistory).filter(ListeningHistory.user_id == user_id).all()
    history_data = []
    for h in history:
        history_data.append({
            "id": h.id,
            "user_id": h.user_id,
            "track_id": h.track_id,
            "listened_at": to_iso(h.listened_at),
            "duration_played": h.duration_played,
            "completed": h.completed,
            "skipped": h.skipped,
            "skip_time": h.skip_time,
        })

    # 4. Focus Sessions (Filter by user_id)
    sessions = db.query(FocusSession).filter(FocusSession.user_id == user_id).all()
    sessions_data = []
    for s in sessions:
        sessions_data.append({
            "id": s.id,
            "user_id": s.user_id,
            "started_at": to_iso(s.started_at),
            "ended_at": to_iso(s.ended_at),
            "total_skips": s.total_skips,
            "focus_score": s.focus_score,
        })

    # 5. Media (All media tracks/videos downloaded)
    media = db.query(Media).all()
    media_data = []
    for m in media:
        media_data.append({
            "id": m.id,
            "type": m.type,
            "title": m.title,
            "artist": m.artist,
            "album": m.album,
            "genre": m.genre,
            "year": m.year,
            "filename": m.filename,
            "format": m.format,
            "cover_url": m.cover_url,
            "shazam_url": m.shazam_url,
            "added_at": to_iso(m.added_at),
            "tags": m.tags,
        })

    # 6. Playlists (All playlists)
    playlists = db.query(Playlist).all()
    playlists_data = []
    for p in playlists:
        playlists_data.append({
            "id": p.id,
            "name": p.name,
            "is_smart": p.is_smart,
            "created_at": to_iso(p.created_at),
        })

    # 7. Playlist Media (All relations)
    pm_entries = db.query(PlaylistMedia).all()
    pm_data = []
    for pm in pm_entries:
        pm_data.append({
            "id": pm.id,
            "playlist_id": pm.playlist_id,
            "media_id": pm.media_id,
            "added_at": to_iso(pm.added_at),
        })

    # 8. Playback Events (All watch logs)
    events = db.query(PlaybackEvent).all()
    events_data = []
    for e in events:
        events_data.append({
            "id": e.id,
            "media_id": e.media_id,
            "start_time": to_iso(e.start_time),
            "duration_watched": e.duration_watched,
            "completed": e.completed,
        })

    return {
        "version": 1,
        "users": users_data,
        "tracks": tracks_data,
        "listening_history": history_data,
        "focus_sessions": sessions_data,
        "media": media_data,
        "playlists": playlists_data,
        "playlist_media": pm_data,
        "playback_events": events_data,
    }


@router.post(
    "/sync/import",
    summary="Import and merge sync data",
)
async def import_sync_data(payload: SyncDataPayload, db: Session = Depends(get_db)) -> dict:
    """
    Accepts sync payload and merges it into the local SQLite database.
    """
    track_id_map = {}
    media_id_map = {}
    playlist_id_map = {}

    try:
        # 1. Merge Users
        for u in payload.users:
            local_user = db.query(User).filter(User.id == u["id"]).first()
            if local_user:
                local_user.name = u["name"]
                if u.get("email"):
                    local_user.email = u["email"]
                if u.get("password_hash"):
                    local_user.password_hash = u["password_hash"]
                if u.get("preferences"):
                    local_user.preferences = u["preferences"]
            else:
                new_user = User(
                    id=u["id"],
                    name=u["name"],
                    email=u.get("email"),
                    password_hash=u.get("password_hash"),
                    preferences=u.get("preferences"),
                )
                db.add(new_user)
        db.flush()

        # 2. Merge Tracks & build track_id_map
        for t in payload.tracks:
            # Try to match by exact title and artist
            local_track = db.query(Track).filter(Track.title == t["title"], Track.artist == t["artist"]).first()
            if local_track:
                # Update attributes if they are local defaults
                local_track.bpm = t["bpm"]
                local_track.valence = t["valence"]
                local_track.energy = t["energy"]
                local_track.instrumentalness = t["instrumentalness"]
                if t.get("genre"):
                    local_track.genre = t["genre"]
                track_id_map[t["id"]] = local_track.id
            else:
                new_track = Track(
                    title=t["title"],
                    artist=t["artist"],
                    bpm=t["bpm"],
                    valence=t["valence"],
                    energy=t["energy"],
                    instrumentalness=t["instrumentalness"],
                    genre=t.get("genre"),
                )
                db.add(new_track)
                db.flush()
                track_id_map[t["id"]] = new_track.id

        # 3. Merge Media & build media_id_map
        for m in payload.media:
            local_media = db.query(Media).filter(Media.filename == m["filename"]).first()
            if local_media:
                media_id_map[m["id"]] = local_media.id
            else:
                new_media = Media(
                    type=m["type"],
                    title=m["title"],
                    artist=m.get("artist"),
                    album=m.get("album"),
                    genre=m.get("genre"),
                    year=m.get("year"),
                    filename=m["filename"],
                    format=m["format"],
                    cover_url=m.get("cover_url"),
                    shazam_url=m.get("shazam_url"),
                    added_at=from_iso(m["added_at"]) or datetime.utcnow(),
                    tags=m.get("tags"),
                )
                db.add(new_media)
                db.flush()
                media_id_map[m["id"]] = new_media.id

        # 4. Merge Playlists & build playlist_id_map
        for p in payload.playlists:
            local_playlist = db.query(Playlist).filter(Playlist.name == p["name"]).first()
            if local_playlist:
                playlist_id_map[p["id"]] = local_playlist.id
            else:
                new_playlist = Playlist(
                    name=p["name"],
                    is_smart=p["is_smart"],
                    created_at=from_iso(p["created_at"]) or datetime.utcnow(),
                )
                db.add(new_playlist)
                db.flush()
                playlist_id_map[p["id"]] = new_playlist.id

        # 5. Merge Listening History
        for h in payload.listening_history:
            local_track_id = track_id_map.get(h["track_id"])
            if not local_track_id:
                continue  # Skip if track didn't map correctly
                
            listened_at_dt = from_iso(h["listened_at"])
            # Match by user, track, and timestamp
            exists = db.query(ListeningHistory).filter(
                ListeningHistory.user_id == h["user_id"],
                ListeningHistory.track_id == local_track_id,
                ListeningHistory.listened_at == listened_at_dt
            ).first()
            
            if not exists:
                new_hist = ListeningHistory(
                    user_id=h["user_id"],
                    track_id=local_track_id,
                    listened_at=listened_at_dt or datetime.utcnow(),
                    duration_played=h.get("duration_played", 0.0),
                    completed=h.get("completed", True),
                    skipped=h.get("skipped", False),
                    skip_time=h.get("skip_time"),
                )
                db.add(new_hist)

        # 6. Merge Focus Sessions
        for s in payload.focus_sessions:
            started_at_dt = from_iso(s["started_at"])
            exists = db.query(FocusSession).filter(
                FocusSession.user_id == s["user_id"],
                FocusSession.started_at == started_at_dt
            ).first()
            
            if not exists:
                new_sess = FocusSession(
                    user_id=s["user_id"],
                    started_at=started_at_dt or datetime.utcnow(),
                    ended_at=from_iso(s.get("ended_at")),
                    total_skips=s.get("total_skips", 0),
                    focus_score=s.get("focus_score"),
                )
                db.add(new_sess)

        # 7. Merge Playlist Media
        for pm in payload.playlist_media:
            local_playlist_id = playlist_id_map.get(pm["playlist_id"])
            local_media_id = media_id_map.get(pm["media_id"])
            if not local_playlist_id or not local_media_id:
                continue
                
            exists = db.query(PlaylistMedia).filter(
                PlaylistMedia.playlist_id == local_playlist_id,
                PlaylistMedia.media_id == local_media_id
            ).first()
            
            if not exists:
                new_pm = PlaylistMedia(
                    playlist_id=local_playlist_id,
                    media_id=local_media_id,
                    added_at=from_iso(pm["added_at"]) or datetime.utcnow(),
                )
                db.add(new_pm)

        # 8. Merge Playback Events
        for e in payload.playback_events:
            local_media_id = media_id_map.get(e["media_id"])
            if not local_media_id:
                continue
                
            start_time_dt = from_iso(e["start_time"])
            exists = db.query(PlaybackEvent).filter(
                PlaybackEvent.media_id == local_media_id,
                PlaybackEvent.start_time == start_time_dt
            ).first()
            
            if not exists:
                new_evt = PlaybackEvent(
                    media_id=local_media_id,
                    start_time=start_time_dt or datetime.utcnow(),
                    duration_watched=e.get("duration_watched", 0.0),
                    completed=e.get("completed", False),
                )
                db.add(new_evt)

        db.commit()
    except Exception as ex:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error al integrar los datos de sincronización: {str(ex)}")

    return {"status": "success", "message": "Datos de sincronización integrados correctamente."}
