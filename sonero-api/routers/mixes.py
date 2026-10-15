from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database import get_db
from models import Mix
from services import library_jobs, mixes
from services.library_data import load_library
from services.searcher import search_youtube

router = APIRouter()


def _link_downloaded(db: Session, mix: Mix, songs) -> None:
    """Online songs the user has downloaded since are linked to the library file."""
    changed = False
    for item in mix.items:
        if item.media_id is None and item.title:
            song = mixes._match_library(item.title, item.artist or "", songs)
            if song is not None:
                item.media_id = song.media_id
                mixes.move_rating_to_library(db, item)
                changed = True
    if changed:
        db.commit()


# Order of Sonero's own mixes in "Para ti": most personal first
_KIND_ORDER = ["daily_mix", "discovery", "radio:", "favorites", "time_", "energy", "calm", "genre:",
               "rediscover", "recent", "unplayed"]


def _rank(mix: Mix) -> tuple:
    if mix.source == "agent":
        return (0, -mix.updated_at.timestamp() if mix.updated_at else 0)
    kind = mix.kind or ""
    position = next((i for i, k in enumerate(_KIND_ORDER) if kind == k or (k.endswith((":", "_")) and kind.startswith(k))),
                    len(_KIND_ORDER))
    return (1, position, mix.id)


@router.get("/mixes", summary="Recommended playlists (Sonero's algorithm and AI agents)")
async def list_mixes(db: Session = Depends(get_db)) -> dict:
    rows = sorted(db.query(Mix).all(), key=_rank)
    return {"mixes": [mixes.serialize(m, with_items=False) for m in rows]}


@router.get("/mixes/{mix_id}", summary="A mix with its songs")
async def get_mix(mix_id: int, db: Session = Depends(get_db)) -> dict:
    mix = db.get(Mix, mix_id)
    if mix is None:
        raise HTTPException(status_code=404, detail="Mix no encontrado.")
    songs = load_library(db)
    _link_downloaded(db, mix, songs)
    return mixes.serialize(mix, {s.media_id: s for s in songs})


@router.post("/mixes/generate", summary="Rebuild Sonero's automatic mixes from current data")
async def generate(db: Session = Depends(get_db)) -> dict:
    return await mixes.generate_auto_mixes(db)


@router.delete("/mixes/{mix_id}", summary="Delete a mix (library files are not touched)")
async def delete_mix(mix_id: int, db: Session = Depends(get_db)) -> dict:
    mix = db.get(Mix, mix_id)
    if mix is None:
        raise HTTPException(status_code=404, detail="Mix no encontrado.")
    db.delete(mix)
    db.commit()
    return {"deleted": mix_id}


class RatingRequest(BaseModel):
    rating: Literal[-1, 0, 1] | None  # 1 me gusta, 0 me da igual, -1 no me gusta, null quita la valoración


@router.put("/mixes/{mix_id}/items/{item_id}/rating", summary="Rate a song of a mix (applies to every mix)")
async def rate_item(mix_id: int, item_id: int, body: RatingRequest, db: Session = Depends(get_db)) -> dict:
    mix = db.get(Mix, mix_id)
    item = next((i for i in mix.items if i.id == item_id), None) if mix else None
    if item is None:
        raise HTTPException(status_code=404, detail="Canción no encontrada en el mix.")
    return {"item_id": item_id, "rating": mixes.rate_item(db, mix, item, body.rating)}


@router.post("/mixes/{mix_id}/items/{item_id}/download", summary="Download an online song of a mix as MP3")
async def download_item(mix_id: int, item_id: int, background_tasks: BackgroundTasks,
                        db: Session = Depends(get_db)) -> dict:
    from routers.downloads import Mp3DownloadRequest, download_mp3_direct

    mix = db.get(Mix, mix_id)
    item = next((i for i in mix.items if i.id == item_id), None) if mix else None
    if item is None or not item.title:
        raise HTTPException(status_code=404, detail="Canción no encontrada en el mix.")
    if item.media_id:
        raise HTTPException(status_code=409, detail="Ya está en tu biblioteca.")
    url = await search_youtube(f"{item.artist or ''} - {item.title} audio".strip(" -"))
    if url is None:
        raise HTTPException(status_code=502, detail="No se encontró la canción en YouTube (¿hay internet?).")
    job = await download_mp3_direct(
        Mp3DownloadRequest(url=url, title=item.title, artist=item.artist or ""), background_tasks)
    return {"job_id": job.job_id, "url": url}


# ── Library data quality: metadata and audio analysis ────────────────────────

class ApplyRequest(BaseModel):
    media_ids: list[int]


@router.post("/library/enrich", summary="Look up missing artist/album/genre/year online")
async def enrich_start() -> dict:
    library_jobs.start_enrichment()
    return library_jobs.enrichment.to_dict()


@router.get("/library/enrich", summary="Enrichment progress and proposals to review")
async def enrich_status() -> dict:
    return {**library_jobs.enrichment.to_dict(), "proposals": library_jobs.enrichment.results}


@router.post("/library/enrich/apply", summary="Save the reviewed metadata proposals")
async def enrich_apply(body: ApplyRequest) -> dict:
    return library_jobs.apply_enrichment(body.media_ids)


@router.post("/library/analyze", summary="Analyze BPM/energy of songs not analyzed yet")
async def analyze_start(force: bool = False) -> dict:
    if not library_jobs.analysis_available():
        raise HTTPException(status_code=501, detail="El análisis de audio necesita la librería librosa "
                                                    "(pip install -r requirements-audio.txt).")
    library_jobs.start_analysis(force=force)
    return library_jobs.analysis.to_dict()


@router.get("/library/analyze", summary="Audio analysis progress")
async def analyze_status() -> dict:
    return {**library_jobs.analysis.to_dict(), "available": library_jobs.analysis_available()}
