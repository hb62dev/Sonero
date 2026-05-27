from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from pydantic import BaseModel
from database import get_db
from models import FocusSession, ListeningHistory, Track, User, SystemSetting
import services.smart_music_service as sms
import services.gemini_service as gs
from typing import List, Optional

router = APIRouter()

# ── Schemas ───────────────────────────────────────────────────────────────────

class GeminiKeyRequest(BaseModel):
    api_key: str

class StartSessionRequest(BaseModel):
    user_id: str

class EndSessionRequest(BaseModel):
    session_id: int

class IsoPrincipleRequest(BaseModel):
    user_id: str

class PlaylistQueueRequest(BaseModel):
    user_id: str
    ideal_bpm: float
    queue_size: Optional[int] = 10
    burnout_threshold: Optional[float] = 5.0

class ParseContextRequest(BaseModel):
    prompt: str
    user_id: Optional[str] = "1"

class WeeklyReportRequest(BaseModel):
    user_id: str

class LogListeningHistoryRequest(BaseModel):
    user_id: str
    track_id: int
    duration_played: float
    completed: bool
    skipped: bool
    skip_time: Optional[float] = 0.0

class CreateTrackRequest(BaseModel):
    title: str
    artist: str
    bpm: float
    valence: float
    energy: float
    instrumentalness: float
    genre: Optional[str] = None

class CreateUserRequest(BaseModel):
    name: str
    preferences: Optional[str] = None

# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post(
    "/settings/gemini-key",
    summary="Save Gemini API Key to database",
    description="Saves or updates the Gemini API key in the database settings table. Key is kept secure and not stored in files."
)
def save_gemini_key(body: GeminiKeyRequest, db: Session = Depends(get_db)):
    setting = db.query(SystemSetting).filter(SystemSetting.key == "gemini_api_key").first()
    if setting:
        setting.value = body.api_key
    else:
        setting = SystemSetting(key="gemini_api_key", value=body.api_key)
        db.add(setting)
    
    db.commit()
    return {"message": "Clave API de Gemini guardada correctamente en la Base de Datos."}


@router.post(
    "/smart/tracks",
    summary="Create a new Track with audio features",
)
def create_track(body: CreateTrackRequest, db: Session = Depends(get_db)):
    track = Track(
        title=body.title,
        artist=body.artist,
        bpm=body.bpm,
        valence=body.valence,
        energy=body.energy,
        instrumentalness=body.instrumentalness,
        genre=body.genre
    )
    db.add(track)
    db.commit()
    db.refresh(track)
    return track


