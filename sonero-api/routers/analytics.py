from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime
from pydantic import BaseModel

from database import get_db
from models import PlaybackEvent, Media

router = APIRouter()

class PlaybackLogRequest(BaseModel):
    media_id: int
    duration_watched: float
    completed: bool

@router.post(
    "/analytics/log",
    summary="Log playback event",
    description="Records the duration a user watched or listened to a specific media file."
)
async def log_playback(request: PlaybackLogRequest, db: Session = Depends(get_db)):
    media = db.query(Media).filter(Media.id == request.media_id).first()
    if not media:
        raise HTTPException(status_code=404, detail="Media not found")
        
    event = PlaybackEvent(
        media_id=request.media_id,
        duration_watched=request.duration_watched,
        completed=request.completed,
        start_time=datetime.utcnow() # we can assume the event is sent periodically or at the end
    )
    db.add(event)
    db.commit()
    
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
