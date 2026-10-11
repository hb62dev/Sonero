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
WEEKDAYS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

mcp = MCPServer(
    name="sonero",
    title="Sonero",
    description="Estadísticas de uso de Sonero: biblioteca musical y hábitos de escucha.",
    instructions=(
        "Herramientas de solo lectura sobre la biblioteca y el historial de escucha de Sonero. "
        "Empieza por get_listening_summary para una visión general; usa get_top_tracks, "
        "get_top_artists y get_listening_timeline para el detalle. Los periodos se indican en "
        "días hacia atrás desde ahora. Las horas y días de la semana están en la zona horaria "
        "local de la computadora donde corre Sonero."
    ),
    version="1.0.0",
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
