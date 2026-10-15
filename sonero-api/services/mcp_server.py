"""
MCP server exposing Sonero's usage statistics to AI agents.

All tools are read-only: agents can query the library and listening
statistics but cannot play, download, edit or delete anything.

Transports:
  * Streamable HTTP at http://127.0.0.1:8000/mcp, mounted in the main API
    (see main.py). Local-only, with DNS-rebinding protection and an optional
    bearer token (MCP_TOKEN in .env).
  * stdio, for clients that launch the server themselves: `python mcp_stdio.py`.
"""

from collections import Counter, defaultdict
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Iterator, Literal

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from config import settings
from database import SessionLocal
from models import FocusSession, ListeningHistory, Media, PlaybackEvent, Playlist

READ_ONLY = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False)
# Queries public music catalogs on the internet
ONLINE = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=True)
# Writes only to Sonero's mixes (never touches music files)
WRITES_MIXES = ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False, openWorldHint=False)
WEEKDAYS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

mcp = MCPServer(
    name="sonero",
    title="Sonero",
    description="Estadísticas de uso de Sonero y creación de playlists recomendadas (mixes).",
    instructions=(
        "Sonero es un reproductor de música. Estas herramientas te dan su biblioteca, el historial de "
        "escucha y búsqueda en catálogos públicos, para que crees playlists recomendadas (mixes) que el "
        "usuario verá en Biblioteca → Para ti.\n"
        "Flujo sugerido: get_taste_profile → list_library_songs → find_similar_artists / "
        "get_artist_top_tracks / search_music_catalog para descubrir música nueva → create_mix (varias "
        "veces, con títulos y razones claras). Mezcla canciones de la biblioteca (media_id) con "
        "descubrimientos online (title + artist + preview_url de los resultados del catálogo).\n"
        "El usuario valora las canciones de los mixes (me gusta / me da igual / no me gusta): consulta "
        "get_song_ratings antes de crear mixes, usa lo que le gusta como semilla y evita los artistas y estilos "
        "que rechaza. create_mix descarta solo las canciones con 'no me gusta'.\n"
        "Las estadísticas y el historial son de solo lectura; create_mix y delete_mix solo afectan a los "
        "mixes, nunca a los archivos de música. Los periodos se indican en días hacia atrás desde ahora. "
        "Las horas y días de la semana están en la zona horaria local de la computadora donde corre Sonero."
    ),
    version="1.2.0",
)


# ── Helpers ───────────────────────────────────────────────────────────────────

@contextmanager
def _db() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _since(days: int | None) -> datetime | None:
    """UTC cutoff (timestamps are stored as naive UTC)."""
    if days is None or days <= 0:
        return None
    return datetime.utcnow() - timedelta(days=days)


def _local(ts: datetime) -> datetime:
    return ts.replace(tzinfo=timezone.utc).astimezone()


def _iso(ts: datetime | None) -> str | None:
    return _local(ts).isoformat(timespec="seconds") if ts else None


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


def _events(db: Session, days: int | None):
    q = db.query(PlaybackEvent, Media).join(Media, PlaybackEvent.media_id == Media.id)
    cutoff = _since(days)
    if cutoff is not None:
        q = q.filter(PlaybackEvent.start_time >= cutoff)
    return q


def _media_dict(m: Media) -> dict:
    return {
        "id": m.id,
        "title": m.title,
        "artist": m.artist or None,
        "album": m.album or None,
        "genre": m.genre or None,
        "year": m.year or None,
        "type": m.type,
        "format": m.format,
        "filename": m.filename,
        "added_at": _iso(m.added_at),
    }


def _period(days: int | None) -> dict:
    return {"days": days if days and days > 0 else None, "timezone": str(datetime.now().astimezone().tzinfo)}


# ── Tools ─────────────────────────────────────────────────────────────────────

