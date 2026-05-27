from pydantic import BaseModel
from typing import Optional


class TrackInfo(BaseModel):
    title: str
    artist: str
    album: Optional[str] = None
    cover_url: Optional[str] = None
    genre: Optional[str] = None
    year: Optional[str] = None
    shazam_url: Optional[str] = None
    track_key: Optional[str] = None

    @property
    def display_name(self) -> str:
        return f"{self.artist} - {self.title}"
