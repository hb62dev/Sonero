from fastapi import APIRouter, Query, HTTPException
from typing import List, Dict, Any
from services.searcher import search_youtube_multiple

router = APIRouter()

@router.get("/search")
async def search_online(q: str = Query(..., min_length=1), limit: int = Query(20, ge=1, le=50)) -> List[Dict[str, Any]]:
    """
    Searches YouTube for the given query and returns a list of results.
    """
    try:
        results = await search_youtube_multiple(q, limit)
        return results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
