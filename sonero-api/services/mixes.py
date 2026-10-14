"""
Mixes (recommended playlists) for Biblioteca → Para ti.

* Storage helpers shared by the API and the MCP server (agents create mixes
  with source="agent").
* Sonero's own recommendation algorithm (source="auto"): scores the library
  from listening history, metadata and audio features, and discovers new
  songs through related artists when there's internet. No AI involved.
"""

import asyncio
import logging
import math
import random
from collections import Counter
from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from models import Mix, MixItem
from services import music_catalog
from services.library_data import LibrarySong, load_library, split_artists, taste_profile

logger = logging.getLogger("sonero.mixes")

MAX_ITEMS = 100
MIN_MIX_SIZE = 5


# ── Storage ───────────────────────────────────────────────────────────────────

def serialize(mix: Mix, songs_by_id: dict[int, LibrarySong] | None = None, with_items: bool = True) -> dict:
    data = {
        "id": mix.id,
        "title": mix.title,
        "description": mix.description,
        "reason": mix.reason,
        "source": mix.source,
        "author": mix.author,
        "kind": mix.kind,
        "created_at": mix.created_at.isoformat() + "Z" if mix.created_at else None,
        "updated_at": mix.updated_at.isoformat() + "Z" if mix.updated_at else None,
        "count": len(mix.items),
        "in_library": sum(1 for i in mix.items if i.media_id),
    }
    if with_items:
        songs_by_id = songs_by_id or {}
        items = []
        for i in mix.items:
            if i.media_id:
                s = songs_by_id.get(i.media_id)
                if s is None:  # file deleted since the mix was made
                    continue
                items.append({"id": i.id, "in_library": True, "media_id": s.media_id, "filename": s.filename,
                              "title": s.title, "artist": s.artist, "album": s.album, "note": i.note})
            else:
                items.append({"id": i.id, "in_library": False, "title": i.title, "artist": i.artist,
                              "album": i.album, "cover_url": i.cover_url, "preview_url": i.preview_url,
                              "external_id": i.external_id, "note": i.note})
        data["items"] = items
    return data


def _match_library(title: str, artist: str, songs: list[LibrarySong]) -> LibrarySong | None:
    """An online suggestion the user already owns becomes a library item."""
    best, best_score = None, 0.0
    for s in songs:
        t = music_catalog.similarity(title, s.title)
        if t < 0.85:
            continue
        a = music_catalog.similarity(artist, s.artist) if artist and s.artist else 0.7
        score = 0.6 * t + 0.4 * a
        if score > best_score:
            best, best_score = s, score
    return best if best_score >= 0.85 else None


def save_mix(db: Session, *, title: str, items: list[dict], description: str | None = None,
             reason: str | None = None, source: str = "auto", author: str | None = None,
             kind: str | None = None, songs: list[LibrarySong] | None = None,
             replace_id: int | None = None) -> Mix:
    """
    items: [{"media_id": 12} | {"filename": "x.mp3"} |
            {"title", "artist", "album"?, "preview_url"?, "cover_url"?, "external_id"?}] + optional "note".
    Duplicates are dropped; online songs already in the library are linked to the file.
    """
    songs = songs if songs is not None else load_library(db)
    by_id = {s.media_id: s for s in songs}
    by_file = {s.filename: s for s in songs} | {s.filename.rsplit("/", 1)[-1]: s for s in songs}

    mix = db.get(Mix, replace_id) if replace_id else None
    if mix is None:
        mix = Mix()
        db.add(mix)
    else:
        mix.items.clear()
    mix.title = title.strip()[:120] or "Mix"
    mix.description = (description or "").strip()[:1000] or None
    mix.reason = (reason or "").strip()[:1000] or None
    mix.source, mix.author, mix.kind = source, author, kind
    mix.updated_at = datetime.utcnow()

    seen: set[str] = set()
    for raw in items[:MAX_ITEMS]:
        song = None
        if raw.get("media_id") is not None:
            song = by_id.get(int(raw["media_id"]))
        elif raw.get("filename"):
            song = by_file.get(raw["filename"]) or by_file.get(str(raw["filename"]).rsplit("/", 1)[-1])
        elif raw.get("title"):
            song = _match_library(raw["title"], raw.get("artist") or "", songs)

        note = (raw.get("note") or "")[:200] or None
        if song is not None:
            key = f"m{song.media_id}"
            if key in seen:
                continue
            seen.add(key)
            mix.items.append(MixItem(position=len(mix.items), media_id=song.media_id, note=note))
        elif raw.get("title"):
            key = "o" + music_catalog.normalize(f"{raw.get('artist', '')} {raw['title']}")
            if key in seen:
                continue
            seen.add(key)
            mix.items.append(MixItem(
                position=len(mix.items), title=str(raw["title"])[:200], artist=(raw.get("artist") or "")[:200],
                album=(raw.get("album") or None), cover_url=raw.get("cover_url"),
                preview_url=raw.get("preview_url"), external_id=raw.get("external_id"), note=note,
            ))
    db.commit()
    db.refresh(mix)
    return mix


