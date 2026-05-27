import os
import unittest
from datetime import datetime, timedelta
import math

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient

# Configure environment variables to use an in-memory database for testing
os.environ["DATABASE_URL"] = "sqlite:///:memory:"

from database import Base, get_db
from models import Track, User, ListeningHistory, FocusSession, SystemSetting
from main import app
import services.smart_music_service as sms
import services.gemini_service as gs

from sqlalchemy.pool import StaticPool

# Create engine and session for unit testing with StaticPool to share connection in-memory
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

# Override the database dependency in FastAPI app
app.dependency_overrides[get_db] = override_get_db


class TestSmartMusic(unittest.TestCase):
    
    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=engine)
        cls.db = TestingSessionLocal()
        cls.client = TestClient(app)

        # 1. Seed users
        cls.user = User(id="1", name="Test User", preferences='{"favorite_genres": ["lo-fi", "techno"]}')
        cls.other_user = User(id="2", name="Other User")
        cls.db.add_all([cls.user, cls.other_user])
        cls.db.commit()

        # 2. Seed tracks
        # Baroque / Lo-Fi Track (Focus)
        cls.t_lofi = Track(
            id=1, title="Lofi Chill", artist="Lofi Artist", 
            bpm=75.0, valence=0.7, energy=0.3, instrumentalness=0.9, genre="Lo-Fi"
        )
        # Techno / Deep House Track (Energy Focus)
        cls.t_techno = Track(
            id=2, title="Deep Techno", artist="Techno DJ", 
            bpm=125.0, valence=0.8, energy=0.9, instrumentalness=0.85, genre="Techno"
        )
        # High Energy, Low Valence (Stressed / Metallish)
        cls.t_stressed = Track(
            id=3, title="Stress Metal", artist="Metal Band", 
            bpm=135.0, valence=0.2, energy=0.95, instrumentalness=0.1, genre="Metal"
        )
        # Low Energy, Low Valence (Sad / Bored)
        cls.t_sad = Track(
            id=4, title="Sad Rain", artist="Sad Singer", 
            bpm=65.0, valence=0.15, energy=0.2, instrumentalness=0.3, genre="Acoustic"
        )
        # Calm Track (Target for Iso-principle)
        cls.t_calm = Track(
            id=5, title="Calm Breeze", artist="Zen Master", 
            bpm=80.0, valence=0.75, energy=0.25, instrumentalness=0.95, genre="Ambient"
        )
        # General Pop Track
        cls.t_pop = Track(
            id=6, title="Pop Anthem", artist="Pop Star", 
            bpm=110.0, valence=0.9, energy=0.75, instrumentalness=0.0, genre="Pop"
        )

        cls.db.add_all([cls.t_lofi, cls.t_techno, cls.t_stressed, cls.t_sad, cls.t_calm, cls.t_pop])
        cls.db.commit()

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        Base.metadata.drop_all(bind=engine)

    def tearDown(self):
        # Clear dynamic tables after each test to ensure test isolation
        self.db.query(ListeningHistory).delete()
        self.db.query(FocusSession).delete()
        self.db.query(SystemSetting).delete()
        self.db.commit()

    def test_focus_score_calculation(self):
        # Create a FocusSession
        session = FocusSession(id=1, user_id=1, started_at=datetime.utcnow() - timedelta(minutes=10))
        self.db.add(session)
        self.db.commit()

        # Log some listening history during session
        # Play track 1: Lo-Fi. Uninterrupted (completed=True, skipped=False, duration_played=180s)
        lh1 = ListeningHistory(
            user_id=1, track_id=1, duration_played=180.0, completed=True, skipped=False,
            listened_at=datetime.utcnow() - timedelta(minutes=8)
        )
        # Play track 6: Pop. Interrupted (completed=False, skipped=True, duration_played=30.0)
        lh2 = ListeningHistory(
            user_id=1, track_id=6, duration_played=30.0, completed=False, skipped=True,
            listened_at=datetime.utcnow() - timedelta(minutes=4)
        )
        self.db.add_all([lh1, lh2])
        self.db.commit()

        session.ended_at = datetime.utcnow()
        self.db.commit()

        # Execute focus score calculation
        score = sms.calculate_focus_score(self.db, session.id)
        
        # Expected calculation:
        # uninterrupted duration = 180s
        # total duration played = 210s
        # session duration = 600s (10 minutes)
        # ratio = 180 / 600 = 0.3
        # instrumentalness of track 1 = 0.9, track 6 = 0.0 -> average = 0.45
        # Expected EF = 0.3 * 0.45 = 0.135
        self.assertAlmostEqual(score, 0.135, places=3)

    def test_optimal_bpm_range(self):
        # Setup history where Techno has a 100% skip rate and Baroque has a 0% skip rate
        # Create completed focus session
        s1 = FocusSession(id=10, user_id=1, started_at=datetime.utcnow() - timedelta(hours=2), ended_at=datetime.utcnow() - timedelta(hours=1))
        self.db.add(s1)
        self.db.commit()

        # Baroque track listened (uninterrupted)
        lh1 = ListeningHistory(
            user_id=1, track_id=1, completed=True, skipped=False,
            listened_at=datetime.utcnow() - timedelta(minutes=100)
        )
        # Techno track listened (skipped)
        lh2 = ListeningHistory(
            user_id=1, track_id=2, completed=False, skipped=True,
            listened_at=datetime.utcnow() - timedelta(minutes=80)
        )
        self.db.add_all([lh1, lh2])
        self.db.commit()

        analysis = sms.get_optimal_bpm_range(self.db, "1")
        self.assertEqual(analysis["optimal_range"], [60.0, 90.0])
        self.assertEqual(analysis["baroque_skip_rate"], 0.0)
        self.assertEqual(analysis["techno_skip_rate"], 1.0)

    def test_current_mood_ea_russell(self):
        # Add a mix of recently played songs within 45 mins
        lh1 = ListeningHistory(
            user_id=1, track_id=3, completed=True, skipped=False,
            listened_at=datetime.utcnow() - timedelta(minutes=5)  # Heavy weight (stressed)
        )
        lh2 = ListeningHistory(
            user_id=1, track_id=1, completed=True, skipped=False,
            listened_at=datetime.utcnow() - timedelta(minutes=40) # Lighter weight (lofi)
        )
        self.db.add_all([lh1, lh2])
        self.db.commit()

        mood = sms.get_current_mood_ea(self.db, "1")
        # Track 3: energy=0.95, valence=0.2. Weight near 5m ago is high.
        # Track 1: energy=0.3, valence=0.7. Weight near 40m ago is low.
        # We expect final state to have low valence (< 0.5) and high energy (>= 0.5) -> "Estresado/Frustrado"
        self.assertEqual(mood["description"], "Estresado/Frustrado")
        self.assertEqual(mood["quadrant"], "Alta Energía, Baja Valencia")

    def test_iso_principle_emotional_equalization(self):
        # We simulate the current user is Stressed: High Energy, Low Valence
        # Log recent heavy track
        lh = ListeningHistory(
            user_id=1, track_id=3, completed=True, skipped=False,
            listened_at=datetime.utcnow() - timedelta(minutes=2)
        )
        self.db.add(lh)
        self.db.commit()

        queue = sms.get_iso_principle_queue(self.db, "1")
        
        # We expect a queue of up to 5 tracks transitioning down energy and up valence
        self.assertEqual(len(queue), 5)
        
        # Verify energy decreases step-by-step
        prev_target_energy = 1.0
        for item in queue:
            self.assertLess(item["target_energy"], prev_target_energy)
            prev_target_energy = item["target_energy"]

    def test_song_burnout_fc(self):
        # Track 1 has 5 plays and 1 skip in the last 7 days
        for i in range(4):
            lh = ListeningHistory(user_id=1, track_id=1, completed=True, skipped=False, listened_at=datetime.utcnow() - timedelta(days=1))
            self.db.add(lh)
        lh_skip = ListeningHistory(user_id=1, track_id=1, completed=False, skipped=True, listened_at=datetime.utcnow() - timedelta(days=2))
        self.db.add(lh_skip)
        self.db.commit()

        fc = sms.get_song_burnout(self.db, 1)
        # Plays = 5 (4 completes + 1 skip), Skips = 1
        # FC = 5 / (1 + 1) = 2.5
        self.assertEqual(fc, 2.5)

    def test_explore_vs_exploit_dynamic_queue(self):
        # Log some completed tracks to establish genre affinity ("Lo-Fi")
        lh = ListeningHistory(user_id=1, track_id=1, completed=True, skipped=False)
        self.db.add(lh)
        # Log a play from another user in the last 7 days (track 2 - Techno) which current user has never listened to
        lh_other = ListeningHistory(user_id=2, track_id=2, completed=True, skipped=False, listened_at=datetime.utcnow() - timedelta(days=2))
        self.db.add(lh_other)
        self.db.commit()

        queue = sms.generate_dynamic_queue(self.db, user_id="1", ideal_bpm=80.0, queue_size=5)
        
        # Verify the queue is generated and has Exploit & Explore types
        self.assertTrue(len(queue) > 0)
        types = [item["type"] for item in queue]
        self.assertIn("Exploit", types)

    def test_gemini_nlp_heuristic_fallback(self):
        # No api key set, so it should use fallback parser
        # Context 1: Relaxing/Lo-fi
        ctx1 = gs._parse_context_offline_fallback("Estoy cansado de programar, necesito relajarme con lofi")
        self.assertEqual(ctx1["bpm_range"], [60.0, 90.0])
        self.assertTrue(ctx1["instrumental"])
        
        # Context 2: Energy/Workout
        ctx2 = gs._parse_context_offline_fallback("Voy a correr un maratón y quiero techno rápido")
        self.assertEqual(ctx2["bpm_range"], [120.0, 140.0])
        self.assertGreater(ctx2["energy_range"][0], 0.6)

    def test_gemini_report_template_fallback(self):
        summary = {
            "avg_focus_score": 0.75,
            "total_sessions": 3,
            "total_skips": 4,
            "skip_rate": 0.12,
            "dominant_mood": "Baja Energía, Alta Valencia",
            "optimal_bpm_range": [60.0, 90.0],
            "top_focus_tracks": [{"title": "Lofi Chill", "artist": "Lofi Artist", "plays": 3, "completion_rate": 1.0}],
            "top_distractor_tracks": [{"title": "Pop Anthem", "artist": "Pop Star", "skips": 2, "avg_skip_time_seconds": 15.0}],
            "temporal_profile": {
                "morning": {"sessions": 2, "avg_focus_score": 0.8, "total_skips": 1},
                "afternoon": {"sessions": 1, "avg_focus_score": 0.6, "total_skips": 3},
                "evening_night": {"sessions": 0, "avg_focus_score": 0.0, "total_skips": 0}
            },
            "genre_focus_correlation": [{"genre": "lo-fi", "plays": 3, "completion_rate": 1.0, "skip_rate": 0.0}]
        }
        report = gs._generate_report_offline_fallback(summary)
        self.assertIn("# Reporte Semanal de Productividad Musical", report)
        self.assertIn("0.75 / 1.00", report)
        self.assertIn("60-90 BPM", report)
        self.assertIn("Lofi Chill", report)
        self.assertIn("Pop Anthem", report)
        self.assertIn("Mañana (06:00-12:00)", report)
        self.assertIn("Lo-fi", report)

    def test_new_focus_analytics_helpers(self):
        # 1. Create a Focus Session
        session = FocusSession(id=100, user_id="1", started_at=datetime.utcnow() - timedelta(hours=2), ended_at=datetime.utcnow() - timedelta(hours=1))
        self.db.add(session)
        self.db.commit()

        # 2. Add some listening history inside the session
        lh_focus = ListeningHistory(
            user_id="1", track_id=1, completed=True, skipped=False, duration_played=180.0,
            listened_at=datetime.utcnow() - timedelta(minutes=100)
        )
        lh_skip = ListeningHistory(
            user_id="1", track_id=6, completed=False, skipped=True, duration_played=15.0, skip_time=15.0,
            listened_at=datetime.utcnow() - timedelta(minutes=80)
        )
        self.db.add_all([lh_focus, lh_skip])
        self.db.commit()

        # Test get_top_focus_tracks
        enablers = sms.get_top_focus_tracks(self.db, "1", limit=2)
        self.assertEqual(len(enablers), 1)
        self.assertEqual(enablers[0]["title"], "Lofi Chill")
        self.assertEqual(enablers[0]["completion_rate"], 1.0)

        # Test get_top_distractor_tracks
        distractors = sms.get_top_distractor_tracks(self.db, "1", limit=2)
        self.assertEqual(len(distractors), 1)
        self.assertEqual(distractors[0]["title"], "Pop Anthem")
        self.assertEqual(distractors[0]["skip_rate"], 1.0)
        self.assertEqual(distractors[0]["avg_skip_time_seconds"], 15.0)

        # Test get_temporal_focus_profile
        profile = sms.get_temporal_focus_profile(self.db, "1")
        self.assertIn("morning", profile)
        self.assertIn("afternoon", profile)
        self.assertIn("evening_night", profile)
        
        # Test get_genre_focus_correlation
        correlation = sms.get_genre_focus_correlation(self.db, "1")
        self.assertTrue(len(correlation) >= 2)
        # Sorts by completion rate, so lo-fi should be first
        self.assertEqual(correlation[0]["genre"], "lo-fi")
        self.assertEqual(correlation[0]["completion_rate"], 1.0)

    # ── API ENDPOINT INTEGRATION TESTS ────────────────────────────────────────

    def test_api_gemini_key_db_storage(self):
        # Save key
        response = self.client.post("/api/v1/settings/gemini-key", json={"api_key": "test_google_gemini_api_key_123"})
        self.assertEqual(response.status_code, 200)
        
        # Check that it exists in the test DB
        setting = self.db.query(SystemSetting).filter(SystemSetting.key == "gemini_api_key").first()
        self.assertIsNotNone(setting)
        self.assertEqual(setting.value, "test_google_gemini_api_key_123")

    def test_api_focus_session_flow(self):
        # Start session
        response = self.client.post("/api/v1/smart/focus/session/start", json={"user_id": "1"})
        self.assertEqual(response.status_code, 200)
        data = response.json()
        session_id = data["session_id"]
        
        # Log a listening event
        lh_response = self.client.post("/api/v1/smart/listening-history/log", json={
            "user_id": "1",
            "track_id": 1,
            "duration_played": 120.0,
            "completed": True,
            "skipped": False
        })
        self.assertEqual(lh_response.status_code, 200)

        # End session
        end_response = self.client.post("/api/v1/smart/focus/session/end", json={"session_id": session_id})
        self.assertEqual(end_response.status_code, 200)
        end_data = end_response.json()
        self.assertEqual(end_data["total_skips"], 0)
        self.assertGreater(end_data["focus_score"], 0.0)

    def test_api_get_optimal_bpm_priorities(self):
        response = self.client.get("/api/v1/smart/focus/bpm-optimum?user_id=1")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("bpm_analysis", data)
        self.assertIn("prioritized_tracks", data)

    def test_api_get_iso_principle(self):
        response = self.client.post("/api/v1/smart/mood/iso-principle", json={"user_id": "1"})
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("queue", data)

    def test_api_generate_playlist_queue(self):
        response = self.client.post("/api/v1/smart/playlist/queue", json={
            "user_id": "1",
            "ideal_bpm": 80.0,
            "queue_size": 3
        })
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["queue_size"], 3)
        self.assertEqual(len(data["queue"]), 3)

    def test_api_weekly_report(self):
        response = self.client.post("/api/v1/smart/gemini/weekly-report", json={"user_id": "1"})
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("report", data)
        self.assertIn("# Reporte Semanal", data["report"])


if __name__ == "__main__":
    unittest.main()