@mcp.tool(annotations=READ_ONLY)
def get_listening_summary(days: int = 30) -> dict:
    """
    Resumen de hábitos de escucha en los últimos `days` días (0 = todo el historial):
    reproducciones, minutos escuchados, tasa de canciones terminadas, canciones y
    artistas distintos, hora y día de la semana con más escucha, y racha de días.
    """
    with _db() as db:
        rows = _events(db, days).all()

    total_seconds = sum(e.duration_watched or 0 for e, _ in rows)
    completed = sum(1 for e, _ in rows if e.completed)
    by_hour: Counter = Counter()
    by_weekday: Counter = Counter()
    active_days = set()
    for e, _ in rows:
        local = _local(e.start_time)
        by_hour[local.hour] += e.duration_watched or 0
        by_weekday[local.weekday()] += e.duration_watched or 0
        active_days.add(local.date())

    # Consecutive days with listening, ending today or yesterday
    streak = 0
    day = datetime.now().astimezone().date()
    if day not in active_days:
        day -= timedelta(days=1)
    while day in active_days:
        streak += 1
        day -= timedelta(days=1)

    span_days = days if days and days > 0 else max(len(active_days), 1)
    return {
        "period": _period(days),
        "plays": len(rows),
        "completed_plays": completed,
        "completion_rate": round(completed / len(rows), 3) if rows else None,
        "minutes_listened": round(total_seconds / 60, 1),
        "avg_minutes_per_day": round(total_seconds / 60 / span_days, 1),
        "unique_tracks": len({m.id for _, m in rows}),
        "unique_artists": len({m.artist for _, m in rows if m.artist}),
        "active_days": len(active_days),
        "current_streak_days": streak,
        "peak_hour": by_hour.most_common(1)[0][0] if by_hour else None,
        "peak_weekday": WEEKDAYS[by_weekday.most_common(1)[0][0]] if by_weekday else None,
    }


@mcp.tool(annotations=READ_ONLY)
def get_top_tracks(days: int = 30, limit: int = 10, order_by: Literal["plays", "minutes"] = "plays") -> dict:
    """Canciones/videos más escuchados en los últimos `days` días (0 = todo), por reproducciones o minutos."""
    limit = _clamp(limit, 1, 100)
    with _db() as db:
        stats: dict[int, dict] = {}
        for e, m in _events(db, days):
            s = stats.setdefault(m.id, {"media": m, "plays": 0, "seconds": 0.0, "completed": 0, "last": e.start_time})
            s["plays"] += 1
            s["seconds"] += e.duration_watched or 0
            s["completed"] += 1 if e.completed else 0
            s["last"] = max(s["last"], e.start_time)

        key = (lambda s: s["seconds"]) if order_by == "minutes" else (lambda s: (s["plays"], s["seconds"]))
        top = sorted(stats.values(), key=key, reverse=True)[:limit]
        return {
            "period": _period(days),
            "order_by": order_by,
            "tracks": [
                {
                    **_media_dict(s["media"]),
                    "plays": s["plays"],
                    "minutes": round(s["seconds"] / 60, 1),
                    "completion_rate": round(s["completed"] / s["plays"], 3),
                    "last_played": _iso(s["last"]),
                }
                for s in top
            ],
        }


@mcp.tool(annotations=READ_ONLY)
def get_top_artists(days: int = 30, limit: int = 10) -> dict:
    """Artistas más escuchados en los últimos `days` días (0 = todo), con reproducciones, minutos y canciones distintas."""
    limit = _clamp(limit, 1, 100)
    with _db() as db:
        stats: dict[str, dict] = defaultdict(lambda: {"plays": 0, "seconds": 0.0, "tracks": set()})
        for e, m in _events(db, days):
            artist = (m.artist or "").strip() or "Desconocido"
            stats[artist]["plays"] += 1
            stats[artist]["seconds"] += e.duration_watched or 0
            stats[artist]["tracks"].add(m.id)

    top = sorted(stats.items(), key=lambda kv: (kv[1]["plays"], kv[1]["seconds"]), reverse=True)[:limit]
    return {
        "period": _period(days),
        "artists": [
            {"artist": a, "plays": s["plays"], "minutes": round(s["seconds"] / 60, 1), "unique_tracks": len(s["tracks"])}
            for a, s in top
        ],
    }


