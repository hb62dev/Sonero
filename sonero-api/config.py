import os
import sys
from pathlib import Path
from pydantic_settings import BaseSettings


def _get_data_dir() -> Path:
    """
    Returns the writable data directory for Sonero.
    - When running as a PyInstaller bundle (installed): %APPDATA%/Sonero
    - When running in development (python main.py):     ./  (next to main.py)
    """
    if getattr(sys, 'frozen', False):
        # Running as PyInstaller exe → use AppData
        return Path(os.environ.get("APPDATA", "~")) / "Sonero"
    else:
        # Development mode → use the project directory
        return Path(__file__).parent


class Settings(BaseSettings):
    # Directories
    BASE_DIR: Path = _get_data_dir()
    MUSIC_DIR: Path = BASE_DIR / "downloads"
    VIDEO_DIR: Path = BASE_DIR / "downloads" / "videos"
    TMP_DIR: Path = BASE_DIR / "tmp"
    RESULTS_DIR: Path = BASE_DIR / "results"

    # Audio recording
    SAMPLE_RATE: int = 44100
    CHANNELS: int = 1
    DEFAULT_LISTEN_DURATION: int = 10  # seconds
    # Audio device index (None = system default).
    # Run: venv\Scripts\python debug_recognition.py to list devices.
    # Use 16 for 'Stereo Mix' (captures PC speaker output directly).
    AUDIO_DEVICE: int | None = None

    # Server
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # Download format preference (no FFmpeg needed)
    AUDIO_FORMAT: str = "m4a"  # m4a = AAC, no conversion required

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
