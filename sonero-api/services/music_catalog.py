"""
Public music catalogs used for discovery and metadata, no account or API key:

* Deezer API (api.deezer.com): artist search, related artists, top tracks,
  track search with 30 s previews, album genres and release dates.
* iTunes Search API (itunes.apple.com): fallback for genre/album/year.

Everything is best effort: without internet these functions raise
CatalogUnavailable, and callers fall back to library-only behaviour.
"""

import asyncio
import difflib
import re
import time
import unicodedata

import httpx

DEEZER = "https://api.deezer.com"
ITUNES = "https://itunes.apple.com/search"
TIMEOUT = httpx.Timeout(8.0, connect=4.0)
CACHE_TTL = 6 * 3600

_cache: dict[str, tuple[float, object]] = {}
# Deezer allows ~50 requests / 5 s; stay well below it
_semaphore = asyncio.Semaphore(4)


class CatalogUnavailable(Exception):
    """No internet, or the catalog didn't answer."""


async def _get_json(url: str, params: dict | None = None) -> dict:
    key = url + "?" + "&".join(f"{k}={v}" for k, v in sorted((params or {}).items()))
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < CACHE_TTL:
        return hit[1]  # type: ignore[return-value]
    async with _semaphore:
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT) as client:
                res = await client.get(url, params=params)
                res.raise_for_status()
                data = res.json()
        except (httpx.HTTPError, ValueError) as e:
            raise CatalogUnavailable(str(e) or type(e).__name__) from e
    if isinstance(data, dict) and data.get("error"):
        # Deezer reports quota/lookup problems in the body with HTTP 200
        raise CatalogUnavailable(str(data["error"]))
    _cache[key] = (time.time(), data)
    return data


# ── Text matching ─────────────────────────────────────────────────────────────

_NOISE = re.compile(
    r"\((?:official|audio|video|lyrics?|visualizer|audio visualizer|letra|slowed|sped up|reverb|"
    r"remaster(?:ed)?|explicit|hd|hq|clip oficial)[^)]*\)"
    r"|\[(?:[^\]]*(?:prod|official|audio|video|lyrics?|slowed|visualizer)[^\]]*)\]"
    r"|\b(?:slowed|reverb|sped up|nightcore|8d audio|official audio|official video|lyrics?)\b"
    r"|\(\s*\d+\s*hz\s*\)",
    re.IGNORECASE,
)


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text or "").encode("ascii", "ignore").decode()
    text = _NOISE.sub(" ", text.lower())
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def clean_title(title: str) -> str:
    """Strip upload noise ("(Official Audio)", "[prod. X]", "slowed + reverb"...)."""
    cleaned = _NOISE.sub(" ", title or "")
    cleaned = re.sub(r"[\(\[]\s*[\)\]]", " ", cleaned)
    return re.sub(r"\s+", " ", cleaned).strip(" -–_")


def similarity(a: str, b: str) -> float:
    a, b = normalize(a), normalize(b)
    if not a or not b:
        return 0.0
    if a == b or a in b or b in a:
        return 1.0 if a == b else 0.9
    return difflib.SequenceMatcher(None, a, b).ratio()


_GENRE_ALIASES = {
    "Hip-Hop/Rap": ("hip hop", "hip-hop", "rap", "rap/hip hop", "hip-hop/rap", "hip hop/rap", "trap", "drill"),
    "R&B/Soul": ("r&b", "rnb", "r&b/soul", "soul", "contemporary r&b"),
    "Electrónica": ("electro", "electronic", "electronica", "electrónica", "dance", "edm", "house", "techno"),
    "Alternativa": ("alternative", "alternativo", "alternativa", "indie", "indie rock", "indie pop"),
    "Reggaetón/Latino": ("reggaeton", "reggaetón", "latin", "latino", "urbano latino", "musica tropical"),
    "Pop": ("pop", "k-pop", "j-pop", "pop latino"),
    "Rock": ("rock", "hard rock", "metal", "punk"),
    "Bandas sonoras": ("soundtrack", "soundtracks", "films/games", "film scores", "anime", "video game"),
}
_GENRE_LOOKUP = {alias: name for name, aliases in _GENRE_ALIASES.items() for alias in aliases}


def canonical_genre(genre: str | None) -> str | None:
    """Unifies catalog genre names ("Rap/Hip Hop" vs "Hip-Hop/Rap") so mixes don't split."""
    if not genre:
        return None
    return _GENRE_LOOKUP.get(genre.strip().lower(), genre.strip())


def split_artist_title(raw: str) -> tuple[str, str]:
    """'Artist - Title' file names → (artist, title)."""
    parts = re.split(r"\s+[-–—]\s+", raw, maxsplit=1)
    if len(parts) == 2:
        return parts[0].strip(), parts[1].strip()
    return "", raw.strip()


# ── Deezer ────────────────────────────────────────────────────────────────────

def _track(t: dict) -> dict:
    album = t.get("album") or {}
    artist = t.get("artist") or {}
    return {
        "external_id": f"deezer:{t.get('id')}",
        "title": t.get("title") or "",
        "artist": artist.get("name") or "",
        "album": album.get("title") or "",
        "duration": t.get("duration"),
        "preview_url": t.get("preview") or None,
        "cover_url": album.get("cover_medium") or album.get("cover") or None,
        "popularity": t.get("rank"),
        "link": t.get("link"),
    }