@mcp.tool(annotations=READ_ONLY)
def get_top_genres(days: int = 30, limit: int = 10) -> dict:
    """Géneros más escuchados en los últimos `days` días (0 = todo). Solo cuenta medios con género en sus metadatos."""
    limit = _clamp(limit, 1, 50)
    with _db() as db:
        stats: dict[str, dict] = defaultdict(lambda: {"plays": 0, "seconds": 0.0})
        untagged = 0
        for e, m in _events(db, days):
            genre = (m.genre or "").strip()
            if not genre:
                untagged += 1
                continue
            stats[genre]["plays"] += 1
            stats[genre]["seconds"] += e.duration_watched or 0

    top = sorted(stats.items(), key=lambda kv: kv[1]["plays"], reverse=True)[:limit]
    return {
        "period": _period(days),
        "genres": [{"genre": g, "plays": s["plays"], "minutes": round(s["seconds"] / 60, 1)} for g, s in top],
        "plays_without_genre": untagged,
    }


@mcp.tool(annotations=READ_ONLY)
def get_listening_timeline(days: int = 30, group_by: Literal["day", "hour", "weekday"] = "day") -> dict:
    """
    Distribución de la escucha en los últimos `days` días: por fecha (`day`),
    por hora del día 0-23 (`hour`) o por día de la semana (`weekday`), en hora local.
    """
    days = days if days and days > 0 else 30
    with _db() as db:
        rows = [(e.start_time, e.duration_watched or 0) for e, _ in _events(db, days)]

    buckets: dict = defaultdict(lambda: {"plays": 0, "seconds": 0.0})
    for ts, secs in rows:
        local = _local(ts)
        key = local.date().isoformat() if group_by == "day" else local.hour if group_by == "hour" else local.weekday()
        buckets[key]["plays"] += 1
        buckets[key]["seconds"] += secs

    if group_by == "day":
        today = datetime.now().astimezone().date()
        keys = [(today - timedelta(days=i)).isoformat() for i in range(days - 1, -1, -1)]
        label = lambda k: k
    elif group_by == "hour":
        keys, label = list(range(24)), (lambda k: f"{k:02d}:00")
    else:
        keys, label = list(range(7)), (lambda k: WEEKDAYS[k])

    return {
        "period": _period(days),
        "group_by": group_by,
        "series": [
            {"bucket": label(k), "plays": buckets[k]["plays"], "minutes": round(buckets[k]["seconds"] / 60, 1)}
            for k in keys
        ],
    }


@mcp.tool(annotations=READ_ONLY)
def get_playback_history(limit: int = 50, days: int = 0) -> dict:
    """Últimas reproducciones (más recientes primero), con duración escuchada y si se terminó."""
    limit = _clamp(limit, 1, 500)
    with _db() as db:
        rows = _events(db, days).order_by(PlaybackEvent.start_time.desc()).limit(limit).all()
        return {
            "period": _period(days),
            "events": [
                {
                    "played_at": _iso(e.start_time),
                    "seconds_listened": round(e.duration_watched or 0, 1),
                    "completed": bool(e.completed),
                    "title": m.title,
                    "artist": m.artist or None,
                    "type": m.type,
                    "media_id": m.id,
                }
                for e, m in rows
            ],
        }


