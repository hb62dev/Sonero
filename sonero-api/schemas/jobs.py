from pydantic import BaseModel
from typing import Optional, Literal
from schemas.song import TrackInfo


class JobStatus(BaseModel):
    job_id: str
    status: Literal[
        "pending", "listening", "recognizing",
        "searching", "downloading", "done", "failed", "paused"
    ]
    step: str = ""
    progress: int = 0  # 0–100
    track: Optional[TrackInfo] = None
    file_path: Optional[str] = None
    error: Optional[str] = None
    warning: Optional[str] = None
    url: Optional[str] = None
    format_id: Optional[str] = None
    is_mp3: bool = False
    mp3_request: Optional[dict] = None


class JobResponse(BaseModel):
    job_id: str
    status: str
    message: str


class BatchJobStatus(BaseModel):
    job_id: str
    status: Literal["pending", "running", "done", "failed"]
    total: int = 0
    completed: int = 0
    failed: int = 0
    current: str = ""
    errors: list[str] = []
