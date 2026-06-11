from fastapi import APIRouter, HTTPException, Query, Depends
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session
from pathlib import Path
from config import settings
from database import get_db
from models import Media, PlaylistMedia, PlaybackEvent
from services import downloader
from schemas.video import VideoDownloadRequest, VideoInfoResponse
from schemas.song import TrackInfo
from routers.metadata import read_mp3_basic_info
import hashlib
import re

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
    "/downloads/playlist/info",
    summary="Get playlist information and videos",
)
async def get_playlist_info_route(url: str = Query(..., description="YouTube Playlist URL")):
    try:
        info = await downloader.get_playlist_info(url)
        return info
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error fetching playlist info: {str(e)}")


def get_file_md5(path: Path) -> str:
    hasher = hashlib.md5()
    with open(path, "rb") as f:
        while chunk := f.read(8192):
            hasher.update(chunk)
    return hasher.hexdigest()


@router.get(
    "/downloads/duplicates",
    summary="Find duplicate files on disk",
)
async def get_duplicates(db: Session = Depends(get_db)) -> dict:
    all_files = []
    seen_paths = set()
    
    # Scan music dir
    if settings.MUSIC_DIR.exists():
        for f in settings.MUSIC_DIR.rglob("*"):
            if f.is_file() and f.suffix.lower() in {".mp3", ".m4a", ".mp4", ".webm", ".mkv", ".avi", ".mov"}:
                res_path = f.resolve()
                if res_path not in seen_paths:
                    seen_paths.add(res_path)
                    all_files.append(f)
                    
    # Scan video dir
    if settings.VIDEO_DIR.exists() and settings.VIDEO_DIR.resolve() != settings.MUSIC_DIR.resolve():
        for f in settings.VIDEO_DIR.rglob("*"):
            if f.is_file() and f.suffix.lower() in {".mp3", ".m4a", ".mp4", ".webm", ".mkv", ".avi", ".mov"}:
                res_path = f.resolve()
                if res_path not in seen_paths:
                    seen_paths.add(res_path)
                    all_files.append(f)
                    
    # Group by size
    files_by_size = {}
    for f in all_files:
        try:
            size = f.stat().st_size
            files_by_size.setdefault(size, []).append(f)
        except Exception:
            continue
            
    # For sizes with multiple files, calculate MD5
    duplicates_by_hash = {}
    for size, files in files_by_size.items():
        if len(files) < 2:
            continue
        for f in files:
            try:
                md5_hash = get_file_md5(f)
                duplicates_by_hash.setdefault(md5_hash, []).append(f)
            except Exception:
                continue
                
    # Prepare result structure
    exact_groups = []
    for h, files in duplicates_by_hash.items():
        if len(files) < 2:
            continue
            
        group_files = []
        for f in files:
            # Determine DB filename
            if f.is_relative_to(settings.VIDEO_DIR) and settings.VIDEO_DIR != settings.MUSIC_DIR:
                filename = f"videos/{str(f.relative_to(settings.VIDEO_DIR)).replace(chr(92), '/')}"
            else:
                filename = str(f.relative_to(settings.MUSIC_DIR)).replace(chr(92), '/')
                
            media_entry = db.query(Media).filter(Media.filename == filename).first()
            stat = f.stat()
            
            group_files.append({
                "filename": filename,
                "absolute_path": str(f.resolve()),
                "in_db": media_entry is not None,
                "size_mb": round(stat.st_size / 1024 / 1024, 2),
                "created_at": stat.st_ctime,
                "title": media_entry.title if media_entry else f.stem,
                "artist": media_entry.artist if media_entry else "",
            })
            
        size_mb = group_files[0]["size_mb"]
        exact_groups.append({
            "hash": h,
            "size_mb": size_mb,
            "files": group_files
        })
        
    return {"exact_duplicates": exact_groups}


class CleanDuplicatesRequest(BaseModel):
    dry_run: bool = False


