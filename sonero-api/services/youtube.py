"""
Shared yt-dlp configuration for every YouTube search and download.

* JavaScript runtime: recent YouTube pages require solving JS challenges;
  yt-dlp needs Deno, Node or Bun for that (plus the yt-dlp-ejs package).
  Without it many videos fail or only expose low-quality formats.
* yt-dlp's own User-Agent instead of a hard-coded browser string (a UA that
  doesn't match the client yt-dlp emulates looks more bot-like, not less).
* Warnings are logged instead of silenced, so problems are visible.
* User's cookies (services.cookies) when configured.
* A small pause between downloads, so batches don't trip YouTube's limits.
* Errors classified into user-facing messages ("bot" = YouTube asks to sign in).
"""

import asyncio
import logging
import os
import random
import shutil
import time
from datetime import date
from pathlib import Path

from services.cookies import CookieManager, get_cookie_browser

logger = logging.getLogger("sonero.youtube")

# yt-dlp versions are dates (YYYY.MM.DD). We compare with the newest release on
# PyPI; offline, a version this old is assumed to be outdated.
STALE_AFTER_DAYS = 90
_LATEST_TTL = 24 * 3600
MIN_SECONDS_BETWEEN_DOWNLOADS = 3.0

# The backend is often started by the desktop app or PyInstaller with a
# minimal PATH, so also look in the usual install locations
_EXTRA_BIN_DIRS = [
    "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
    str(Path.home() / ".deno" / "bin"), str(Path.home() / ".bun" / "bin"),
    str(Path.home() / ".volta" / "bin"), str(Path.home() / ".local" / "bin"),
    r"C:\Program Files\nodejs", str(Path.home() / "AppData" / "Roaming" / "npm"),
]


class _YtdlpLogger:
    """Routes yt-dlp output to logging; keeps the last error for callers."""

    def __init__(self):
        self.last_error: str | None = None

    def debug(self, msg: str) -> None:
        if msg.startswith("[debug] "):
            logger.debug(msg)

    def info(self, msg: str) -> None:
        logger.debug(msg)

    def warning(self, msg: str) -> None:
        logger.warning("yt-dlp: %s", msg)

    def error(self, msg: str) -> None:
        self.last_error = msg
        logger.error("yt-dlp: %s", msg)


