from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from services import tv_server

router = APIRouter()


class EnableRequest(BaseModel):
    enabled: bool


@router.get("/tv/status", summary="Sonero TV status, pairing PIN and paired devices")
async def tv_status() -> dict:
    return tv_server.status()


@router.put("/tv/enabled", summary="Turn the Sonero TV server on/off (persists across restarts)")
async def tv_enable(body: EnableRequest) -> dict:
    try:
        await tv_server.set_enabled(body.enabled)
    except RuntimeError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return tv_server.status()


@router.post("/tv/pairing", summary="Open a 5-minute pairing window and get its PIN")
async def tv_pairing_start() -> dict:
    if not tv_server.state.running:
        raise HTTPException(status_code=409, detail="Activa Sonero TV antes de emparejar.")
    tv_server.start_pairing()
    return tv_server.status()


@router.delete("/tv/pairing", summary="Close the pairing window")
async def tv_pairing_cancel() -> dict:
    tv_server.cancel_pairing()
    return tv_server.status()


@router.delete("/tv/devices/{device_id}", summary="Revoke a paired TV")
async def tv_revoke(device_id: str) -> dict:
    if not tv_server.revoke_device(device_id):
        raise HTTPException(status_code=404, detail="Dispositivo no encontrado.")
    return tv_server.status()


@router.post("/tv/devices/{device_id}/command", summary="Control a connected TV (play a queue, pause, next, volume…)")
async def tv_command(device_id: str, cmd: tv_server.TvCommand) -> dict:
    return await tv_server.send_command(device_id, cmd)
