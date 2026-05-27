import asyncio
from shazamio import Shazam
from pathlib import Path

async def main():
    shazam = Shazam()
    try:
        data = await shazam.recognize('test_loopback.wav')
        if "track" in data:
            t = data["track"]
            print(f"SUCCESS: {t.get('subtitle')} - {t.get('title')}")
        else:
            print(f"FAILED: No song recognized. Response keys: {list(data.keys())}")
    except Exception as e:
        print(f"ERROR: {e}")

if __name__ == "__main__":
    asyncio.run(main())