@mcp.tool(annotations=READ_ONLY)
def get_library_overview() -> dict:
    """Tamaño y composición de la biblioteca: canciones, videos, playlists, formatos, artistas/géneros con más archivos y añadidos recientes."""
    with _db() as db:
        now = datetime.utcnow()
        count = lambda *f: db.query(func.count(Media.id)).filter(*f).scalar() or 0

        def top(col, n=10):
            return [
                {"name": name, "count": c}
                for name, c in db.query(col, func.count(Media.id))
                .filter(col.isnot(None), col != "")
                .group_by(col).order_by(func.count(Media.id).desc()).limit(n)
            ]

        never_played = (
            db.query(func.count(Media.id))
            .filter(~Media.id.in_(db.query(PlaybackEvent.media_id).distinct()))
            .scalar() or 0
        )
        folder_playlists = (
            sorted(d.name for d in settings.MUSIC_DIR.iterdir()
                   if d.is_dir() and not d.name.startswith(".") and d.resolve() != settings.VIDEO_DIR.resolve())
            if settings.MUSIC_DIR.exists() else []
        )
        return {
            "songs": count(Media.type == "music"),
            "videos": count(Media.type == "video"),
            "total": count(),
            "never_played": never_played,
            "added_last_7_days": count(Media.added_at >= now - timedelta(days=7)),
            "added_last_30_days": count(Media.added_at >= now - timedelta(days=30)),
            "playlists": folder_playlists,
            "smart_playlists": [p.name for p in db.query(Playlist).filter(Playlist.is_smart.is_(True))],
            "formats": top(Media.format),
            "top_artists_by_files": top(Media.artist),
            "top_genres_by_files": top(Media.genre),
        }


@mcp.tool(annotations=READ_ONLY)
def search_library(query: str, limit: int = 20) -> dict:
    """Busca en la biblioteca por título, artista, álbum o género (sin distinguir mayúsculas). Incluye cuántas veces se reprodujo cada resultado."""
    limit = _clamp(limit, 1, 100)
    pattern = f"%{query.strip()}%"
    with _db() as db:
        plays = dict(db.query(PlaybackEvent.media_id, func.count(PlaybackEvent.id)).group_by(PlaybackEvent.media_id))
        results = (
            db.query(Media)
            .filter(or_(Media.title.ilike(pattern), Media.artist.ilike(pattern),
                        Media.album.ilike(pattern), Media.genre.ilike(pattern)))
            .order_by(Media.title)
            .limit(limit)
            .all()
        )
        return {"query": query, "results": [{**_media_dict(m), "plays": plays.get(m.id, 0)} for m in results]}


@mcp.tool(annotations=READ_ONLY)
def get_focus_stats(days: int = 30) -> dict:
    """
    Sesiones de concentración (modo Focus) y saltos de canciones en los últimos `days` días:
    número de sesiones, duración, saltos y puntuación de concentración (Focus Score).
    """
    cutoff = _since(days)
    with _db() as db:
        q = db.query(FocusSession)
        h = db.query(ListeningHistory)
        if cutoff is not None:
            q = q.filter(FocusSession.started_at >= cutoff)
            h = h.filter(ListeningHistory.listened_at >= cutoff)
        sessions = q.order_by(FocusSession.started_at.desc()).all()
        history = h.all()

    finished = [s for s in sessions if s.ended_at]
    minutes = [(s.ended_at - s.started_at).total_seconds() / 60 for s in finished]
    scores = [s.focus_score for s in sessions if s.focus_score is not None]
    skipped = sum(1 for x in history if x.skipped)
    return {
        "period": _period(days),
        "sessions": len(sessions),
        "finished_sessions": len(finished),
        "total_focus_minutes": round(sum(minutes), 1),
        "avg_session_minutes": round(sum(minutes) / len(minutes), 1) if minutes else None,
        "avg_focus_score": round(sum(scores) / len(scores), 3) if scores else None,
        "skips_in_sessions": sum(s.total_skips or 0 for s in sessions),
        "tracks_logged": len(history),
        "skip_rate": round(skipped / len(history), 3) if history else None,
        "recent_sessions": [
            {
                "started_at": _iso(s.started_at),
                "ended_at": _iso(s.ended_at),
                "skips": s.total_skips or 0,
                "focus_score": s.focus_score,
            }
            for s in sessions[:10]
        ],
    }


