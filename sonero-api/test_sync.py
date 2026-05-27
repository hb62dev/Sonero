import os
import unittest
from datetime import datetime, timedelta
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool

# Force in-memory DB for tests
os.environ["DATABASE_URL"] = "sqlite:///:memory:"

from database import Base, get_db
from models import Track, User, ListeningHistory, FocusSession, Media, Playlist, PlaylistMedia, PlaybackEvent
from main import app

# Create in-memory engine and session
engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

class TestSync(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=engine)
        cls.db = TestingSessionLocal()
        cls.client = TestClient(app)

        # Seed initial data
        cls.user = User(id="user_123", name="Original User", email="user@test.com", preferences='{"theme": "dark"}')
        cls.db.add(cls.user)
        cls.db.commit()

    def setUp(self):
        # Clean specific test tables between runs
        self.db.query(ListeningHistory).delete()
        self.db.query(FocusSession).delete()
        self.db.query(PlaylistMedia).delete()
        self.db.query(Playlist).delete()
        self.db.query(PlaybackEvent).delete()
        self.db.query(Media).delete()
        self.db.query(Track).delete()
        self.db.commit()

    def test_export_sync_data(self):
        # 1. Create a track
        track = Track(title="Song A", artist="Artist A", bpm=120.0, valence=0.5, energy=0.6, instrumentalness=0.1, genre="Pop")
        self.db.add(track)
        self.db.flush()

        # 2. Add history
        hist = ListeningHistory(user_id="user_123", track_id=track.id, listened_at=datetime(2026, 5, 27, 12, 0, 0), duration_played=180.0, completed=True)
        self.db.add(hist)

        # 3. Add focus session
        sess = FocusSession(user_id="user_123", started_at=datetime(2026, 5, 27, 11, 0, 0), ended_at=datetime(2026, 5, 27, 11, 30, 0), total_skips=1, focus_score=85.0)
        self.db.add(sess)

        # 4. Add Media
        media = Media(type="music", title="Song A", artist="Artist A", filename="song_a.mp3", format="mp3", added_at=datetime(2026, 5, 26, 10, 0, 0))
        self.db.add(media)
        self.db.flush()

        # 5. Add Playlist
        playlist = Playlist(name="My Favs", is_smart=False, created_at=datetime(2026, 5, 25, 9, 0, 0))
        self.db.add(playlist)
        self.db.flush()

        # 6. Add Playlist Media relation
        pm = PlaylistMedia(playlist_id=playlist.id, media_id=media.id, added_at=datetime(2026, 5, 26, 11, 0, 0))
        self.db.add(pm)

        # 7. Add Playback Event
        evt = PlaybackEvent(media_id=media.id, start_time=datetime(2026, 5, 27, 10, 0, 0), duration_watched=60.0, completed=False)
        self.db.add(evt)

        self.db.commit()

        # Call endpoint
        response = self.client.get("/api/v1/sync/export?user_id=user_123")
        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data["version"], 1)
        self.assertEqual(len(data["users"]), 1)
        self.assertEqual(data["users"][0]["name"], "Original User")
        self.assertEqual(len(data["tracks"]), 1)
        self.assertEqual(data["tracks"][0]["title"], "Song A")
        self.assertEqual(len(data["listening_history"]), 1)
        self.assertEqual(data["listening_history"][0]["duration_played"], 180.0)
        self.assertEqual(len(data["focus_sessions"]), 1)
        self.assertEqual(data["focus_sessions"][0]["focus_score"], 85.0)
        self.assertEqual(len(data["media"]), 1)
        self.assertEqual(data["media"][0]["filename"], "song_a.mp3")
        self.assertEqual(len(data["playlists"]), 1)
        self.assertEqual(data["playlists"][0]["name"], "My Favs")
        self.assertEqual(len(data["playlist_media"]), 1)
        self.assertEqual(len(data["playback_events"]), 1)

    def test_import_sync_data(self):
        payload = {
            "version": 1,
            "users": [
                {"id": "user_123", "name": "Updated User Name", "email": "user@test.com", "preferences": '{"theme": "light"}'}
            ],
            "tracks": [
                {"id": 99, "title": "Imported Track", "artist": "Imported Artist", "bpm": 90.0, "valence": 0.8, "energy": 0.4, "instrumentalness": 0.95, "genre": "Ambient"}
            ],
            "listening_history": [
                {"id": 55, "user_id": "user_123", "track_id": 99, "listened_at": "2026-05-27T15:00:00", "duration_played": 200.0, "completed": True, "skipped": False}
            ],
            "focus_sessions": [
                {"id": 66, "user_id": "user_123", "started_at": "2026-05-27T14:00:00", "ended_at": "2026-05-27T14:45:00", "total_skips": 0, "focus_score": 98.0}
            ],
            "media": [
                {"id": 77, "type": "music", "title": "Imported Track", "artist": "Imported Artist", "filename": "imported.mp3", "format": "mp3", "added_at": "2026-05-27T12:00:00"}
            ],
            "playlists": [
                {"id": 88, "name": "Imported Playlist", "is_smart": True, "created_at": "2026-05-27T10:00:00"}
            ],
            "playlist_media": [
                {"id": 10, "playlist_id": 88, "media_id": 77, "added_at": "2026-05-27T13:00:00"}
            ],
            "playback_events": [
                {"id": 20, "media_id": 77, "start_time": "2026-05-27T16:00:00", "duration_watched": 45.0, "completed": False}
            ]
        }

        # Import first time (inserts)
        res = self.client.post("/api/v1/sync/import", json=payload)
        self.assertEqual(res.status_code, 200)

        # Verify insertions
        db = self.db
        user = db.query(User).filter(User.id == "user_123").first()
        self.assertEqual(user.name, "Updated User Name")
        self.assertEqual(user.preferences, '{"theme": "light"}')

        track = db.query(Track).filter(Track.title == "Imported Track").first()
        self.assertIsNotNone(track)
        self.assertEqual(track.bpm, 90.0)

        hist = db.query(ListeningHistory).filter(ListeningHistory.user_id == "user_123").first()
        self.assertIsNotNone(hist)
        self.assertEqual(hist.track_id, track.id) # Should map remote ID 99 to local generated ID
        self.assertEqual(hist.duration_played, 200.0)

        sess = db.query(FocusSession).filter(FocusSession.user_id == "user_123").first()
        self.assertIsNotNone(sess)
        self.assertEqual(sess.focus_score, 98.0)

        media = db.query(Media).filter(Media.filename == "imported.mp3").first()
        self.assertIsNotNone(media)

        playlist = db.query(Playlist).filter(Playlist.name == "Imported Playlist").first()
        self.assertIsNotNone(playlist)

        pm = db.query(PlaylistMedia).filter(PlaylistMedia.playlist_id == playlist.id, PlaylistMedia.media_id == media.id).first()
        self.assertIsNotNone(pm)

        evt = db.query(PlaybackEvent).filter(PlaybackEvent.media_id == media.id).first()
        self.assertIsNotNone(evt)

        # Import second time with same data (should skip duplicates and not crash)
        res_dup = self.client.post("/api/v1/sync/import", json=payload)
        self.assertEqual(res_dup.status_code, 200)

        # Count records to ensure no duplicates were added
        self.assertEqual(db.query(Track).count(), 1)
        self.assertEqual(db.query(ListeningHistory).count(), 1)
        self.assertEqual(db.query(FocusSession).count(), 1)
        self.assertEqual(db.query(Media).count(), 1)
        self.assertEqual(db.query(Playlist).count(), 1)
        self.assertEqual(db.query(PlaylistMedia).count(), 1)
        self.assertEqual(db.query(PlaybackEvent).count(), 1)
