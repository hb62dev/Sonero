from sqlalchemy import Column, Integer, String, Boolean, DateTime, Float, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime
import json
from database import Base

class Media(Base):
    __tablename__ = "media"
    
    id = Column(Integer, primary_key=True, index=True)
    type = Column(String, index=True) # "music" or "video"
    title = Column(String, index=True)
    artist = Column(String, index=True, nullable=True) # Also used for channel name
    album = Column(String, nullable=True)
    genre = Column(String, nullable=True)
    year = Column(String, nullable=True)
    filename = Column(String, unique=True, index=True)
    format = Column(String) # "mp3", "mp4", etc.
    cover_url = Column(String, nullable=True)
    shazam_url = Column(String, nullable=True)
    added_at = Column(DateTime, default=datetime.utcnow)
    _tags = Column("tags", Text, nullable=True) # Stored as JSON string
    
    @property
    def tags(self):
        if self._tags:
            return json.loads(self._tags)
        return []
        
    @tags.setter
    def tags(self, value):
        if value is not None:
            self._tags = json.dumps(value)
        else:
            self._tags = None
            
    # Relationships
    playlist_entries = relationship("PlaylistMedia", back_populates="media", cascade="all, delete-orphan")
    playback_events = relationship("PlaybackEvent", back_populates="media", cascade="all, delete-orphan")


class Playlist(Base):
    __tablename__ = "playlists"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    is_smart = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    items = relationship("PlaylistMedia", back_populates="playlist", cascade="all, delete-orphan")


class PlaylistMedia(Base):
    __tablename__ = "playlist_media"
    
    id = Column(Integer, primary_key=True, index=True)
    playlist_id = Column(Integer, ForeignKey("playlists.id"))
    media_id = Column(Integer, ForeignKey("media.id"))
    added_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    playlist = relationship("Playlist", back_populates="items")
    media = relationship("Media", back_populates="playlist_entries")


class PlaybackEvent(Base):
    __tablename__ = "playback_events"
    
    id = Column(Integer, primary_key=True, index=True)
    media_id = Column(Integer, ForeignKey("media.id"))
    start_time = Column(DateTime, default=datetime.utcnow)
    duration_watched = Column(Float, default=0.0) # in seconds
    completed = Column(Boolean, default=False)
    
    # Relationships
    media = relationship("Media", back_populates="playback_events")


class Track(Base):
    __tablename__ = "tracks"
    
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    artist = Column(String, index=True)
    bpm = Column(Float, nullable=False)
    valence = Column(Float, nullable=False)  # float, 0-1
    energy = Column(Float, nullable=False)   # float, 0-1
    instrumentalness = Column(Float, nullable=False)  # float, 0-1
    genre = Column(String, nullable=True)

    # Relationships
    listening_histories = relationship("ListeningHistory", back_populates="track", cascade="all, delete-orphan")


class User(Base):
    __tablename__ = "users"
    
    id = Column(String, primary_key=True, index=True)
    name = Column(String, index=True)
    email = Column(String, unique=True, index=True, nullable=True)
    password_hash = Column(String, nullable=True)
    preferences = Column(Text, nullable=True)  # JSON string

    # Relationships
    listening_histories = relationship("ListeningHistory", back_populates="user", cascade="all, delete-orphan")
    focus_sessions = relationship("FocusSession", back_populates="user", cascade="all, delete-orphan")


class ListeningHistory(Base):
    __tablename__ = "listening_history"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    track_id = Column(Integer, ForeignKey("tracks.id"), nullable=False)
    listened_at = Column(DateTime, default=datetime.utcnow, index=True)
    duration_played = Column(Float, default=0.0)  # in seconds
    completed = Column(Boolean, default=True)
    skipped = Column(Boolean, default=False)
    skip_time = Column(Float, nullable=True)  # in seconds, if skipped

    # Relationships
    user = relationship("User", back_populates="listening_histories")
    track = relationship("Track", back_populates="listening_histories")


class FocusSession(Base):
    __tablename__ = "focus_sessions"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    started_at = Column(DateTime, default=datetime.utcnow)
    ended_at = Column(DateTime, nullable=True)
    total_skips = Column(Integer, default=0)
    focus_score = Column(Float, nullable=True)

    # Relationships
    user = relationship("User", back_populates="focus_sessions")


class SystemSetting(Base):
    __tablename__ = "system_settings"
    
    key = Column(String, primary_key=True, index=True)
    value = Column(String, nullable=True)
