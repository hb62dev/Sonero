import asyncio
from pathlib import Path
from typing import Literal

import sys
import numpy as np

try:
    import sounddevice as sd
    import soundfile as sf
except ImportError:
    sd = None
    sf = None

from config import settings

AudioSource = Literal["mic", "system"]


# ── Device helpers ────────────────────────────────────────────────────────────

def list_devices() -> list[dict]:
    """Returns all available audio input devices, deduplicated and cleaned."""
    if sd is None:
        return []

    devices = sd.query_devices()
    unique_devices = {}

    for i, d in enumerate(devices):
        if d["max_input_channels"] > 0:
            name = d["name"].strip()
            
            # Omit internal Windows virtual devices that clutter the list
            if "@System" in name or "AMDAfdInstall" in name:
                continue
                
            # Deduplicate by name. The first one found is usually the MME host API
            # which is what we want.
            if name not in unique_devices:
                unique_devices[name] = {
                    "index": i,
                    "name": name,
                    "channels": d["max_input_channels"]
                }
                
    return sorted(unique_devices.values(), key=lambda x: x["index"])


def _find_wasapi_loopback_device() -> int:
    """
    Finds the WASAPI loopback device for the default output (speakers/headphones).
    This allows capturing any audio playing through the OS — browser, Spotify, etc.
    Returns the device index to pass to sounddevice.
    Raises RuntimeError if WASAPI is not available.
    """
    if sd is None:
        raise RuntimeError("Audio modules are not available on this platform.")

    # Locate the WASAPI host API
    wasapi_hostapi = None
    for i, api in enumerate(sd.query_hostapis()):
        if "WASAPI" in api["name"]:
            wasapi_hostapi = i
            break

    if wasapi_hostapi is None:
        raise RuntimeError(
            "WASAPI is not available on this system. "
            "System audio capture requires Windows with WASAPI support."
        )

    # Find the default output device (speakers/headphones)
    default_output_idx = sd.default.device[1]
    devices = sd.query_devices()

    # If the default output is already WASAPI, use it directly
    if devices[default_output_idx]["hostapi"] == wasapi_hostapi:
        return default_output_idx

    # Otherwise find any WASAPI output device
    for i, d in enumerate(devices):
        if d["hostapi"] == wasapi_hostapi and d["max_output_channels"] > 0:
            return i

    raise RuntimeError(
        "No WASAPI output device found. "
        "Check that your audio drivers support WASAPI (standard on Windows 7+)."
    )


# ── Recording ─────────────────────────────────────────────────────────────────

async def record_audio(
    duration: int = 10,
    device: int | None = None,
    source: AudioSource = "mic",
) -> Path:
    """
    Records audio for `duration` seconds and saves it as a WAV file.

    Source modes:
      - "mic"    → Physical microphone (default). Device priority:
                   1. `device` argument  2. AUDIO_DEVICE in .env  3. System default
      - "system" → WASAPI loopback — captures any audio playing on the OS
                   (browser, Spotify, YouTube, system sounds, etc.)
                   No physical microphone required.

    Returns the path to the recorded WAV file.
    """
    settings.TMP_DIR.mkdir(exist_ok=True)
    output_path = settings.TMP_DIR / "recording.wav"

    if source == "system":
        await asyncio.to_thread(_record_system, output_path, duration)
    else:
        resolved_device = device if device is not None else settings.AUDIO_DEVICE
        await asyncio.to_thread(_record_mic, output_path, duration, resolved_device)

    return output_path


def _get_reliable_default_mic() -> int | None:
    """Finds the most reliable default microphone index (DirectSound) instead of MME."""
    if sd is None: return None
    try:
        hostapis = sd.query_hostapis()
        # Prefer DirectSound (extremely stable for microphones on Windows)
        for api in hostapis:
            if "DirectSound" in api["name"] and api["default_input_device"] >= 0:
                return api["default_input_device"]
        # Fallback to WASAPI
        for api in hostapis:
            if "WASAPI" in api["name"] and api["default_input_device"] >= 0:
                return api["default_input_device"]
    except Exception:
        pass
    return None


