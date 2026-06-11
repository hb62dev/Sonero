import os
import unittest
import tempfile
import shutil
from pathlib import Path
from datetime import datetime
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool

# Force in-memory DB for tests
os.environ["DATABASE_URL"] = "sqlite:///:memory:"

from database import Base, get_db
from models import Media, Playlist, PlaylistMedia, PlaybackEvent
from config import settings
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

class TestDuplicates(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=engine)
        cls.db = TestingSessionLocal()
        cls.client = TestClient(app)

        # Save original directories
        cls.orig_music_dir = settings.MUSIC_DIR
        cls.orig_video_dir = settings.VIDEO_DIR

        # Create temp directories
        cls.temp_dir = tempfile.mkdtemp()
        cls.temp_path = Path(cls.temp_dir)
        settings.MUSIC_DIR = cls.temp_path / "downloads"
        settings.VIDEO_DIR = cls.temp_path / "downloads" / "videos"

        settings.MUSIC_DIR.mkdir(parents=True, exist_ok=True)
        settings.VIDEO_DIR.mkdir(parents=True, exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        # Restore original settings
        settings.MUSIC_DIR = cls.orig_music_dir
        settings.VIDEO_DIR = cls.orig_video_dir
        # Remove temp directory
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def setUp(self):
        # Clean database tables
        self.db.query(PlaylistMedia).delete()
        self.db.query(Playlist).delete()
        self.db.query(PlaybackEvent).delete()
        self.db.query(Media).delete()
        self.db.commit()

        # Clean filesystem
        for f in settings.MUSIC_DIR.rglob("*"):
            if f.is_file():
                f.unlink()
        for f in settings.VIDEO_DIR.rglob("*"):
            if f.is_file():
                f.unlink()

    def test_duplicates_empty(self):
        response = self.client.get("/api/v1/downloads/duplicates")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(len(data["exact_duplicates"]), 0)

    def test_duplicates_detection(self):
        # Create identical files
        file1 = settings.MUSIC_DIR / "song1.mp3"
        file2 = settings.MUSIC_DIR / "song2.mp3"
        file3 = settings.MUSIC_DIR / "song3.mp3" # different content

        file1.write_bytes(b"hello world")
        file2.write_bytes(b"hello world")
        file3.write_bytes(b"hello world different")

        # Run detection
        response = self.client.get("/api/v1/downloads/duplicates")
        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(len(data["exact_duplicates"]), 1)
        group = data["exact_duplicates"][0]
        self.assertEqual(len(group["files"]), 2)
        filenames = [f["filename"] for f in group["files"]]
        self.assertIn("song1.mp3", filenames)
        self.assertIn("song2.mp3", filenames)

    def test_duplicates_clean(self):
        # Setup duplicate files
        file1 = settings.MUSIC_DIR / "original.mp3"
        file2 = settings.MUSIC_DIR / "copy (1).mp3"
        
        file1.write_bytes(b"duplicate content")
        file2.write_bytes(b"duplicate content")

        # Insert DB entries
        media1 = Media(type="music", title="Track A", artist="Artist A", filename="original.mp3", format="mp3", added_at=datetime.utcnow())
        media2 = Media(type="music", title="Track A", artist="Artist A", filename="copy (1).mp3", format="mp3", added_at=datetime.utcnow())
        self.db.add(media1)
        self.db.add(media2)
        self.db.flush()

        # Setup playlist
        playlist = Playlist(name="Test Playlist")
        self.db.add(playlist)
        self.db.flush()

        # Link both to playlist
        pm1 = PlaylistMedia(playlist_id=playlist.id, media_id=media1.id, added_at=datetime.utcnow())
        pm2 = PlaylistMedia(playlist_id=playlist.id, media_id=media2.id, added_at=datetime.utcnow())
        self.db.add(pm1)
        self.db.add(pm2)

        # Add playback event to media2 (copy)
        evt = PlaybackEvent(media_id=media2.id, start_time=datetime.utcnow(), duration_watched=30.0, completed=True)
        self.db.add(evt)
        self.db.commit()

        # Verify initial DB state
        self.assertEqual(self.db.query(Media).count(), 2)
        self.assertEqual(self.db.query(PlaylistMedia).count(), 2)
        self.assertEqual(self.db.query(PlaybackEvent).count(), 1)

        # Run cleanup endpoint
        response = self.client.post("/api/v1/downloads/duplicates/clean", json={"dry_run": False})
        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data["deleted_count"], 1)
        self.assertEqual(data["deleted_files"], ["copy (1).mp3"])

        # Check physical files
        self.assertTrue(file1.exists())
        self.assertFalse(file2.exists())

        # Check DB reconciliation
        self.assertEqual(self.db.query(Media).count(), 1)
        winner_media = self.db.query(Media).first()
        self.assertEqual(winner_media.filename, "original.mp3")

        # PlaylistMedia should only have 1 entry (linked to original.mp3)
        self.assertEqual(self.db.query(PlaylistMedia).count(), 1)
        pm = self.db.query(PlaylistMedia).first()
        self.assertEqual(pm.media_id, winner_media.id)

        # PlaybackEvent should now point to original.mp3
        self.assertEqual(self.db.query(PlaybackEvent).count(), 1)
        pe = self.db.query(PlaybackEvent).first()
        self.assertEqual(pe.media_id, winner_media.id)
