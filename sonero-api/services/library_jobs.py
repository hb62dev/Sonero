"""
Background jobs that improve the data recommendations are built from:

* Metadata enrichment: looks up missing artist/album/genre/year in public
  catalogs and produces proposals the user reviews before anything is saved.
* Audio analysis: computes BPM, energy, brightness and danceability locally
  (no internet) with librosa, if installed.
"""

import asyncio
import logging
import time
from dataclasses import dataclass, field
from datetime import datetime

from database import SessionLocal
from models import AudioFeatures, Media
from services import music_catalog
from services.library_data import resolve_file

logger = logging.getLogger("sonero.library_jobs")

AUTO_SELECT_CONFIDENCE = 0.8
MIN_CONFIDENCE = 0.6
FIELDS = ("artist", "album", "genre", "year")


@dataclass
class JobState:
    running: bool = False
    done: int = 0
    total: int = 0
    started_at: float | None = None
    finished_at: float | None = None
    error: str | None = None
    results: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "running": self.running,
            "done": self.done,
            "total": self.total,
            "error": self.error,
            "finished_at": self.finished_at,
        }


enrichment = JobState()
analysis = JobState()
_tasks: set[asyncio.Task] = set()


def _spawn(coro) -> None:
    task = asyncio.create_task(coro)
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


# ── Metadata enrichment ───────────────────────────────────────────────────────

def start_enrichment(only_missing: bool = True) -> None:
    if enrichment.running:
        return
    db = SessionLocal()
    try:
        rows = [(m.id, m.filename, m.title or "", m.artist or "", m.album or "", m.genre or "", m.year or "")
                for m in db.query(Media).filter(Media.type == "music")]
    finally:
        db.close()
    if only_missing:
        rows = [r for r in rows if not all(r[3:7])]

    enrichment.__init__(running=True, total=len(rows), started_at=time.time())
    _spawn(_run_enrichment(rows))


async def _run_enrichment(rows: list[tuple]) -> None:
    try:
        reachable = True
        for media_id, filename, title, artist, album, genre, year in rows:
            current = {"title": title, "artist": artist, "album": album, "genre": genre, "year": year}
            try:
                found = await music_catalog.lookup_metadata(title, artist) if reachable else None
            except music_catalog.CatalogUnavailable:
                found = None
            enrichment.done += 1
            if found is None or found["confidence"] < MIN_CONFIDENCE:
                continue
            changes = {f: found[f] for f in FIELDS if not current[f] and found.get(f)}
            if not changes:
                continue
            enrichment.results.append({
                "media_id": media_id,
                "filename": filename,
                "current": current,
                "found": {k: found.get(k) for k in ("title", "artist", "album", "genre", "year")},
                "changes": changes,
                "confidence": found["confidence"],
                "source": found["source"],
                "selected": found["confidence"] >= AUTO_SELECT_CONFIDENCE,
            })
        if enrichment.done and not enrichment.results and not await _online():
            enrichment.error = "Sin conexión a internet: no se pudieron consultar los catálogos."
    except Exception as e:  # never leave the job stuck in "running"
        logger.exception("Enrichment failed")
        enrichment.error = str(e)
    finally:
        enrichment.running = False
        enrichment.finished_at = time.time()


async def _online() -> bool:
    try:
        await music_catalog.search_tracks("test", limit=1)
        return True
    except music_catalog.CatalogUnavailable:
        return False


def apply_enrichment(media_ids: list[int]) -> dict:
    """Saves the reviewed proposals: fills only empty fields, in the DB and the MP3 tags."""
    wanted = set(media_ids)
    proposals = [p for p in enrichment.results if p["media_id"] in wanted]
    applied, tagged = 0, 0
    db = SessionLocal()
    try:
        for p in proposals:
            media = db.get(Media, p["media_id"])
            if media is None:
                continue
            for f, value in p["changes"].items():
                if not getattr(media, f):
                    setattr(media, f, value)
            applied += 1
            path = resolve_file(media.filename)
            if path is not None and path.suffix.lower() == ".mp3" and _write_id3(path, p["changes"]):
                tagged += 1
        db.commit()
    finally:
        db.close()
    enrichment.results = [p for p in enrichment.results if p["media_id"] not in wanted]
    return {"applied": applied, "tags_written": tagged}


