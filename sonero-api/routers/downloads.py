from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel
from config import settings
from services import downloader
from schemas.video import VideoDownloadRequest, VideoInfoResponse
from schemas.song import TrackInfo
from routers.metadata import read_mp3_basic_info

router = APIRouter()


@router.get(
    "/downloads",
    summary="List all downloaded MP3 files",
)
async def list_downloads() -> dict:
    settings.MUSIC_DIR.mkdir(exist_ok=True)
    files = []
    
    for f in settings.MUSIC_DIR.rglob("*.mp3"):
        if f.is_file():
            files.append(f)
            
    videos_dir = settings.VIDEO_DIR
    if videos_dir.exists():
        for f in videos_dir.rglob("*"):
            if f.is_file() and f.suffix in [".mp4", ".webm", ".mkv"]:
                files.append(f)
                
    files.sort(key=lambda x: x.stat().st_ctime, reverse=True)
    
    downloads = []
    for f in files:
        stat = f.stat()
        meta = read_mp3_basic_info(f) if f.suffix == ".mp3" else {}
        
        if f.is_relative_to(settings.VIDEO_DIR) and settings.VIDEO_DIR != settings.MUSIC_DIR:
            filename = f"videos/{str(f.relative_to(settings.VIDEO_DIR)).replace(chr(92), '/')}"
        else:
            filename = str(f.relative_to(settings.MUSIC_DIR)).replace(chr(92), '/')
            
        playlist_name = ""
        if not filename.startswith("videos/"):
            rel_parts = f.relative_to(settings.MUSIC_DIR).parts
            if len(rel_parts) > 1:
                playlist_name = rel_parts[0]
            
        downloads.append({
            "filename": filename,
            "size_mb": round(stat.st_size / 1024 / 1024, 2),
            "created_at": stat.st_ctime,
            "title": meta.get("title") or f.stem,
            "artist": meta.get("artist"),
            "album": meta.get("album"),
            "year": meta.get("year"),
            "cover_url": f"/api/v1/metadata/cover/{filename}" if meta.get("has_cover") and f.suffix == ".mp3" else None,
            "playlist": playlist_name,
        })
    return {"total": len(downloads), "downloads": downloads}



@router.get(
    "/downloads/videos",
    summary="List all downloaded video files",
)
async def list_videos() -> dict:
    videos_dir = settings.VIDEO_DIR
    videos_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for f in sorted(videos_dir.rglob("*"), key=lambda x: x.stat().st_ctime, reverse=True):
        if f.is_file() and f.suffix in [".mp4", ".mp3", ".webm"]:
            rel_path = str(f.relative_to(videos_dir)).replace(chr(92), '/')
            stat = f.stat()
            files.append({
                "filename": rel_path,
                "size_mb": round(stat.st_size / 1024 / 1024, 2),
                "created_at": stat.st_ctime,
            })
    return {"total": len(files), "videos": files}



@router.get(
    "/downloads/video/info",
    response_model=VideoInfoResponse,
    summary="Get video information and available formats",
)
async def get_video_info(url: str = Query(..., description="YouTube URL")):
    try:
        info = await downloader.get_video_info(url)
        return info
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error fetching video info: {str(e)}")


import uuid
from typing import Dict
from fastapi import BackgroundTasks
from schemas.jobs import JobResponse, JobStatus
from services.downloader import PauseDownload

video_jobs: Dict[str, JobStatus] = {}
pause_flags: Dict[str, bool] = {}

@router.get(
    "/downloads/video/jobs",
    response_model=list[JobStatus],
    summary="Get all video download jobs",
)
async def get_all_video_jobs():
    return list(video_jobs.values())

@router.get(
    "/downloads/video/jobs/{job_id}",
    response_model=JobStatus,
    summary="Get video download job status",
)
async def get_video_job(job_id: str):
    if job_id not in video_jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    return video_jobs[job_id]

@router.post(
    "/downloads/video",
    response_model=JobResponse,
    summary="Download video from a specific format",
)
async def download_video(request: VideoDownloadRequest, background_tasks: BackgroundTasks):
    job_id = str(uuid.uuid4())[:8]
    video_jobs[job_id] = JobStatus(
        job_id=job_id,
        status="pending",
        step="⏳ Preparando descarga...",
        progress=0,
        url=request.url,
        format_id=request.format_id,
        is_mp3=False,
    )
    pause_flags[job_id] = False
    background_tasks.add_task(_run_video_download, job_id, request.url, request.format_id)
    return JobResponse(
        job_id=job_id,
        status="pending",
        message="Descarga iniciada",
    )

async def _run_video_download(job_id: str, url: str, format_id: str):
    try:
        video_jobs[job_id].status = "downloading"
        video_jobs[job_id].step = "⬇️ Descargando..."
        
        def update_progress(p):
            video_jobs[job_id].progress = p
            
        def check_pause():
            return pause_flags.get(job_id, False)
            
        path, warning = await downloader.download_video(url, format_id, progress_callback=update_progress, check_pause_callback=check_pause)
        
        video_jobs[job_id].status = "done"
        video_jobs[job_id].step = f"✅ Guardado: {path.name}"
        video_jobs[job_id].progress = 100
        video_jobs[job_id].file_path = str(path)
        video_jobs[job_id].warning = warning
    except PauseDownload:
        video_jobs[job_id].status = "paused"
        video_jobs[job_id].step = "⏸️ Pausado"
    except Exception as exc:
        video_jobs[job_id].status = "failed"
        video_jobs[job_id].step = "❌ Error en descarga"
        video_jobs[job_id].error = str(exc)

