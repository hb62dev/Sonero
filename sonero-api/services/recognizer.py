import asyncio
from pathlib import Path
from typing import Optional
from shazamio import Shazam
from schemas.song import TrackInfo


async def recognize(audio_path: Path) -> Optional[TrackInfo]:
    """
    Sends the audio file to the Shazam API and parses the response.
    Returns a TrackInfo if a song is found, None otherwise.
    """
    shazam = Shazam()
    data = await shazam.recognize(str(audio_path))

    if "track" not in data:
        return None

    track = data["track"]

    # --- Cover image ---
    cover_url: Optional[str] = None
    images = track.get("images", {})
    cover_url = images.get("coverarthq") or images.get("coverart")

    # --- Genre ---
    genre: Optional[str] = None
    genres = track.get("genres", {})
    genre = genres.get("primary")

    # --- Year & Album from metadata sections ---
    year: Optional[str] = None
    album: Optional[str] = None
    for section in track.get("sections", []):
        if section.get("type") == "SONG":
            for meta in section.get("metadata", []):
                title = meta.get("title", "").lower()
                if title == "released":
                    year = meta.get("text")
                elif title == "album":
                    album = meta.get("text")

    return TrackInfo(
        title=track.get("title", "Unknown"),
        artist=track.get("subtitle", "Unknown"),
        album=album,
        cover_url=cover_url,
        genre=genre,
        year=year,
        shazam_url=track.get("url"),
        track_key=track.get("key"),
    )
