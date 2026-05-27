import yt_dlp
from services.cookies import CookieManager

def main():
    url = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
    ydl_opts = {
        "verbose": True,
        "nocheckcertificate": True,
        "socket_timeout": 15,
        "noplaylist": True,
    }
    ydl_opts.update(CookieManager.get_cookie_opts())
    print("Extracting info...")
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=False)
        print(f"Title: {info.get('title')}")

if __name__ == "__main__":
    main()