@mcp.tool(annotations=READ_ONLY)
async def get_dashboard_stats() -> dict:
    """
    Las mismas estadísticas completas que muestra la pantalla de Estadísticas de la app
    (biblioteca, tiempo de escucha, patrones, ánimo y tendencias). Respuesta extensa:
    prefiere las herramientas específicas si solo necesitas una parte.
    """
    from routers.analytics import get_advanced_stats

    with _db() as db:
        return await get_advanced_stats(db=db)


# ── Recommendations: library, discovery and mixes ─────────────────────────────

from models import Mix, SongRating  # noqa: E402
from services import mixes as mix_service, music_catalog  # noqa: E402
from services.library_data import load_library, split_artists, taste_profile  # noqa: E402


def _catalog_error(e: Exception) -> dict:
    return {"error": "Catálogo no disponible (¿hay internet en la computadora de Sonero?)", "detail": str(e)}


@mcp.tool(annotations=READ_ONLY)
def get_taste_profile() -> dict:
    """
    Perfil musical del usuario: artistas y géneros que más escucha (ponderado por tiempo),
    artistas con más canciones en la biblioteca, promedios de audio (BPM, energía) de lo que
    escucha, en qué momentos del día escucha, y cuánta información hay disponible.
    Úsalo primero para decidir qué mixes crear.
    """
    with _db() as db:
        songs = load_library(db)
        ratings = list(mix_service.load_ratings(db).values())
    played = [s for s in songs if s.plays]

    def weighted(attr: str) -> float | None:
        rows = [(getattr(s, attr), s.seconds) for s in played if getattr(s, attr) is not None]
        total = sum(w for _, w in rows)
        return round(sum(v * w for v, w in rows) / total, 2) if total else None

    periods: Counter = Counter()
    for s in played:
        for hour, n in s.hours.items():
            periods["mañana" if 6 <= hour < 12 else "tarde" if 12 <= hour < 19 else "noche"] += n
    return {
        **taste_profile(songs),
        "listening_by_period": dict(periods),
        "avg_bpm_listened": weighted("bpm"),
        "avg_energy_listened": weighted("energy"),
        "data_coverage": {
            "songs": len(songs),
            "with_artist": sum(1 for s in songs if s.artist),
            "with_genre": sum(1 for s in songs if s.genre),
            "with_year": sum(1 for s in songs if s.year),
            "with_audio_analysis": sum(1 for s in songs if s.bpm),
            "played_songs": len(played),
            "total_plays": sum(s.plays for s in songs),
        },
        "ratings": {label: sum(1 for r in ratings if r == value)
                    for label, value in (("liked", 1), ("meh", 0), ("disliked", -1))},
        "hint": "Si faltan género/año o análisis de audio, sugiere al usuario 'Completar metadatos' y "
                "'Analizar audio' en Biblioteca → Para ti.",
    }


@mcp.tool(annotations=READ_ONLY)
def list_library_songs(
    sort_by: Literal["affinity", "plays", "minutes", "recently_played", "recently_added", "title"] = "affinity",
    limit: int = 150,
    artist: str | None = None,
    genre: str | None = None,
    min_bpm: float | None = None,
    max_bpm: float | None = None,
    min_energy: float | None = None,
    max_energy: float | None = None,
    only_unplayed: bool = False,
) -> dict:
    """
    Canciones de la biblioteca con sus metadatos, uso (reproducciones, minutos, % terminado,
    % saltada, última vez, horas favoritas) y análisis de audio (bpm, energy 0-1, brightness 0-1,
    danceability 0-1; null si no se ha analizado) y rating (1 me gusta, 0 me da igual, -1 no me gusta,
    null sin valorar). Usa media_id para incluirlas en create_mix.
    'affinity' ordena por cuánto le gusta al usuario (valoración, tiempo, terminadas, sin saltos, recencia).
    """
    limit = _clamp(limit, 1, 500)
    now = datetime.utcnow()
    with _db() as db:
        songs = load_library(db)

    def keep(s) -> bool:
        if artist and music_catalog.similarity(artist, s.artist) < 0.8 and artist.lower() not in s.artist.lower():
            return False
        if genre and music_catalog.similarity(genre, s.genre) < 0.8:
            return False
        if only_unplayed and s.plays:
            return False
        for value, lo, hi in ((s.bpm, min_bpm, max_bpm), (s.energy, min_energy, max_energy)):
            if (lo is not None or hi is not None) and value is None:
                return False
            if (lo is not None and value < lo) or (hi is not None and value > hi):
                return False
        return True

    keys = {
        "affinity": lambda s: mix_service._affinity(s, now),
        "plays": lambda s: s.plays,
        "minutes": lambda s: s.seconds,
        "recently_played": lambda s: s.last_played or datetime.min,
        "recently_added": lambda s: s.added_at or datetime.min,
        "title": lambda s: s.title.lower(),
    }
    chosen = sorted(filter(keep, songs), key=keys[sort_by], reverse=sort_by != "title")
    return {"total_matching": len(chosen), "songs": [s.to_dict() for s in chosen[:limit]]}


