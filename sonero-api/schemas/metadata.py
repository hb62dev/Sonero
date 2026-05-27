from pydantic import BaseModel, Field
from typing import Optional, List


class MetadataBase(BaseModel):
    title: Optional[str] = Field(None, description="Title of the track")
    artist: Optional[str] = Field(None, description="Artist of the track")
    album: Optional[str] = Field(None, description="Album name")
    year: Optional[str] = Field(None, description="Release year")
    cover_art_base64: Optional[str] = Field(None, description="Base64 encoded string of the album cover image")


class MetadataResponse(MetadataBase):
    filename: str = Field(..., description="The MP3 filename")
    filepath: Optional[str] = Field(None, description="Relative or absolute path")


class MetadataUpdateItem(MetadataBase):
    filename: str = Field(..., description="The MP3 filename to update")


class MetadataBatchUpdateRequest(BaseModel):
    updates: List[MetadataUpdateItem] = Field(..., description="List of files to update with their new metadata")


class AutoFillRequest(BaseModel):
    filenames: List[str] = Field(..., description="List of filenames to autofill using Shazam")

