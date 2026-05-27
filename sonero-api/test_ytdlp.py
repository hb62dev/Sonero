import asyncio
from services.downloader import download_video
from config import settings

async def main():
    settings.VIDEO_DIR.mkdir(parents=True, exist_ok=True)
    def prog(p):
        print(f"Progress: {p}%")
    
    print("Testing Video Download...")
    try:
        # A short creative commons video
        path, warn = await download_video("https://www.youtube.com/watch?v=aqz-KE-bpKQ", "bestvideo+bestaudio", progress_callback=prog)
        print(f"Video download success: {path}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    asyncio.run(main())