@router.post(
    "/smart/users",
    summary="Create a new User",
)
def create_user(body: CreateUserRequest, db: Session = Depends(get_db)):
    user = User(
        name=body.name,
        preferences=body.preferences
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.post(
    "/smart/listening-history/log",
    summary="Log listening history event",
)
def log_listening_history(body: LogListeningHistoryRequest, db: Session = Depends(get_db)):
    track = db.query(Track).filter(Track.id == body.track_id).first()
    user = db.query(User).filter(User.id == body.user_id).first()
    if not track:
        raise HTTPException(status_code=404, detail="Track not found")
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
        
    lh = ListeningHistory(
        user_id=body.user_id,
        track_id=body.track_id,
        duration_played=body.duration_played,
        completed=body.completed,
        skipped=body.skipped,
        skip_time=body.skip_time,
        listened_at=datetime.utcnow()
    )
    db.add(lh)
    db.flush()

    # ── Automated Intelligent Focus Session Detection ──
    active_session = db.query(FocusSession).filter(
        FocusSession.user_id == body.user_id,
        FocusSession.ended_at.is_(None)
    ).order_by(FocusSession.started_at.desc()).first()

    now = datetime.utcnow()

    if active_session:
        # Check gap since last logged listening history (excluding the current one we just added)
        last_history = db.query(ListeningHistory).filter(
            ListeningHistory.user_id == body.user_id,
            ListeningHistory.id != lh.id
        ).order_by(ListeningHistory.listened_at.desc()).first()
        
        if last_history:
            gap_seconds = (now - last_history.listened_at).total_seconds()
            if gap_seconds > 1200:  # 20 minutes of silence/inactivity
                # Close the active session
                active_session.ended_at = last_history.listened_at + timedelta(seconds=last_history.duration_played)
                db.flush()
                # Compute Focus Score
                active_session.focus_score = sms.calculate_focus_score(db, active_session.id)
                # Count skips
                skips_count = db.query(ListeningHistory).filter(
                    ListeningHistory.user_id == active_session.user_id,
                    ListeningHistory.listened_at >= active_session.started_at,
                    ListeningHistory.listened_at <= active_session.ended_at,
                    ListeningHistory.skipped == True
                ).count()
                active_session.total_skips = skips_count
                
                # Start new focus session
                new_session = FocusSession(
                    user_id=body.user_id,
                    started_at=now,
                    total_skips=0,
                    focus_score=0.0
                )
                db.add(new_session)
    else:
        # Start new focus session
        new_session = FocusSession(
            user_id=body.user_id,
            started_at=now,
            total_skips=0,
            focus_score=0.0
        )
        db.add(new_session)

    db.commit()
    db.refresh(lh)
    return {"message": "Escucha registrada exitosamente y sesión de enfoque actualizada", "id": lh.id}


@router.post(
    "/smart/focus/session/start",
    summary="Start a Focus Session",
)
def start_focus_session(body: StartSessionRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == body.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    session = FocusSession(
        user_id=body.user_id,
        started_at=datetime.utcnow(),
        total_skips=0,
        focus_score=0.0
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return {
        "message": "Sesión de enfoque iniciada.",
        "session_id": session.id,
        "started_at": session.started_at
    }


@router.post(
    "/smart/focus/session/end",
    summary="End a Focus Session",
    description="Calculates the Focus Score (EF) for the ended session and commits it to the database."
)
def end_focus_session(body: EndSessionRequest, db: Session = Depends(get_db)):
    session = db.query(FocusSession).filter(FocusSession.id == body.session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Focus session not found")
    
    if session.ended_at:
         raise HTTPException(status_code=400, detail="Session already ended")

    session.ended_at = datetime.utcnow()
    db.flush()

    # Calculate skips from history during the session
    history = db.query(ListeningHistory).filter(
        ListeningHistory.user_id == session.user_id,
        ListeningHistory.listened_at >= session.started_at,
        ListeningHistory.listened_at <= session.ended_at
    ).all()
    session.total_skips = sum(1 for lh in history if lh.skipped)

    # Calculate Focus Score using productivity logic
    focus_score = sms.calculate_focus_score(db, session.id)
    session.focus_score = focus_score
    db.commit()
    db.refresh(session)

    return {
        "message": "Sesión de enfoque finalizada.",
        "session_id": session.id,
        "started_at": session.started_at,
        "ended_at": session.ended_at,
        "total_skips": session.total_skips,
        "focus_score": session.focus_score
    }


@router.get(
    "/smart/focus/session/active",
    summary="Get active Focus Session",
)
def get_active_focus_session(user_id: str, db: Session = Depends(get_db)):
    session = db.query(FocusSession).filter(
        FocusSession.user_id == user_id,
        FocusSession.ended_at.is_(None)
    ).order_by(FocusSession.started_at.desc()).first()
    
    if not session:
        return {"active": False, "session": None}
        
    return {
        "active": True,
        "session": {
            "id": session.id,
            "user_id": session.user_id,
            "started_at": session.started_at
        }
    }


@router.get(
    "/smart/focus/bpm-optimum",
    summary="Get optimal BPM and prioritized tracks",
    description="Analyzes focus sessions and retrieves optimal BPM range. Prioritizes instrumental tracks (>0.7 instrumentalness) in that range."
)
def get_optimal_bpm(user_id: str, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    bpm_analysis = sms.get_optimal_bpm_range(db, user_id)
    opt_range = bpm_analysis["optimal_range"]

    # Query prioritized focus tracks (instrumentalness > 0.7) in the optimal BPM range
    prioritized_tracks = db.query(Track).filter(
        Track.bpm >= opt_range[0],
        Track.bpm <= opt_range[1],
        Track.instrumentalness > 0.7
    ).all()

    tracks_data = [{
        "id": t.id,
        "title": t.title,
        "artist": t.artist,
        "bpm": t.bpm,
        "valence": t.valence,
        "energy": t.energy,
        "instrumentalness": t.instrumentalness,
        "genre": t.genre
    } for t in prioritized_tracks]

    return {
        "bpm_analysis": bpm_analysis,
        "prioritized_tracks_count": len(tracks_data),
        "prioritized_tracks": tracks_data
    }


@router.get(
    "/smart/mood/current",
    summary="Get current user mood",
    description="Computes Valence & Energy based on the last 45 minutes of listening history (Russell Model)."
)
def get_current_mood(user_id: str, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    mood_data = sms.get_current_mood_ea(db, user_id)
    return mood_data


@router.post(
    "/smart/mood/iso-principle",
    summary="Generate emotional equalization queue",
    description="Generates a 5-song playlist starting from user's current mood towards Calm state (Iso-Principle)."
)
def get_iso_principle_queue(body: IsoPrincipleRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == body.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    queue = sms.get_iso_principle_queue(db, body.user_id)
    return {
        "user_id": body.user_id,
        "description": "Iso-Principle Emotional Equalization Queue (Stressed to Calm transition)",
        "queue_size": len(queue),
        "queue": queue
    }


@router.post(
    "/smart/playlist/queue",
    summary="Generate dynamic play queue",
    description="Generates a queue of tracks utilizing Explore (15%) vs Exploit (85%) algorithm, filtering for burnout."
)
def generate_playlist_queue(body: PlaylistQueueRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == body.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    queue = sms.generate_dynamic_queue(
        db, 
        user_id=body.user_id, 
        ideal_bpm=body.ideal_bpm, 
        queue_size=body.queue_size, 
        burnout_threshold=body.burnout_threshold
    )

    return {
        "user_id": body.user_id,
        "ideal_bpm": body.ideal_bpm,
        "queue_size": len(queue),
        "queue": queue
    }


@router.post(
    "/smart/gemini/parse-context",
    summary="Parse natural language context prompt",
    description="Queries Gemini (or offline fallback) to extract BPM, energy, valence, and instrumental preference."
)
async def parse_prompt_context(body: ParseContextRequest, db: Session = Depends(get_db)):
    parsed_context = await gs.parse_natural_language_context(body.prompt, db)
    return parsed_context


@router.post(
    "/smart/gemini/weekly-report",
    summary="Generate weekly productivity report",
    description="Aggregates metrics for the user over the last 7 days and invokes Gemini (or offline fallback) to generate a Markdown report."
)
async def get_weekly_productivity_report(body: WeeklyReportRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == body.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # 1. Aggregate statistics for the last 7 days
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    
    # Focus sessions statistics
    sessions = db.query(FocusSession).filter(
        FocusSession.user_id == body.user_id,
        FocusSession.started_at >= seven_days_ago,
        FocusSession.ended_at.isnot(None)
    ).all()

    total_sessions = len(sessions)
    avg_focus_score = sum(s.focus_score for s in sessions) / total_sessions if total_sessions > 0 else 0.0
    total_skips = sum(s.total_skips for s in sessions)

    # Listening history statistics
    history = db.query(ListeningHistory).filter(
        ListeningHistory.user_id == body.user_id,
        ListeningHistory.listened_at >= seven_days_ago
    ).all()

    total_listened = len(history)
    skipped_listened = sum(1 for lh in history if lh.skipped)
    skip_rate = skipped_listened / total_listened if total_listened > 0 else 0.0

    # Determine dominant mood
    mood_analysis = sms.get_current_mood_ea(db, body.user_id)
    dominant_mood = mood_analysis["quadrant"]

    # Optimal BPM
    bpm_analysis = sms.get_optimal_bpm_range(db, body.user_id)
    optimal_bpm_range = bpm_analysis["optimal_range"]

    # New deep analysis metrics
    top_focus_tracks = sms.get_top_focus_tracks(db, body.user_id, limit=3)
    top_distractor_tracks = sms.get_top_distractor_tracks(db, body.user_id, limit=3)
    temporal_profile = sms.get_temporal_focus_profile(db, body.user_id)
    genre_focus_correlation = sms.get_genre_focus_correlation(db, body.user_id)

    # Assemble summary payload
    summary = {
        "avg_focus_score": round(avg_focus_score, 4),
        "total_sessions": total_sessions,
        "total_skips": total_skips,
        "skip_rate": round(skip_rate, 4),
        "dominant_mood": dominant_mood,
        "optimal_bpm_range": optimal_bpm_range,
        "top_focus_tracks": top_focus_tracks,
        "top_distractor_tracks": top_distractor_tracks,
        "temporal_profile": temporal_profile,
        "genre_focus_correlation": genre_focus_correlation
    }

    # Generate Markdown report (Gemini or Offline Fallback)
    report_markdown = await gs.generate_weekly_productivity_report(summary, db)

    return {
        "user_id": body.user_id,
        "summary": summary,
        "report": report_markdown
    }
