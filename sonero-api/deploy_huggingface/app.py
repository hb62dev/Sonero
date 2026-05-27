import os
import shutil
import tempfile
from pathlib import Path
from typing import Optional
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from shazamio import Shazam
from pydantic import BaseModel

app = FastAPI(title="Sonero Shazam Proxy API")

# Enable CORS for mobile app connectivity
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class TrackInfo(BaseModel):
    title: str
    artist: str
    album: Optional[str] = None
    cover_url: Optional[str] = None
    genre: Optional[str] = None
    year: Optional[str] = None
    shazam_url: Optional[str] = None
    track_key: Optional[str] = None

@app.get("/")
def read_root():
    return {"status": "running", "service": "Sonero Shazam Proxy"}

@app.post("/recognize", response_model=TrackInfo)
async def recognize_audio(file: UploadFile = File(...)):
    # Create a temporary file to save the uploaded WAV bytes
    temp_dir = Path(tempfile.gettempdir())
    temp_path = temp_dir / f"shazam_{os.urandom(8).hex()}.wav"
    
    try:
        with temp_path.open("wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        shazam = Shazam()
        data = await shazam.recognize(str(temp_path))
        
        if "track" not in data:
            raise HTTPException(status_code=404, detail="No track found")
            
        track = data["track"]
        
        # Cover image
        cover_url = None
        images = track.get("images", {})
        cover_url = images.get("coverarthq") or images.get("coverart")
        
        # Genre
        genre = None
        genres = track.get("genres", {})
        genre = genres.get("primary")
        
        # Year & Album from metadata sections
        year = None
        album = None
        for section in track.get("sections", []):
            if section.get("type") == "SONG":
                for meta in section.get("metadata", []):
                    title = meta.get("title", "").lower()
                    if title == "released":
                        year = meta.get("text")
                    elif title == "album":
                        album = meta.get("text")
                        
        return TrackInfo(
            title=track.get("title", "Unknown"),
            artist=track.get("subtitle", "Unknown"),
            album=album,
            cover_url=cover_url,
            genre=genre,
            year=year,
            shazam_url=track.get("url"),
            track_key=track.get("key"),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Clean up temporary WAV file
        if temp_path.exists():
            try:
                temp_path.unlink()
            except Exception:
                pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7860)
