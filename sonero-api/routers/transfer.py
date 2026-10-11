from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from config import settings
from services import wifi_transfer as wt

router = APIRouter()


class SendFile(BaseModel):
    filename: str = Field(..., description="Library filename as returned by GET /downloads")
    title: str = ""
    artist: str = ""
    album: str = ""
    genre: str = ""
    year: str = ""


class SendRequest(BaseModel):
    target_ip: str
    port: int = Field(default=8090, ge=1, le=65535)
    files: list[SendFile] = Field(..., min_length=1)


def _status() -> dict:
    ips = wt.get_lan_ips()
    ip = ips[0] if ips else None
    port = settings.TRANSFER_PORT
    by_time = lambda items: sorted(items.values(), key=lambda i: i.get("updated_at", 0))
    return {
        "receiving": wt.state.receiving,
        "sending": wt.state.sending,
        "ip": ip,
        "ips": ips,
        "port": port,
        "upload_url": f"http://{ip}:{port}" if ip else None,
        "receive": by_time(wt.state.receive_items),
        "send": by_time(wt.state.send_items),
    }


@router.get("/transfer/status", summary="WiFi transfer status, LAN IP and progress")
async def transfer_status() -> dict:
    return _status()


@router.post("/transfer/receive/start", summary="Open the WiFi receiver on the LAN")
async def receive_start() -> dict:
    try:
        await wt.start_receiver()
    except RuntimeError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return _status()


@router.post("/transfer/receive/stop", summary="Close the WiFi receiver")
async def receive_stop() -> dict:
    await wt.stop_receiver()
    return _status()


@router.post("/transfer/send", summary="Send library files to another Sonero device")
async def send(body: SendRequest) -> dict:
    target_ip = wt.validate_target_ip(body.target_ip)
    files = []
    for f in body.files:
        path, file_type, playlist = wt.resolve_library_file(f.filename)
        files.append({"path": path, "type": file_type, "playlist": playlist, **f.model_dump(exclude={"filename"})})
    wt.start_sending(target_ip, body.port, files)
    return _status()


@router.post("/transfer/clear", summary="Remove finished items from the progress lists")
async def clear() -> dict:
    wt.clear_finished()
    return _status()