def _mark_owned(tracks: list[dict]) -> list[dict]:
    with _db() as db:
        songs = load_library(db)
    out = []
    for t in tracks:
        owned = mix_service._match_library(t["title"], t["artist"], songs)
        out.append({**t, "in_library": owned is not None, "media_id": owned.media_id if owned else None})
    return out


@mcp.tool(annotations=ONLINE)
async def find_similar_artists(artist: str, limit: int = 10) -> dict:
    """Artistas similares a `artist` según Deezer, marcando cuáles ya están en la biblioteca."""
    try:
        related = await music_catalog.related_artists(artist, limit=_clamp(limit, 1, 25))
    except music_catalog.CatalogUnavailable as e:
        return _catalog_error(e)
    with _db() as db:
        own = {music_catalog.normalize(s.artist) for s in load_library(db) if s.artist}
    return {"artist": artist, "similar": [
        {**r, "in_library": any(music_catalog.normalize(r["name"]) in o for o in own)} for r in related]}


@mcp.tool(annotations=ONLINE)
async def get_artist_top_tracks(artist: str, limit: int = 10) -> dict:
    """
    Canciones más populares de un artista (Deezer), con preview_url de 30 s y portada.
    Las que el usuario ya tiene vienen con in_library=true y su media_id.
    """
    try:
        tracks = await music_catalog.artist_top_tracks(artist, limit=_clamp(limit, 1, 25))
    except music_catalog.CatalogUnavailable as e:
        return _catalog_error(e)
    return {"artist": artist, "tracks": _mark_owned(tracks)}


@mcp.tool(annotations=ONLINE)
async def search_music_catalog(query: str, limit: int = 10) -> dict:
    """
    Busca canciones en el catálogo de Deezer. Admite filtros: artist:"Nombre" track:"Título"
    album:"Álbum". Devuelve preview_url de 30 s, portada y si ya está en la biblioteca.
    """
    try:
        tracks = await music_catalog.search_tracks(query, limit=_clamp(limit, 1, 25))
    except music_catalog.CatalogUnavailable as e:
        return _catalog_error(e)
    return {"query": query, "tracks": _mark_owned(tracks)}


@mcp.tool(annotations=ONLINE)
async def get_genre_chart(genre: str, limit: int = 20) -> dict:
    """Éxitos actuales de un género en Deezer (p. ej. "Rap/Hip Hop", "Reggaeton", "Rock", "Pop", "R&B")."""
    try:
        tracks = await music_catalog.genre_chart(genre, limit=_clamp(limit, 1, 50))
    except music_catalog.CatalogUnavailable as e:
        return _catalog_error(e)
    if not tracks:
        return {"genre": genre, "tracks": [], "note": "Género no encontrado en Deezer."}
    return {"genre": genre, "tracks": _mark_owned(tracks)}


@mcp.tool(annotations=READ_ONLY)
def list_mixes(include_songs: bool = False) -> dict:
    """Mixes existentes: los automáticos de Sonero (source=auto) y los creados por agentes (source=agent)."""
    with _db() as db:
        songs = {s.media_id: s for s in load_library(db)} if include_songs else None
        rows = db.query(Mix).order_by(Mix.updated_at.desc()).all()
        return {"mixes": [mix_service.serialize(m, songs, with_items=include_songs) for m in rows]}


