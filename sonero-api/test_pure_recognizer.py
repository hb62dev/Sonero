import asyncio
from pathlib import Path
from services.recognizer import recognize

async def main():
    path = Path("test_loopback.wav")
    print("Testing pure Python recognizer on test_loopback.wav...")
    track = await recognize(path)
    if track:
        print(f"SUCCESS: {track.artist} - {track.title}")
    else:
        print("FAILED: Recognition failed using pure Python signature.")

if __name__ == "__main__":
    asyncio.run(main())
