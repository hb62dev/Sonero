import asyncio
from typing import Optional, List, Dict, Any
import yt_dlp
from services.cookies import CookieManager


async def search_youtube(query: str) -> Optional[str]:
    """
    Searches YouTube for `query` using yt-dlp's ytsearch and returns
    the URL of the first result.
    Runs in a thread to avoid blocking the event loop.
    """

    def _search() -> Optional[str]:
        ydl_opts = {
            "quiet": True,
            "no_warnings": True,
            "extract_flat": True,   # Don't download, just get metadata
            "default_search": "ytsearch1",  # 1 result
            "nocheckcertificate": True,
        }
        ydl_opts.update(CookieManager.get_cookie_opts())
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(f"ytsearch1:{query}", download=False)
                if not info or "entries" not in info or not info["entries"]:
                    return None
                entry = info["entries"][0]
                return f"https://www.youtube.com/watch?v={entry['id']}"
        except Exception:
            return None

    return await asyncio.to_thread(_search)


async def search_youtube_multiple(query: str, limit: int = 20) -> List[Dict[str, Any]]:
    """
    Searches YouTube for `query` and returns a list of results.
    Each result contains title, channel, duration, url, and thumbnails.
    """
    def _search() -> List[Dict[str, Any]]:
        ydl_opts = {
            "quiet": True,
            "no_warnings": True,
            "extract_flat": True,
            "default_search": f"ytsearch{limit}",
            "nocheckcertificate": True,
        }
        ydl_opts.update(CookieManager.get_cookie_opts())
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(f"ytsearch{limit}:{query}", download=False)
                if not info or "entries" not in info:
                    return []
                
                results = []
                for entry in info["entries"]:
                    duration = entry.get("duration")
                    is_short = False
                    if duration is not None and duration <= 60:
                        is_short = True
                    
                    thumbnails = entry.get("thumbnails", [])
                    best_thumbnail = thumbnails[-1]["url"] if thumbnails else None
                    
                    results.append({
                        "id": entry.get("id"),
                        "title": entry.get("title"),
                        "channel": entry.get("uploader"),
                        "duration": duration,
                        "url": entry.get("url"),
                        "thumbnail": best_thumbnail,
                        "is_short": is_short
                    })
                return results
        except Exception as e:
            print(f"Error in search_youtube_multiple: {e}")
            return []

    return await asyncio.to_thread(_search)