def _record_mic(output_path: Path, duration: int, device: int | None) -> None:
    """Records from a physical microphone input device."""
    if sd is None or sf is None:
        raise RuntimeError("Mic recording is not supported natively on this platform without permissions.")

    devices_to_try = []
    if device is not None:
        devices_to_try.append(device)
        
    default_mic = _get_reliable_default_mic()
    if default_mic is not None and default_mic not in devices_to_try:
        devices_to_try.append(default_mic)
        
    for dev in list_devices():
        if dev["index"] not in devices_to_try:
            devices_to_try.append(dev["index"])

    last_error = None
    
    for dev_idx in devices_to_try:
        try:
            recording = sd.rec(
                int(duration * settings.SAMPLE_RATE),
                samplerate=settings.SAMPLE_RATE,
                channels=settings.CHANNELS,
                dtype="float32",
                device=dev_idx,
            )
            sd.wait()
            sf.write(str(output_path), recording, settings.SAMPLE_RATE)
            return
        except Exception as e:
            last_error = e
            continue
            
    if last_error:
        error_msg = str(last_error)
        if "Unanticipated host error" in error_msg or "-9999" in error_msg:
            raise RuntimeError(
                "No se pudo acceder a ningún micrófono. Verifica que estén conectados y que "
                "Windows les dé permisos (Configuración > Privacidad > Micrófono)."
            )
        raise RuntimeError(f"Error grabando audio: {error_msg}")


def _record_system(output_path: Path, duration: int) -> None:
    """
    Records system audio via WASAPI loopback using pyaudiowpatch.
    Captures everything playing through the default output device
    (speakers, headphones, HDMI audio, etc.).
    Works with browsers, media players, Spotify, YouTube — any audio source.
    Does NOT require Stereo Mix to be enabled in Windows settings.
    """
    if sys.platform != "win32":
        raise RuntimeError("System loopback audio capture is only supported on Windows.")

    import pyaudiowpatch as pyaudio

    p = pyaudio.PyAudio()
    try:
        # Find the default WASAPI loopback device (speakers/headphones output)
        wasapi_info = p.get_host_api_info_by_type(pyaudio.paWASAPI)
        default_out_idx = wasapi_info["defaultOutputDevice"]
        default_out = p.get_device_info_by_index(default_out_idx)

        # Get the loopback version of the default output device
        loopback_device = None
        for i in range(p.get_device_count()):
            dev = p.get_device_info_by_index(i)
            if (
                dev.get("isLoopbackDevice", False)
                and default_out["name"] in dev["name"]
            ):
                loopback_device = dev
                break

        # Fallback: use first available loopback device
        if loopback_device is None:
            for i in range(p.get_device_count()):
                dev = p.get_device_info_by_index(i)
                if dev.get("isLoopbackDevice", False):
                    loopback_device = dev
                    break

        if loopback_device is None:
            raise RuntimeError(
                "No WASAPI loopback device found. "
                "Ensure your audio drivers support WASAPI (standard on Windows 7+)."
            )

        sample_rate   = int(loopback_device["defaultSampleRate"])
        channels      = min(int(loopback_device["maxInputChannels"]), 2)
        frames_needed = int(sample_rate * duration)
        chunk         = 1024
        frames        = []

        stream = p.open(
            format=pyaudio.paFloat32,
            channels=channels,
            rate=sample_rate,
            input=True,
            input_device_index=int(loopback_device["index"]),
            frames_per_buffer=chunk,
        )

        collected = 0
        while collected < frames_needed:
            data = stream.read(min(chunk, frames_needed - collected), exception_on_overflow=False)
            frames.append(np.frombuffer(data, dtype=np.float32).copy())
            collected += chunk

        stream.stop_stream()
        stream.close()

        audio = np.concatenate(frames)
        if channels > 1:
            audio = audio.reshape(-1, channels).mean(axis=1)  # stereo → mono

        sf.write(str(output_path), audio, sample_rate)

    finally:
        p.terminate()



