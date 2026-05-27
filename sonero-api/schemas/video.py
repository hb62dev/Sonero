from pydantic import BaseModel
from typing import List, Optional

class VideoFormat(BaseModel):
    format_id: str
    resolution: str
    ext: str
    filesize_mb: Optional[float] = None
    is_audio_only: bool = False

class VideoInfoResponse(BaseModel):
    title: str
    thumbnail: str
    formats: List[VideoFormat]

class VideoDownloadRequest(BaseModel):
    url: str
    format_id: str
