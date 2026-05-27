import csv
from pathlib import Path
from datetime import datetime
from database import engine, SessionLocal
from models import Base, Media, Playlist, PlaylistMedia, Track, User, ListeningHistory, FocusSession, SystemSetting
from config import settings

def init_db():
    print("Creating tables...")
    Base.metadata.create_all(bind=engine)
    print("Tables created.")
    
    seed_default_user()
    migrate_csv_data()

def seed_default_user():
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.id == "1").first()
        if not user:
            print("Seeding default user...")
            default_user = User(id="1", name="Usuario Principal", preferences='{"favorite_genres": []}')
            db.add(default_user)
            db.commit()
            print("Default user seeded.")
    except Exception as e:
        print(f"Error seeding user: {e}")
        db.rollback()
    finally:
        db.close()

def migrate_csv_data():
    csv_path = settings.BASE_DIR / "music_library.csv"
    if not csv_path.exists():
        print("No music_library.csv found. Skipping migration.")
        return

    db = SessionLocal()
    try:
        # Check if we already migrated
        existing_count = db.query(Media).count()
        if existing_count > 0:
            print(f"Database already has {existing_count} media entries. Skipping migration.")
            return
            
        print("Migrating data from music_library.csv to SQLite...")
        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            
            # Cache playlists
            playlists = {}
            
            for row in reader:
                filename = row.get("Filename")
                if not filename:
                    continue
                    
                title = row.get("Title", "")
                artist = row.get("Artist", "")
                album = row.get("Album", "")
                genre = row.get("Genre", "")
                year = row.get("Year", "")
                shazam_url = row.get("ShazamURL", "")
                playlist_name = row.get("Playlist", "")
                
                downloaded_str = row.get("Downloaded", "")
                added_at = datetime.utcnow()
                if downloaded_str:
                    try:
                        added_at = datetime.fromisoformat(downloaded_str)
                    except ValueError:
                        pass
                
                # Determine type
                media_type = "music"
                fmt = ""
                if filename.endswith(".mp3"):
                    fmt = "mp3"
                elif filename.endswith(".mp4"):
                    media_type = "video"
                    fmt = "mp4"
                
                media = Media(
                    type=media_type,
                    title=title,
                    artist=artist,
                    album=album,
                    genre=genre,
                    year=year,
                    filename=filename,
                    format=fmt,
                    shazam_url=shazam_url,
                    added_at=added_at
                )
                db.add(media)
                db.flush() # get media.id
                
                if playlist_name:
                    if playlist_name not in playlists:
                        playlist = Playlist(name=playlist_name, is_smart=False)
                        db.add(playlist)
                        db.flush()
                        playlists[playlist_name] = playlist
                        
                    pm = PlaylistMedia(
                        playlist_id=playlists[playlist_name].id,
                        media_id=media.id,
                        added_at=added_at
                    )
                    db.add(pm)
                    
        db.commit()
        print("Migration complete!")
    except Exception as e:
        print(f"Error during migration: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    init_db()