@mcp.tool(annotations=READ_ONLY)
def get_song_ratings() -> dict:
    """
    Lo que el usuario dijo de las canciones de los mixes: me gusta (1), me da igual (0) o
    no me gusta (-1), con el mix desde el que valoró, y un resumen por artista.
    Úsalo para refinar: repite y expande lo que le gusta, evita lo que no le gusta, y no insistas
    con lo que le da igual. Las canciones con "no me gusta" se descartan solas en create_mix.
    """
    with _db() as db:
        rows = db.query(SongRating).order_by(SongRating.updated_at.desc()).all()
        data = [{
            "rating": r.rating,
            "title": r.title,
            "artist": r.artist or None,
            "in_library": r.media_id is not None,
            "media_id": r.media_id,
            "external_id": r.external_id,
            "rated_in_mix": r.mix_title,
            "rated_at": _iso(r.updated_at),
        } for r in rows]

    labels = {1: "liked", 0: "meh", -1: "disliked"}
    by_artist: dict[str, Counter] = {}
    for r in data:
        for a in split_artists(r["artist"] or ""):
            by_artist.setdefault(a, Counter())[labels[r["rating"]]] += 1
    return {
        "counts": {label: sum(1 for r in data if r["rating"] == value) for value, label in labels.items()},
        "liked": [r for r in data if r["rating"] == 1],
        "meh": [r for r in data if r["rating"] == 0],
        "disliked": [r for r in data if r["rating"] == -1],
        "by_artist": {a: dict(c) for a, c in sorted(by_artist.items(), key=lambda kv: -sum(kv[1].values()))},
        "hint": None if data else "Aún no hay valoraciones: el usuario puede valorar canciones dentro de cada mix.",
    }


@mcp.tool(annotations=WRITES_MIXES)
def create_mix(
    title: str,
    songs: list[dict],
    description: str = "",
    reason: str = "",
    author: str = "Agente IA",
    replace_mix_id: int | None = None,
) -> dict:
    """
    Crea (o reemplaza, con replace_mix_id) un mix que el usuario verá en Biblioteca → Para ti.

    songs: lista ordenada (máx. 100) donde cada elemento es
      - una canción de la biblioteca: {"media_id": 12, "note": "opcional"}
      - o una canción online: {"title": "...", "artist": "...", "preview_url": "...",
        "cover_url": "...", "album": "...", "external_id": "...", "note": "opcional"}
        (copia esos campos de get_artist_top_tracks / search_music_catalog).
    Las canciones online que el usuario ya tiene se enlazan solas con su archivo, y las que
    marcó con "no me gusta" se descartan (ver get_song_ratings).
    description: una frase para la tarjeta. reason: por qué se la recomiendas, en base a sus datos.
    author: tu nombre como agente (p. ej. "Claude"); se muestra en la app.
    """
    if not songs:
        return {"error": "El mix necesita al menos una canción."}
    with _db() as db:
        if replace_mix_id is not None:
            old = db.get(Mix, replace_mix_id)
            if old is None or old.source != "agent":
                return {"error": "Solo puedes reemplazar mixes creados por agentes (source=agent)."}
        mix = mix_service.save_mix(db, title=title, items=songs, description=description, reason=reason,
                                   source="agent", author=(author or "Agente IA")[:60], kind="agent",
                                   replace_id=replace_mix_id)
        if not mix.items:
            db.delete(mix)
            db.commit()
            return {"error": "Ninguna canción era válida (revisa media_id o title/artist)."}
        data = mix_service.serialize(mix, with_items=False)
    skipped = len(songs) - data["count"]
    return {"created": data, "message": f"Mix '{data['title']}' guardado con {data['count']} canciones "
                                        f"({data['in_library']} de la biblioteca)."
                                        + (f" Se omitieron {skipped} (repetidas, no válidas o con 'no me gusta')."
                                           if skipped > 0 else "")}


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=True, idempotentHint=True,
                                      openWorldHint=False))