# ── Sonero's own algorithm ────────────────────────────────────────────────────

def _affinity(s: LibrarySong, now: datetime) -> float:
    """How much the listener likes a song: time spent, finishing it, not skipping, recency."""
    if not s.plays:
        return 0.0
    completion = s.completion_rate or 0.0
    skip = s.skip_rate or 0.0
    days = s.days_since_played(now) or 0.0
    recency = math.exp(-days / 30)  # a play last month counts ~1/3
    return (math.log1p(s.seconds / 60) + 0.5 * s.plays) * (0.5 + completion) * (1 - 0.7 * skip) * (0.6 + 0.4 * recency)


def _period_of(hour: int) -> str:
    return "mañana" if 6 <= hour < 12 else "tarde" if 12 <= hour < 19 else "noche"


async def generate_auto_mixes(db: Session) -> dict:
    """Rebuilds every source="auto" mix. Online parts are skipped without internet."""
    now = datetime.utcnow()
    rng = random.Random(now.strftime("%Y-%m-%d"))  # changes daily, stable within a day
    songs = load_library(db)
    if not songs:
        return {"created": 0, "online": False, "mixes": []}

    profile = taste_profile(songs)
    played = [s for s in songs if s.plays]
    by_affinity = sorted(played, key=lambda s: _affinity(s, now), reverse=True)
    lib_artists = {music_catalog.normalize(a) for s in songs if s.artist for a in split_artists(s.artist)}
    plans: list[dict] = []
    online = True

    def plan(kind, title, description, reason, items):
        if len(items) >= MIN_MIX_SIZE:
            plans.append({"kind": kind, "title": title, "description": description, "reason": reason, "items": items})

    lib = lambda ss, note=None: [{"media_id": s.media_id, "note": note} for s in ss]

    # 1. Daily mix: favourites + a few songs from the same artists you haven't played much
    if played:
        top = by_affinity[:18]
        fav_artists = {a for s in top[:8] for a in split_artists(s.artist)} if top else set()
        top_ids = {s.media_id for s in top}
        fresh = [s for s in songs if s.plays <= 1 and s.media_id not in top_ids
                 and any(a in fav_artists for a in split_artists(s.artist))]
        rng.shuffle(fresh)
        daily = top + fresh[:7]
        rng.shuffle(daily)
        plan("daily_mix", "Tu mix diario", "Tus canciones de siempre y algunas de los mismos artistas que casi no escuchas.",
             "Basado en cuánto escuchas cada canción, si la terminas o la saltas, y qué tan reciente fue.", lib(daily))
    else:
        recent = sorted(songs, key=lambda s: s.added_at or now, reverse=True)[:25]
        plan("daily_mix", "Tu mix diario", "Aún no hay historial: una selección de tu biblioteca para empezar.",
             "Sin historial de escucha todavía; mejora a medida que uses Sonero.", lib(recent))

    # 2. Favourites
    plan("favorites", "Tus favoritas", "Lo que más escuchas y terminas, sin las que sueles saltar.",
         "Canciones con más tiempo de escucha y mayor porcentaje terminado.",
         lib([s for s in by_affinity if s.plays >= 2 and (s.skip_rate or 0) < 0.5][:30]))

    # 3. Rediscover: liked once, not heard lately
    stale = [s for s in played if (s.days_since_played(now) or 0) >= 14 and (s.completion_rate or 0) >= 0.5]
    plan("rediscover", "Redescubre", "Canciones que te gustaron y llevas tiempo sin escuchar.",
         "Las terminaste en su momento y no suenan desde hace más de dos semanas.",
         lib(sorted(stale, key=lambda s: _affinity(s, now), reverse=True)[:25]))

    # 4. Never played
    unplayed = [s for s in songs if not s.plays]
    rng.shuffle(unplayed)
    plan("unplayed", "Nunca escuchadas", "Están en tu biblioteca pero nunca les diste play.",
         f"{len(unplayed)} canciones de tu biblioteca sin reproducciones.", lib(unplayed[:25]))

    # 5. Recently added
    recent = [s for s in songs if s.added_at and (now - s.added_at).days <= 30]
    plan("recent", "Recién añadidas", "Lo último que agregaste a tu biblioteca.",
         "Añadidas en los últimos 30 días.", lib(sorted(recent, key=lambda s: s.added_at, reverse=True)[:30]))

    # 6. Time of day, from when you actually play each song
    by_period: dict[str, Counter] = {"mañana": Counter(), "tarde": Counter(), "noche": Counter()}
    for s in played:
        for hour, n in s.hours.items():
            by_period[_period_of(hour)][s.media_id] += n
    ids = {s.media_id: s for s in songs}
    for period, counter in by_period.items():
        chosen = [ids[i] for i, _ in counter.most_common(25)]
        plan(f"time_{period}", f"Para la {period}" if period != "tarde" else "Para la tarde",
             f"Lo que sueles escuchar por la {period}.",
             f"Canciones que reproduces con más frecuencia por la {period}.", lib(chosen))

    # 7. Energy and calm, from the local audio analysis
    analyzed = [s for s in songs if s.energy is not None and s.bpm]
    if analyzed:
        high = sorted([s for s in analyzed if s.energy >= 0.65 and s.bpm >= 105],
                      key=lambda s: s.energy * 0.6 + (s.danceability or 0) * 0.4, reverse=True)
        plan("energy", "Alta energía", "Fuerte y con ritmo: para entrenar o despertarte.",
             "Mayor energía y BPM según el análisis de audio.", lib(high[:30]))
        calm = sorted([s for s in analyzed if s.energy <= 0.5 or s.bpm < 90], key=lambda s: s.energy)
        plan("calm", "Modo calma", "Suave y tranquila: para concentrarte o descansar.",
             "Menor energía y tempo según el análisis de audio.", lib(calm[:30]))

    # 8. Genres (after "Completar metadatos")
    genre_of = {s.media_id: music_catalog.canonical_genre(s.genre) for s in songs if s.genre}
    genre_counts = Counter(genre_of.values())
    for genre, n in genre_counts.most_common(3):
        if n >= 8:
            chosen = sorted([s for s in songs if genre_of.get(s.media_id) == genre],
                            key=lambda s: _affinity(s, now), reverse=True)
            plan(f"genre:{genre}", f"Lo mejor de {genre}", f"Tu {genre}, empezando por lo que más escuchas.",
                 f"{n} canciones de tu biblioteca con género {genre}.", lib(chosen[:30]))

    # 9. Online: artist radios and weekly discovery through related artists
    seeds = profile["top_artists"][:3] or profile["library_artists"][:3]
    try:
        async def top_of(name: str, n: int) -> list[dict]:
            return (await music_catalog.artist_top_tracks(name, limit=n))[:n]

        related_by_seed = dict(zip(seeds, await asyncio.gather(
            *(music_catalog.related_artists(a, limit=8) for a in seeds))))

        for artist in seeds[:2]:
            found = await music_catalog.find_artist(artist)
            name = found["name"] if found else artist  # official spelling for the title
            related = related_by_seed[artist][:5]
            own = [s for s in songs if any(music_catalog.similarity(artist, a) >= 0.9 for a in split_artists(s.artist))]
            items = lib(sorted(own, key=lambda s: _affinity(s, now), reverse=True)[:10], note=f"De {name}")
            for tracks in await asyncio.gather(*(top_of(r["name"], 2) for r in related)):
                items += [{**t, "note": f"Similar a {name}"} for t in tracks]
            rng.shuffle(items)
            plan(f"radio:{name}", f"Radio de {name}", f"{name} y artistas parecidos.",
                 f"Tus canciones de {name} mezcladas con lo más popular de artistas similares.", items)

        new_artists: dict[str, str] = {}  # related artist -> seed that led to it
        for seed, related in related_by_seed.items():
            for r in related:
                if music_catalog.normalize(r["name"]) not in lib_artists:  # already yours: not a discovery
                    new_artists.setdefault(r["name"], seed)
        discovery: list[dict] = []
        names = list(new_artists)[:12]
        for name, tracks in zip(names, await asyncio.gather(*(top_of(n, 2) for n in names))):
            discovery += [{**t, "note": f"Porque escuchas {new_artists[name]}"} for t in tracks]
        rng.shuffle(discovery)
        plan("discovery", "Descubrimiento semanal", "Artistas que no tienes en tu biblioteca y probablemente te gusten.",
             "Artistas relacionados con los que más escuchas, que todavía no están en tu biblioteca.", discovery[:25])
    except music_catalog.CatalogUnavailable as e:
        online = False
        logger.info("Discovery skipped (offline): %s", e)

    # Replace previous automatic mixes
    for old in db.query(Mix).filter(Mix.source == "auto"):
        db.delete(old)
    db.commit()
    created = [save_mix(db, source="auto", songs=songs, **p) for p in plans]
    return {"created": len(created), "online": online, "mixes": [m.title for m in created]}
