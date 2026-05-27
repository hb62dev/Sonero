import asyncio
from services.downloader import get_video_info

async def main():
    print("Fetching info...")
    info = await get_video_info("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    print("Done:", info["title"])

if __name__ == "__main__":
    asyncio.run(main())