def delete_mix(mix_id: int) -> dict:
    """Borra un mix creado por un agente (los archivos de música no se tocan)."""
    with _db() as db:
        mix = db.get(Mix, mix_id)
        if mix is None:
            return {"error": "Mix no encontrado."}
        if mix.source != "agent":
            return {"error": "Solo se pueden borrar mixes de agentes; los automáticos se regeneran solos."}
        db.delete(mix)
        db.commit()
    return {"deleted": mix_id}


@mcp.prompt(title="Crear mis mixes recomendados")
def recommend_mixes(how_many: int = 4) -> str:
    """Pide al agente que analice tus datos y cree varios mixes al estilo Spotify/YouTube."""
    return (
        f"Analiza mis datos de Sonero y crea {how_many} mixes recomendados, como los de Spotify o YouTube Music.\n"
        "1. Llama a get_taste_profile y list_library_songs (sort_by=affinity) para entender mis gustos, "
        "cuándo escucho y qué salto, y get_song_ratings para ver qué me gustó y qué no de mixes anteriores.\n"
        "2. Usa find_similar_artists y get_artist_top_tracks para descubrir música que no tengo.\n"
        "3. Crea mixes variados con create_mix: por ejemplo uno de favoritas, uno de descubrimiento, uno según "
        "el momento del día o la energía, y uno sorpresa. Cada mix de 15 a 30 canciones, mezclando mi biblioteca "
        "con descubrimientos, con un título atractivo, una descripción corta y una razón basada en mis datos.\n"
        "4. Al final resume qué creaste y por qué."
    )


# ── Resource ──────────────────────────────────────────────────────────────────

@mcp.resource(
    "sonero://stats/summary",
    name="listening-summary",
    title="Resumen de escucha (30 días)",
    description="Resumen de los últimos 30 días, listo para dar contexto a un agente.",
    mime_type="application/json",
)
def summary_resource() -> dict:
    return {"listening": get_listening_summary(30), "library": get_library_overview()}


# ── HTTP mounting ─────────────────────────────────────────────────────────────

def build_http_route():
    """
    Starlette route serving the MCP Streamable HTTP endpoint at /mcp.

    The caller must run `mcp.session_manager.run()` in the app lifespan.
    Only local clients are accepted: the Host/Origin checks block DNS-rebinding
    attacks from web pages, and MCP_TOKEN (if set) requires
    `Authorization: Bearer <token>`.
    """
    import hmac

    from mcp.server.transport_security import TransportSecuritySettings
    from starlette.responses import JSONResponse
    from starlette.routing import Route

    local_hosts = ["127.0.0.1", "localhost", "[::1]"]
    starlette_app = mcp.streamable_http_app(
        stateless_http=True,
        json_response=True,
        transport_security=TransportSecuritySettings(
            enable_dns_rebinding_protection=True,
            allowed_hosts=[f"{h}:*" for h in local_hosts] + local_hosts,
            allowed_origins=[f"http://{h}:*" for h in local_hosts],
        ),
    )
    mcp_asgi = next(r.endpoint for r in starlette_app.routes if getattr(r, "path", None) == "/mcp")

    class _TokenGuard:
        # A class instance (not a function) so Starlette treats it as a raw ASGI app
        async def __call__(self, scope, receive, send):
            token = settings.MCP_TOKEN
            if token:
                headers = dict(scope.get("headers") or [])
                supplied = headers.get(b"authorization", b"").decode("latin-1")
                if not hmac.compare_digest(supplied.encode(), f"Bearer {token}".encode()):
                    await JSONResponse({"error": "unauthorized"}, status_code=401)(scope, receive, send)
                    return
            await mcp_asgi(scope, receive, send)

    return Route("/mcp", endpoint=_TokenGuard(), methods=["GET", "POST", "DELETE"])