@router.post(
    "/downloads/duplicates/clean",
    summary="Delete duplicate files on disk and database",
)
async def clean_duplicates(body: CleanDuplicatesRequest, db: Session = Depends(get_db)) -> dict:
    dry_run = body.dry_run
    all_files = []
    seen_paths = set()
    
    if settings.MUSIC_DIR.exists():
        for f in settings.MUSIC_DIR.rglob("*"):
            if f.is_file() and f.suffix.lower() in {".mp3", ".m4a", ".mp4", ".webm", ".mkv", ".avi", ".mov"}:
                res_path = f.resolve()
                if res_path not in seen_paths:
                    seen_paths.add(res_path)
                    all_files.append(f)
                    
    if settings.VIDEO_DIR.exists() and settings.VIDEO_DIR.resolve() != settings.MUSIC_DIR.resolve():
        for f in settings.VIDEO_DIR.rglob("*"):
            if f.is_file() and f.suffix.lower() in {".mp3", ".m4a", ".mp4", ".webm", ".mkv", ".avi", ".mov"}:
                res_path = f.resolve()
                if res_path not in seen_paths:
                    seen_paths.add(res_path)
                    all_files.append(f)
                    
    files_by_size = {}
    for f in all_files:
        try:
            size = f.stat().st_size
            files_by_size.setdefault(size, []).append(f)
        except Exception:
            continue
            
    duplicates_by_hash = {}
    for size, files in files_by_size.items():
        if len(files) < 2:
            continue
        for f in files:
            try:
                md5_hash = get_file_md5(f)
                duplicates_by_hash.setdefault(md5_hash, []).append(f)
            except Exception:
                continue
                
    deleted_files = []
    space_saved_bytes = 0
    
    for h, files in duplicates_by_hash.items():
        if len(files) < 2:
            continue
            
        group_items = []
        for f in files:
            if f.is_relative_to(settings.VIDEO_DIR) and settings.VIDEO_DIR != settings.MUSIC_DIR:
                filename = f"videos/{str(f.relative_to(settings.VIDEO_DIR)).replace(chr(92), '/')}"
            else:
                filename = str(f.relative_to(settings.MUSIC_DIR)).replace(chr(92), '/')
                
            media_entry = db.query(Media).filter(Media.filename == filename).first()
            stat = f.stat()
            has_dup_suffix = bool(re.search(r'\s*\(\d+\)$|\s*_\d+$', f.stem))
            
            group_items.append({
                "path": f,
                "filename": filename,
                "db_entry": media_entry,
                "ctime": stat.st_ctime,
                "size": stat.st_size,
                "has_dup_suffix": has_dup_suffix
            })
            
        # Prioritize winner:
        # 1. Has DB entry
        # 2. Doesn't have duplicate suffix (like (1))
        # 3. Oldest added_at or ctime
        def sort_key(item):
            has_db = item["db_entry"] is not None
            db_priority = -1 if has_db else 0
            suffix_priority = 1 if item["has_dup_suffix"] else 0
            db_added_at = item["db_entry"].added_at.timestamp() if (has_db and item["db_entry"].added_at) else item["ctime"]
            return (db_priority, suffix_priority, db_added_at)
            
        group_items.sort(key=sort_key)
        winner = group_items[0]
        losers = group_items[1:]
        
        media_win = winner["db_entry"]
        
        for loser in losers:
            media_del = loser["db_entry"]
            
            # Database reconciliation
            if media_del and media_win:
                # Reassociate playlist media
                for pm in list(media_del.playlist_entries):
                    media_del.playlist_entries.remove(pm)
                    # Check if winner is already in this playlist
                    exists = db.query(PlaylistMedia).filter(
                        PlaylistMedia.playlist_id == pm.playlist_id,
                        PlaylistMedia.media_id == media_win.id
                    ).first()
                    if not exists:
                        media_win.playlist_entries.append(pm)
                    else:
                        db.delete(pm)
                        
                # Reassociate playback events
                for pe in list(media_del.playback_events):
                    media_del.playback_events.remove(pe)
                    media_win.playback_events.append(pe)
                    
                db.flush()
                db.delete(media_del)
            elif media_del:
                db.delete(media_del)
                
            # Delete file on disk
            if not dry_run:
                try:
                    if loser["path"].exists():
                        loser["path"].unlink()
                except Exception as e:
                    raise HTTPException(status_code=500, detail=f"Error deleting file {loser['path']}: {str(e)}")
                    
            deleted_files.append(loser["filename"])
            space_saved_bytes += loser["size"]
            
    if not dry_run:
        db.commit()
    else:
        db.rollback()
        
    return {
        "dry_run": dry_run,
        "deleted_count": len(deleted_files),
        "deleted_files": deleted_files,
        "space_saved_mb": round(space_saved_bytes / 1024 / 1024, 2)
    }


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





