from fastapi import APIRouter, HTTPException
from services.recorder import list_devices
from config import settings

router = APIRouter()


@router.get(
    "/devices",
    summary="List available audio input devices",
    description=(
        "Returns all audio input devices on the system. "
        "Use the index to set `AUDIO_DEVICE` in `.env` or via `POST /devices/select`.\n\n"
        "**TIP:** Use **'Stereo Mix'** to capture audio playing through PC speakers "
        "without needing a physical microphone."
    ),
)
async def get_devices() -> dict:
    devices = list_devices()
    current = settings.AUDIO_DEVICE
    return {
        "current_device": current,
        "current_device_name": (
            next((d["name"] for d in devices if d["index"] == current), "System default")
            if current is not None else "System default"
        ),
        "devices": devices,
    }


@router.post(
    "/devices/select/{device_index}",
    summary="Select audio input device for this session",
    description=(
        "Temporarily sets the audio input device for the current server session. "
        "Use `GET /devices` to find the correct index.\n\n"
        "For a permanent change, set `AUDIO_DEVICE=<index>` in the `.env` file."
    ),
)
async def select_device(device_index: int) -> dict:
    devices = list_devices()
    match = next((d for d in devices if d["index"] == device_index), None)
    if not match:
        raise HTTPException(status_code=404, detail=f"Device index {device_index} not found.")

    # Temporarily override at runtime (no restart needed)
    settings.AUDIO_DEVICE = device_index
    return {
        "message": f"Audio device set to [{device_index}] {match['name']}",
        "device_index": device_index,
        "device_name": match["name"],
        "tip": "This change lasts until the server restarts. Add AUDIO_DEVICE={} to .env for persistence.".format(device_index),
    }
