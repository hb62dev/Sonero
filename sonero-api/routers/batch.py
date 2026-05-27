import csv
import io
import uuid
from typing import Dict
from fastapi import APIRouter, BackgroundTasks, UploadFile, File, HTTPException

from schemas.jobs import BatchJobStatus, JobResponse
from schemas.song import TrackInfo
from services import searcher, downloader

router = APIRouter()

# In-memory store for batch jobs
batch_jobs: Dict[str, BatchJobStatus] = {}


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post(
    "/batch/from-csv",
    response_model=JobResponse,
    summary="Download full Shazam library from CSV",
    description=(
        "Upload the `shazamlibrary.csv` exported from the Shazam app. "
        "The API reads each song, searches YouTube, and downloads it as MP3. "
        "Returns a `job_id` to track progress."
    ),
)
async def batch_from_csv(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(..., description="CSV exported from Shazam app"),
) -> JobResponse:
    if not file.filename.endswith(".csv"):
        raise HTTPException(status_code=400, detail="El archivo debe ser un .csv")

    content = await file.read()
    text = content.decode("utf-8", errors="replace")

    job_id = str(uuid.uuid4())[:8]
    batch_jobs[job_id] = BatchJobStatus(
        job_id=job_id,
        status="pending",
        current="⏳ Preparando...",
    )

    background_tasks.add_task(_run_batch, job_id, text)

    return JobResponse(
        job_id=job_id,
        status="pending",
        message="Batch iniciado. Usa /batch/jobs/{job_id} para ver el progreso.",
    )


@router.get(
    "/batch/jobs/{job_id}",
    response_model=BatchJobStatus,
    summary="Get batch job progress",
)
async def get_batch_job(job_id: str) -> BatchJobStatus:
    if job_id not in batch_jobs:
        raise HTTPException(status_code=404, detail=f"Batch job '{job_id}' no encontrado.")
    return batch_jobs[job_id]


@router.get(
    "/batch/jobs",
    response_model=list[BatchJobStatus],
    summary="List all batch jobs",
)
async def list_batch_jobs() -> list[BatchJobStatus]:
    return list(batch_jobs.values())


# ── Batch logic ───────────────────────────────────────────────────────────────

def _parse_csv(csv_content: str) -> list[dict]:
    """
    Parses the Shazam library CSV format:
      Row 0: "Shazam Library" (skip)
      Row 1: headers — Index, TagTime, Title, Artist, URL, TrackKey
      Row 2+: data
    """
    reader = csv.reader(io.StringIO(csv_content))
    rows = list(reader)

    songs = []
    for row in rows[2:]:  # skip first two header rows
        if not row or not row[0].strip().isdigit():
            continue
        songs.append({
            "index": row[0],
            "title": row[2] if len(row) > 2 else "",
            "artist": row[3] if len(row) > 3 else "",
        })
    return songs


async def _run_batch(job_id: str, csv_content: str) -> None:
    """Processes each song from the CSV: search YouTube → download MP3."""
    try:
        songs = _parse_csv(csv_content)

        batch_jobs[job_id].total = len(songs)
        batch_jobs[job_id].status = "running"

        for song in songs:
            query = f"{song['artist']} - {song['title']}"
            batch_jobs[job_id].current = f"🔎 {query}"

            try:
                yt_url = await searcher.search_youtube(query)
                if not yt_url:
                    batch_jobs[job_id].failed += 1
                    batch_jobs[job_id].errors.append(f"No encontrado en YouTube: {query}")
                    continue

                track = TrackInfo(title=song["title"], artist=song["artist"])
                await downloader.download_mp3(yt_url, track)
                batch_jobs[job_id].completed += 1

            except Exception as exc:
                batch_jobs[job_id].failed += 1
                batch_jobs[job_id].errors.append(f"Error en '{query}': {str(exc)}")

        batch_jobs[job_id].status = "done"
        done = batch_jobs[job_id].completed
        failed = batch_jobs[job_id].failed
        batch_jobs[job_id].current = f"✅ Completado: {done} descargadas, {failed} fallidas."

    except Exception as exc:
        batch_jobs[job_id].status = "failed"
        batch_jobs[job_id].current = f"❌ Error fatal: {str(exc)}"