async def find_artist(name: str) -> dict | None:
    data = await _get_json(f"{DEEZER}/search/artist", {"q": name, "limit": 5})
    best, best_score = None, 0.0
    for a in data.get("data", []):
        score = similarity(name, a.get("name", ""))
        if score > best_score:
            best, best_score = a, score
    if best is None or best_score < 0.75:
        return None
    return {"id": best["id"], "name": best["name"], "fans": best.get("nb_fan"),
            "picture_url": best.get("picture_medium")}


async def related_artists(name: str, limit: int = 10) -> list[dict]:
    artist = await find_artist(name)
    if artist is None:
        return []
    data = await _get_json(f"{DEEZER}/artist/{artist['id']}/related", {"limit": limit})
    return [{"name": a["name"], "fans": a.get("nb_fan"), "picture_url": a.get("picture_medium")}
            for a in data.get("data", [])[:limit]]


async def artist_top_tracks(name: str, limit: int = 10) -> list[dict]:
    artist = await find_artist(name)
    if artist is None:
        return []
    data = await _get_json(f"{DEEZER}/artist/{artist['id']}/top", {"limit": limit})
    return [_track(t) for t in data.get("data", [])[:limit]]


async def search_tracks(query: str, limit: int = 10) -> list[dict]:
    data = await _get_json(f"{DEEZER}/search", {"q": query, "limit": limit})
    return [_track(t) for t in data.get("data", [])[:limit]]


async def genre_chart(genre: str, limit: int = 20) -> list[dict]:
    """Top tracks of a Deezer genre ("Rap/Hip Hop", "Reggaeton", "Rock"...)."""
    genres = await _get_json(f"{DEEZER}/genre")
    match = max(genres.get("data", []), key=lambda g: similarity(genre, g.get("name", "")), default=None)
    if match is None or similarity(genre, match["name"]) < 0.6:
        return []
    data = await _get_json(f"{DEEZER}/chart/{match['id']}/tracks", {"limit": limit})
    return [_track(t) for t in data.get("data", [])[:limit]]


# ── Metadata lookup (for enrichment) ──────────────────────────────────────────

async def lookup_metadata(title: str, artist: str = "") -> dict | None:
    """
    Best catalog match for a library song, with a 0-1 confidence.
    Returns {title, artist, album, genre, year, confidence, source} or None.
    """
    clean = clean_title(title)
    if not artist:
        artist, clean = split_artist_title(clean)
    query = f'artist:"{artist}" track:"{clean}"' if artist else clean

    candidates: list[dict] = []
    try:
        data = await _get_json(f"{DEEZER}/search", {"q": query, "limit": 5})
        if not data.get("data") and artist:
            data = await _get_json(f"{DEEZER}/search", {"q": f"{artist} {clean}", "limit": 5})
        for t in data.get("data", []):
            candidates.append({"source": "deezer", "raw": t, "title": t.get("title", ""),
                               "artist": (t.get("artist") or {}).get("name", "")})
    except CatalogUnavailable:
        pass

    try:
        data = await _get_json(ITUNES, {"term": f"{artist} {clean}".strip(), "entity": "song", "limit": 5})
        for r in data.get("results", []):
            candidates.append({"source": "itunes", "raw": r, "title": r.get("trackName", ""),
                               "artist": r.get("artistName", "")})
    except CatalogUnavailable:
        pass

    if not candidates:
        return None

    def score(c: dict) -> float:
        t = similarity(clean, c["title"])
        # Without a known artist a title match alone is weak evidence
        a = similarity(artist, c["artist"]) if artist else 0.3
        return 0.6 * t + 0.4 * a

    best = max(candidates, key=score)
    confidence = round(score(best), 2)
    raw = best["raw"]

    if best["source"] == "deezer":
        album_id = (raw.get("album") or {}).get("id")
        genre, year = None, None
        if album_id:
            try:
                album = await _get_json(f"{DEEZER}/album/{album_id}")
                genres = (album.get("genres") or {}).get("data") or []
                genre = genres[0]["name"] if genres else None
                year = (album.get("release_date") or "")[:4] or None
            except CatalogUnavailable:
                pass
        # Deezer genres are coarse; prefer iTunes' when it agrees on the song
        itunes = next((c for c in candidates if c["source"] == "itunes" and score(c) >= 0.75
                       and similarity(best["artist"], c["artist"]) >= 0.8), None)
        if itunes:
            genre = itunes["raw"].get("primaryGenreName") or genre
            year = year or (itunes["raw"].get("releaseDate") or "")[:4] or None
        return {"title": raw.get("title"), "artist": best["artist"],
                "album": (raw.get("album") or {}).get("title"), "genre": canonical_genre(genre), "year": year,
                "confidence": confidence, "source": "deezer"}

    return {"title": raw.get("trackName"), "artist": raw.get("artistName"),
            "album": raw.get("collectionName"), "genre": canonical_genre(raw.get("primaryGenreName")),
            "year": (raw.get("releaseDate") or "")[:4] or None,
            "confidence": confidence, "source": "itunes"}
