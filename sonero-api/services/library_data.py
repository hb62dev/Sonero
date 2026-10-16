"""
One view of every library song with its metadata, listening history and
audio features. Shared by the mix algorithm, the MCP server and the API.
"""

from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy.orm import Session

from config import settings
from models import AudioFeatures, Media, PlaybackEvent, SongRating

AUDIO_EXTS = {".mp3", ".m4a", ".opus", ".ogg", ".wav", ".aac", ".flac", ".wma", ".webm"}


@dataclass
class LibrarySong:
    media_id: int
    filename: str  # path relative to the music folder, as the app uses it
    title: str
    artist: str
    album: str
    genre: str
    year: str
    type: str
    added_at: datetime | None
    plays: int = 0
    seconds: float = 0.0
    completed: int = 0
    skips: int = 0  # plays stopped in the first 30 s
    last_played: datetime | None = None
    hours: Counter = field(default_factory=Counter)  # local hour -> plays
    bpm: float | None = None
    energy: float | None = None
    brightness: float | None = None
    danceability: float | None = None
    duration: float | None = None
    rating: int | None = None  # 1 me gusta, 0 me da igual, -1 no me gusta (from a mix)

    @property
    def completion_rate(self) -> float | None:
        return self.completed / self.plays if self.plays else None

    @property
    def skip_rate(self) -> float | None:
        return self.skips / self.plays if self.plays else None

    def days_since_played(self, now: datetime) -> float | None:
        return (now - self.last_played).total_seconds() / 86400 if self.last_played else None

    def to_dict(self) -> dict:
        local = lambda d: d.replace(tzinfo=timezone.utc).astimezone().isoformat(timespec="seconds") if d else None
        return {
            "media_id": self.media_id,
            "filename": self.filename,
            "title": self.title,
            "artist": self.artist or None,
            "album": self.album or None,
            "genre": self.genre or None,
            "year": self.year or None,
            "type": self.type,
            "added_at": local(self.added_at),
            "plays": self.plays,
            "minutes": round(self.seconds / 60, 1),
            "completion_rate": round(self.completion_rate, 2) if self.completion_rate is not None else None,
            "skip_rate": round(self.skip_rate, 2) if self.skip_rate is not None else None,
            "last_played": local(self.last_played),
            "favorite_hours": [h for h, _ in self.hours.most_common(3)],
            "bpm": round(self.bpm) if self.bpm else None,
            "energy": round(self.energy, 2) if self.energy is not None else None,
            "brightness": round(self.brightness, 2) if self.brightness is not None else None,
            "danceability": round(self.danceability, 2) if self.danceability is not None else None,
            "duration": round(self.duration) if self.duration else None,
            "rating": self.rating,
        }


def relative_paths() -> dict[str, str]:
    """File name -> path relative to the music folder (songs may live in playlist folders)."""
    paths: dict[str, str] = {}
    root = settings.MUSIC_DIR
    if root.exists():
        for f in root.rglob("*"):
            if f.is_file() and f.suffix.lower() in AUDIO_EXTS and not f.name.startswith("."):
                paths.setdefault(f.name, f.relative_to(root).as_posix())
    return paths


def resolve_file(filename: str) -> Path | None:
    rel = relative_paths().get(Path(filename).name)
    return settings.MUSIC_DIR / rel if rel else None


def load_library(db: Session, include_missing: bool = False) -> list[LibrarySong]:
    """Every music file in the library with its usage and audio features."""
    paths = relative_paths()
    features = {f.media_id: f for f in db.query(AudioFeatures)}
    songs: dict[int, LibrarySong] = {}

    for m in db.query(Media).filter(Media.type == "music"):
        rel = paths.get(Path(m.filename).name)
        if rel is None and not include_missing:
            continue
        f = features.get(m.id)
        songs[m.id] = LibrarySong(
            media_id=m.id,
            filename=rel or m.filename,
            title=m.title or Path(m.filename).stem,
            artist=(m.artist or "").strip(),
            album=(m.album or "").strip(),
            genre=(m.genre or "").strip(),
            year=(m.year or "").strip(),
            type=m.type,
            added_at=m.added_at,
            bpm=f.bpm if f else None,
            energy=f.energy if f else None,
            brightness=f.brightness if f else None,
            danceability=f.danceability if f else None,
            duration=f.duration if f else None,
        )

    for e in db.query(PlaybackEvent).filter(PlaybackEvent.media_id.in_(songs.keys())):
        s = songs[e.media_id]
        secs = e.duration_watched or 0
        s.plays += 1
        s.seconds += secs
        s.completed += 1 if e.completed else 0
        if not e.completed and secs < 30:
            s.skips += 1
        if e.start_time and (s.last_played is None or e.start_time > s.last_played):
            s.last_played = e.start_time
        if e.start_time:
            s.hours[e.start_time.replace(tzinfo=timezone.utc).astimezone().hour] += 1

    for r in db.query(SongRating).filter(SongRating.media_id.in_(songs.keys())):
        songs[r.media_id].rating = r.rating

    return list(songs.values())


def taste_profile(songs: list[LibrarySong]) -> dict:
    """What the listener plays most, weighted by listening time."""
    # Same artist written differently ("playboi carti" / "Playboi Carti") counts once,
    # shown with its best-looking spelling
    spellings: dict[str, Counter] = {}

    def key(name: str) -> str:
        k = " ".join(name.lower().split())
        spellings.setdefault(k, Counter())[name] += 1
        return k

    artists: Counter = Counter()
    genres: Counter = Counter()
    library_artists: Counter = Counter()
    for s in songs:
        names = split_artists(s.artist) if s.artist else []
        for a in names:
            library_artists[key(a)] += 1
        weight = s.seconds / 60 + s.plays  # minutes plus a bonus per play
        if weight <= 0:
            continue
        for a in names:
            artists[key(a)] += weight
        if s.genre:
            genres[s.genre] += weight

    def display(k: str) -> str:
        forms = spellings[k]
        return max(forms, key=lambda f: (f != f.lower(), forms[f]))

    return {
        "top_artists": [display(a) for a, _ in artists.most_common(10)],
        "top_genres": [g for g, _ in genres.most_common(5)],
        "library_artists": [display(a) for a, _ in library_artists.most_common(15)],
    }


def split_artists(artist: str) -> list[str]:
    """'Post Malone, Swae Lee' / 'A & B' / 'A ft. B' -> individual names."""
    import re

    parts = re.split(r"\s*(?:,|&| x | feat\.? | ft\.? | y | and )\s*", artist, flags=re.IGNORECASE)
    return [p.strip() for p in parts if p.strip()]