class Mp3DownloadRequest(BaseModel):
    url: str
    title: str
    artist: str = ""
    playlist: str | None = None

@router.post(
    "/downloads/mp3",
    response_model=JobResponse,
    summary="Download MP3 directly from URL",
)
async def download_mp3_direct(request: Mp3DownloadRequest, background_tasks: BackgroundTasks):
    job_id = str(uuid.uuid4())[:8]
    video_jobs[job_id] = JobStatus(
        job_id=job_id,
        status="pending",
        step="⏳ Preparando descarga...",
        progress=0,
        url=request.url,
        is_mp3=True,
        mp3_request=request.model_dump(),
    )
    pause_flags[job_id] = False
    background_tasks.add_task(_run_mp3_download, job_id, request)
    return JobResponse(
        job_id=job_id,
        status="pending",
        message="Descarga MP3 iniciada",
    )

async def _run_mp3_download(job_id: str, request: Mp3DownloadRequest):
    try:
        video_jobs[job_id].status = "downloading"
        video_jobs[job_id].step = "⬇️ Descargando MP3..."
        
        def update_progress(p):
            video_jobs[job_id].progress = p
            
        def check_pause():
            return pause_flags.get(job_id, False)
            
        track = TrackInfo(title=request.title, artist=request.artist)
        path = await downloader.download_mp3(request.url, track, playlist=request.playlist, progress_callback=update_progress, check_pause_callback=check_pause)
        
        video_jobs[job_id].status = "done"
        video_jobs[job_id].step = f"✅ Guardado: {path.name}"
        video_jobs[job_id].progress = 100
        video_jobs[job_id].file_path = str(path)
    except PauseDownload:
        video_jobs[job_id].status = "paused"
        video_jobs[job_id].step = "⏸️ Pausado"
    except Exception as exc:
        video_jobs[job_id].status = "failed"
        video_jobs[job_id].step = "❌ Error en descarga"
        video_jobs[job_id].error = str(exc)

@router.post(
    "/downloads/video/jobs/{job_id}/pause",
    response_model=JobResponse,
    summary="Pause a running download job",
)
async def pause_video_job(job_id: str):
    if job_id not in video_jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    if video_jobs[job_id].status not in ["pending", "downloading"]:
        raise HTTPException(status_code=400, detail="Job is not running")
    
    pause_flags[job_id] = True
    return JobResponse(
        job_id=job_id,
        status="paused",
        message="Descarga pausada",
    )

@router.post(
    "/downloads/video/jobs/{job_id}/resume",
    response_model=JobResponse,
    summary="Resume a paused download job",
)
async def resume_video_job(job_id: str, background_tasks: BackgroundTasks):
    if job_id not in video_jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    if video_jobs[job_id].status != "paused":
        raise HTTPException(status_code=400, detail="Job is not paused")
    
    job = video_jobs[job_id]
    job.status = "pending"
    job.step = "⏳ Reanudando..."
    pause_flags[job_id] = False
    
    if job.is_mp3:
        req = Mp3DownloadRequest(**job.mp3_request)
        background_tasks.add_task(_run_mp3_download, job_id, req)
    else:
        background_tasks.add_task(_run_video_download, job_id, job.url, job.format_id)
        
    return JobResponse(
        job_id=job_id,
        status="pending",
        message="Descarga reanudada",
    )


@router.get(
    "/downloads/videos/{filename:path}",
    summary="Get a specific video file",
)
async def get_video_file(filename: str) -> FileResponse:
    file_path = settings.VIDEO_DIR / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Archivo de video '{filename}' no encontrado.")
    
    media_type = "video/mp4"
    if file_path.suffix == ".mp3":
        media_type = "audio/mpeg"
        
    return FileResponse(
        path=str(file_path),
        filename=filename,
        media_type=media_type,
    )


@router.delete(
    "/downloads/videos/{filename:path}",
    summary="Delete a downloaded video",
)
async def delete_video_file(filename: str) -> dict:
    file_path = settings.VIDEO_DIR / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Archivo de video '{filename}' no encontrado.")
    file_path.unlink()
    return {"message": f"'{filename}' eliminado correctamente."}


@router.get(
    "/downloads/{filename:path}",
    summary="Download a specific MP3 file",
)
async def get_file(filename: str) -> FileResponse:
    file_path = settings.MUSIC_DIR / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Archivo '{filename}' no encontrado.")
    return FileResponse(
        path=str(file_path),
        filename=filename,
        media_type="audio/mpeg",
    )


@router.delete(
    "/downloads/{filename:path}",
    summary="Delete a downloaded MP3",
)
async def delete_file(filename: str) -> dict:
    file_path = settings.MUSIC_DIR / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Archivo '{filename}' no encontrado.")
    file_path.unlink()
    return {"message": f"'{filename}' eliminado correctamente."}