def _write_id3(path, changes: dict) -> bool:
    try:
        from mutagen.id3 import ID3, ID3NoHeaderError, TALB, TCON, TDRC, TPE1

        try:
            tags = ID3(path)
        except ID3NoHeaderError:
            tags = ID3()
        frames = {"artist": TPE1, "album": TALB, "genre": TCON, "year": TDRC}
        changed = False
        for f, value in changes.items():
            cls = frames[f]
            if not tags.get(cls.__name__):
                tags.add(cls(encoding=3, text=str(value)))
                changed = True
        if changed:
            tags.save(path)
        return changed
    except Exception as e:
        logger.warning("Could not write tags to %s: %s", path.name, e)
        return False


# ── Audio analysis ────────────────────────────────────────────────────────────

def analysis_available() -> bool:
    try:
        import librosa  # noqa: F401

        return True
    except ImportError:
        return False


def start_analysis(force: bool = False) -> None:
    if analysis.running:
        return
    db = SessionLocal()
    try:
        done_ids = {f.media_id for f in db.query(AudioFeatures.media_id)}
        rows = [(m.id, m.filename) for m in db.query(Media).filter(Media.type == "music")
                if force or m.id not in done_ids]
    finally:
        db.close()
    analysis.__init__(running=True, total=len(rows), started_at=time.time())
    _spawn(_run_analysis(rows))


async def _run_analysis(rows: list[tuple[int, str]]) -> None:
    failed = 0
    try:
        for media_id, filename in rows:
            path = resolve_file(filename)
            features = None
            if path is not None:
                try:
                    features = await asyncio.to_thread(_analyze_file, str(path))
                except Exception as e:
                    failed += 1
                    logger.warning("Analysis failed for %s: %s", filename, e)
            if features:
                db = SessionLocal()
                try:
                    row = db.get(AudioFeatures, media_id) or AudioFeatures(media_id=media_id)
                    for k, v in features.items():
                        setattr(row, k, v)
                    row.analyzed_at = datetime.utcnow()
                    db.merge(row)
                    db.commit()
                finally:
                    db.close()
            analysis.done += 1
        if failed:
            analysis.error = f"{failed} archivo(s) no se pudieron analizar."
    except Exception as e:
        logger.exception("Analysis failed")
        analysis.error = str(e)
    finally:
        analysis.running = False
        analysis.finished_at = time.time()


def _analyze_file(path: str) -> dict:
    """BPM, energy, brightness and danceability from a 60 s excerpt of the song."""
    import librosa
    import numpy as np

    duration = float(librosa.get_duration(path=path))
    offset = 30.0 if duration > 100 else 0.0  # skip intros
    y, sr = librosa.load(path, sr=22050, mono=True, offset=offset, duration=60)
    if y.size < sr * 10:
        # The header's duration can be wrong (VBR or a truncated download): use what decodes
        y, sr = librosa.load(path, sr=22050, mono=True, duration=90)
        duration = min(duration, y.size / sr) if y.size else duration
    if y.size < sr * 5:
        raise ValueError("audio demasiado corto o dañado")

    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    tempo, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr)
    bpm = float(np.atleast_1d(tempo)[0])

    # Calibrated on real libraries: quiet ~-24 dBFS RMS, loud modern masters ~-6
    rms_db = 20 * np.log10(float(librosa.feature.rms(y=y)[0].mean()) + 1e-9)
    energy = float(np.clip((rms_db + 24) / 18, 0, 1))

    centroid = float(librosa.feature.spectral_centroid(y=y, sr=sr)[0].mean())
    brightness = float(np.clip((centroid - 900) / 2400, 0, 1))

    # Danceability ≈ how strongly the beat stands out (beat-synchronous onset
    # strength vs the average), favouring tempos people dance to (~90-145 BPM).
    # Beat regularity alone is ~0.95+ for almost all produced music, so it
    # doesn't tell songs apart.
    pulse = float(onset_env[beats].mean() / (onset_env.mean() + 1e-9)) if len(beats) else 1.0
    beat_strength = float(np.clip((pulse - 1.5) / 3.0, 0, 1))
    tempo_fit = 1 - min(abs(bpm - 118) / 60, 1) * 0.6
    danceability = 0.75 * beat_strength + 0.25 * tempo_fit

    return {"bpm": round(bpm, 1), "energy": round(energy, 3), "brightness": round(brightness, 3),
            "danceability": round(danceability, 3), "duration": round(duration, 1)}