def _which(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        # Version managers (fnm, nvm) put per-shell symlinks on PATH that vanish
        # with the shell; use the real installed binary instead
        return os.path.realpath(found)
    for d in _EXTRA_BIN_DIRS:
        for candidate in (Path(d) / name, Path(d) / f"{name}.exe"):
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return str(candidate)
    return None


_runtime_cache: tuple[str, str] | None | bool = False  # False = not checked yet


def js_runtime() -> tuple[str, str] | None:
    """(name, path) of the JavaScript runtime yt-dlp will use, preferring Deno (its default)."""
    global _runtime_cache
    if _runtime_cache is False:
        _runtime_cache = next(((n, p) for n in ("deno", "node", "bun") if (p := _which(n))), None)
    return _runtime_cache  # type: ignore[return-value]


def ejs_installed() -> bool:
    try:
        import yt_dlp_ejs  # noqa: F401

        return True
    except ImportError:
        return False


def apply_common(opts: dict) -> dict:
    """Adds Sonero's standard YouTube settings to a yt-dlp options dict."""
    opts = dict(opts)

    headers = dict(opts.get("http_headers") or {})
    headers.pop("User-Agent", None)
    if headers:
        opts["http_headers"] = headers
    else:
        opts.pop("http_headers", None)

    runtime = js_runtime()
    if runtime:
        name, path = runtime
        opts.setdefault("js_runtimes", {name: {"path": path}})
        # The challenge solver scripts come from the yt-dlp-ejs package
        # (requirements.txt). Fetching them at runtime (remote_components)
        # would download and run code on every launch, so it stays off.

    opts.setdefault("logger", _YtdlpLogger())
    opts["no_warnings"] = False
    opts.update(CookieManager.get_cookie_opts())
    return opts


# ── Pacing ────────────────────────────────────────────────────────────────────

_last_download = 0.0
_pace_lock = asyncio.Lock()


async def pace() -> None:
    """Waits so consecutive YouTube downloads are a few seconds apart."""
    global _last_download
    async with _pace_lock:
        wait = _last_download + MIN_SECONDS_BETWEEN_DOWNLOADS + random.uniform(0, 2) - time.monotonic()
        if wait > 0:
            await asyncio.sleep(wait)
        _last_download = time.monotonic()


# ── Errors ────────────────────────────────────────────────────────────────────

_BOT_HINT = ("YouTube pidió verificar que no eres un bot. Suele pasar con VPN o muchas descargas seguidas. "
             "Activa \"Leer cookies de un navegador\" o carga un cookies.txt en Ajustes → Autenticación, "
             "o desactiva la VPN para Sonero.")


def classify_error(error: BaseException | str) -> tuple[str, str]:
    """(kind, user-facing message). kind: bot, age, private, unavailable, rate_limited, network, outdated, other."""
    text = str(error)
    low = text.lower()
    # Age check first: "Sign in to confirm your age" would also match the bot check
    if "confirm your age" in low or "age-restricted" in low or "inappropriate for some users" in low:
        return "age", ("El video tiene restricción de edad: YouTube exige una cuenta. "
                       "Configura cookies de un navegador con sesión iniciada en Ajustes → Autenticación.")
    if "not a bot" in low or "please sign in" in low or "sign in to confirm" in low:
        return "bot", _BOT_HINT
    if "private video" in low or "members-only" in low or "join this channel" in low:
        return "private", "El video es privado o solo para miembros del canal."
    if "http error 429" in low or "too many requests" in low:
        return "rate_limited", ("YouTube está limitando las descargas (demasiadas peticiones). "
                                "Espera unos minutos antes de volver a intentarlo.")
    if "page needs to be reloaded" in low or "requested format is not available" in low \
            or "signature" in low or "nsig" in low or "n challenge" in low:
        return "outdated", ("YouTube cambió algo y yt-dlp no pudo procesar el video. "
                            "Actualiza yt-dlp (pip install -U \"yt-dlp[default]\") y vuelve a intentarlo.")
    if "video unavailable" in low or "not available in your country" in low or "has been removed" in low:
        return "unavailable", "El video no está disponible (eliminado o bloqueado en tu país)."
    if any(s in low for s in ("timed out", "connection", "network is unreachable", "name or service not known",
                              "nodename nor servname", "getaddrinfo")):
        return "network", "No hay conexión con YouTube. Revisa tu internet."
    return "other", text.replace("ERROR: ", "").strip()[:300]


# ── Health ────────────────────────────────────────────────────────────────────

def ytdlp_version() -> str:
    try:
        import yt_dlp

        return yt_dlp.version.__version__
    except Exception:
        return "desconocida"


def version_age_days(version: str) -> int | None:
    try:
        y, m, d = (int(p) for p in version.split(".")[:3])
        return (date.today() - date(y, m, d)).days
    except Exception:
        return None


_latest: tuple[float, str | None] = (0.0, None)


def latest_version() -> str | None:
    """Newest yt-dlp on PyPI (cached for a day); None if unreachable."""
    global _latest
    checked_at, version = _latest
    if time.time() - checked_at < _LATEST_TTL:
        return version
    try:
        import httpx

        res = httpx.get("https://pypi.org/pypi/yt-dlp/json", timeout=5)
        version = res.json()["info"]["version"]
    except Exception:
        version = None
    _latest = (time.time(), version)
    return version


def _as_tuple(version: str) -> tuple[int, ...]:
    try:
        return tuple(int(p) for p in version.split(".")[:3])
    except ValueError:
        return ()


def status() -> dict:
    version = ytdlp_version()
    age = version_age_days(version)
    latest = latest_version()
    if latest:
        outdated = _as_tuple(latest) > _as_tuple(version)
    else:
        outdated = age is not None and age > STALE_AFTER_DAYS
    runtime = js_runtime()
    cookie_file = CookieManager.get_cookie_opts().get("cookiefile")
    issues = []
    if outdated:
        newer = f" (hay una nueva: {latest})" if latest else ""
        issues.append(f"yt-dlp {version} está desactualizado{newer}; YouTube cambia a menudo y las versiones "
                      "viejas fallan más. Actualízalo con: pip install -U \"yt-dlp[default]\"")
    if runtime is None:
        issues.append("No se encontró Deno, Node ni Bun: muchos videos de YouTube fallarán. Instala Deno "
                      "(https://deno.com) o Node.js.")
    elif not ejs_installed():
        issues.append("Falta el paquete yt-dlp-ejs (resuelve los desafíos de YouTube). Instálalo con: "
                      "pip install -U \"yt-dlp[default]\"")
    return {
        "ytdlp_version": version,
        "ytdlp_age_days": age,
        "ytdlp_latest": latest,
        "outdated": bool(outdated),
        "js_runtime": runtime[0] if runtime else None,
        "ejs_installed": ejs_installed(),
        "cookies": "file" if cookie_file else ("browser:" + b if (b := get_cookie_browser()) else None),
        "ok": not issues,
        "issues": issues,
    }
