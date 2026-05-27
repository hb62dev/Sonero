import sys
from pathlib import Path
from config import settings
import yt_dlp

class CookieManager:
    @staticmethod
    def get_cookie_opts() -> dict:
        """
        Determines the best cookie strategy to bypass YouTube bot detection.
        1. Checks for local tmp/cookies.txt (from manual upload or Benrio).
        2. On Windows, scans installed browsers (Brave, Chrome, Edge, Firefox)
           and returns the first one that successfully extracts cookies.
        3. Returns empty dict if nothing works.
        """
        # 1. Check local file (highest priority)
        cookie_path = settings.TMP_DIR / "cookies.txt"
        if cookie_path.exists():
            print("[CookieManager] Usando archivo local cookies.txt")
            return {"cookiefile": str(cookie_path)}

        # 2. Check browsers (only on desktop OS like Windows)
        if sys.platform in ["win32", "darwin", "linux"]:
            browsers_to_try = ["brave", "chrome", "edge", "firefox", "opera"]
            
            for browser in browsers_to_try:
                try:
                    # Attempt to extract cookies to see if the browser has them.
                    # This will throw an exception if the browser is not installed
                    # or if the cookie database is locked/empty.
                    # We just test the extraction, we don't keep the jar.
                    yt_dlp.cookies.extract_cookies_from_browser(browser)
                    print(f"[CookieManager] Cookies encontradas en el navegador: {browser}")
                    return {"cookiesfrombrowser": (browser,)}
                except Exception as e:
                    # Ignore and try the next browser
                    continue

        print("[CookieManager] No se encontraron cookies válidas. Procediendo limpio.")
        return {}
