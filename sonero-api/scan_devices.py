"""Test all audio input devices and report RMS level."""
import sounddevice as sd
import numpy as np

print("Testing all input devices (2s each) - play audio or speak now!")
print("-" * 70)

devices = [(i, d) for i, d in enumerate(sd.query_devices()) if d["max_input_channels"] > 0]

for idx, d in devices:
    try:
        r = sd.rec(2 * 44100, samplerate=44100, channels=1, dtype="float32", device=idx)
        sd.wait()
        rms = float(np.sqrt(np.mean(r ** 2)))
        status = "<-- AUDIO DETECTED!" if rms > 0.001 else "silent"
        name = d["name"][:48]
        print(f"  [{idx:2d}] {name:<48s}  RMS={rms:.5f}  {status}")
    except Exception as e:
        name = d["name"][:48]
        print(f"  [{idx:2d}] {name:<48s}  ERROR: {e}")

print("-" * 70)
print("Use the index of a device with AUDIO DETECTED as your AUDIO_DEVICE in .env")
