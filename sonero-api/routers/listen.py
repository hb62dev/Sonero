import uuid
import shutil
from pathlib import Path
from typing import Dict, Literal
from fastapi import APIRouter, BackgroundTasks, HTTPException, UploadFile, File, Form
from pydantic import BaseModel

from schemas.jobs import JobStatus, JobResponse
from schemas.song import TrackInfo
from services import recorder, recognizer, searcher, downloader
from config import settings

router = APIRouter()

# In-memory store for all pipeline jobs
jobs: Dict[str, JobStatus] = {}


# ── Request model ────────────────────────────────────────────────────────────

class ListenRequest(BaseModel):
    duration: int = 10
    auto_download: bool = True
    device_index: int | None = None
    source: Literal["mic", "system"] = "mic"
    playlist: str | None = None
    """
    Audio source mode:
      - "mic"    → Physical microphone. Pair with device_index to choose which mic.
      - "system" → WASAPI loopback. Captures audio from PC speakers/headphones.

    playlist: name of the sub-folder to save the MP3 into (optional).
      Leave null to save to the library root.
    """


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post(
    "/listen",
    response_model=JobResponse,
    summary="Start listening pipeline",
    description=(
        "Starts the full pipeline: record microphone → Shazam recognition → "
        "YouTube search → MP3 download. Returns a `job_id` immediately. "
        "Poll `/listen/jobs/{job_id}` to get progress and final result."
    ),
)
async def start_listening(
    request: ListenRequest,
    background_tasks: BackgroundTasks,
) -> JobResponse:
    job_id = str(uuid.uuid4())[:8]
    jobs[job_id] = JobStatus(
        job_id=job_id,
        status="pending",
        step="⏳ En cola...",
        progress=0,
    )
    background_tasks.add_task(
        _run_pipeline, job_id, request.duration, request.auto_download,
        request.device_index, request.source, request.playlist
    )
    return JobResponse(
        job_id=job_id,
        status="pending",
        message=f"Pipeline iniciado. Escuchando {request.duration}s...",
    )


@router.post(
    "/listen/upload",
    response_model=JobResponse,
    summary="Start listening pipeline with uploaded audio",
)
async def start_listening_upload(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    auto_download: bool = Form(True),
    playlist: str | None = Form(None),
) -> JobResponse:
    job_id = str(uuid.uuid4())[:8]
    jobs[job_id] = JobStatus(
        job_id=job_id,
        status="pending",
        step="⏳ Procesando audio subido...",
        progress=0,
    )
    
    settings.TMP_DIR.mkdir(exist_ok=True)
    temp_file_path = settings.TMP_DIR / f"{job_id}_{file.filename}"
    
    with open(temp_file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    background_tasks.add_task(
        _run_pipeline, job_id, 0, auto_download,
        None, "uploaded", playlist, temp_file_path
    )
    return JobResponse(
        job_id=job_id,
        status="pending",
        message="Audio recibido. Iniciando reconocimiento...",
    )


@router.post(
    "/recognize",
    response_model=TrackInfo,
    summary="Recognize uploaded audio using Shazam",
)
async def recognize_audio(
    file: UploadFile = File(...),
) -> TrackInfo:
    """
    Sube un archivo de audio WAV y obtiene los metadatos reconocidos por Shazam.
    """
    job_id = str(uuid.uuid4())[:8]
    settings.TMP_DIR.mkdir(parents=True, exist_ok=True)
    temp_file_path = settings.TMP_DIR / f"recognize_{job_id}_{file.filename}"
    
    with open(temp_file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    try:
        track = await recognizer.recognize(temp_file_path)
        if not track:
            raise HTTPException(status_code=404, detail="No se reconoció ninguna canción.")
        return track
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    finally:
        if temp_file_path.exists():
            try:
                temp_file_path.unlink()
            except Exception:
                pass


@router.get(
    "/listen/jobs/{job_id}",
    response_model=JobStatus,
    summary="Get job status",
)
async def get_job(job_id: str) -> JobStatus:
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail=f"Job '{job_id}' no encontrado.")
    return jobs[job_id]


@router.get(
    "/listen/jobs",
    response_model=list[JobStatus],
    summary="List all jobs",
)
async def list_jobs() -> list[JobStatus]:
    return list(jobs.values())


@router.delete(
    "/listen/jobs/{job_id}",
    summary="Delete a job from memory",
)
async def delete_job(job_id: str) -> dict:
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail=f"Job '{job_id}' no encontrado.")
    del jobs[job_id]
    return {"message": f"Job '{job_id}' eliminado."}


# ── Pipeline logic ────────────────────────────────────────────────────────────

async def _run_pipeline(
    job_id: str,
    duration: int,
    auto_download: bool,
    device_index: int | None = None,
    source: str = "mic",
    playlist: str | None = None,
    uploaded_file_path: Path | None = None,
) -> None:
    """Full async pipeline: record → recognize → search → download."""
    try:
        if source == "uploaded" and uploaded_file_path:
            jobs[job_id].status = "listening"
            jobs[job_id].step = "🎙️ Procesando audio subido..."
            jobs[job_id].progress = 10
            audio_path = uploaded_file_path
        else:
            # ── Step 1: Record ────────────────────────────────────────────────────
            jobs[job_id].status = "listening"
            jobs[job_id].step = f"🎙️ Escuchando {duration} segundos..."
            jobs[job_id].progress = 10

            audio_path = await recorder.record_audio(duration, device=device_index, source=source)

        # ── Step 2: Recognize ─────────────────────────────────────────────────
        jobs[job_id].status = "recognizing"
        jobs[job_id].step = "🔍 Reconociendo canción con Shazam..."
        jobs[job_id].progress = 35

        track = await recognizer.recognize(audio_path)

        if not track:
            jobs[job_id].status = "failed"
            jobs[job_id].step = "❌ No se reconoció ninguna canción."
            jobs[job_id].error = "Shazam no pudo identificar el audio. Intenta de nuevo."
            return

        jobs[job_id].track = track

        if not auto_download:
            jobs[job_id].status = "done"
            jobs[job_id].step = f"✅ Reconocido: {track.artist} - {track.title}"
            jobs[job_id].progress = 100
            return

        # ── Step 3: Search YouTube ─────────────────────────────────────────────
        jobs[job_id].status = "searching"
        jobs[job_id].step = f"🔎 Buscando '{track.artist} - {track.title}' en YouTube..."
        jobs[job_id].progress = 55

        yt_url = await searcher.search_youtube(f"{track.artist} - {track.title}")

        if not yt_url:
            jobs[job_id].status = "failed"
            jobs[job_id].step = "❌ No se encontró la canción en YouTube."
            jobs[job_id].error = "Sin resultados en YouTube para este track."
            return

        # ── Step 4: Download ───────────────────────────────────────────────────
        jobs[job_id].status = "downloading"
        jobs[job_id].step = "⬇️ Descargando MP3 (320 kbps)..."
        jobs[job_id].progress = 70

        def update_progress(p):
            jobs[job_id].progress = p

        file_path = await downloader.download_mp3(yt_url, track, playlist=playlist, progress_callback=update_progress)

        jobs[job_id].status = "done"
        jobs[job_id].file_path = str(file_path)
        jobs[job_id].step = f"✅ Listo: {track.artist} - {track.title}"
        jobs[job_id].progress = 100

    except Exception as exc:
        jobs[job_id].status = "failed"
        jobs[job_id].step = "❌ Error inesperado en el pipeline."
        jobs[job_id].error = str(exc)
