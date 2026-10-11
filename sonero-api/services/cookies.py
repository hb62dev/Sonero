from config import settings
from database import SessionLocal
from models import SystemSetting
import yt_dlp

# Browsers yt-dlp can read cookies from
SUPPORTED_BROWSERS = ("brave", "chrome", "chromium", "edge", "firefox", "opera", "safari", "vivaldi")

BROWSER_SETTING_KEY = "cookies_from_browser"


def get_cookie_browser() -> str | None:
    """Browser the user explicitly allowed Sonero to read YouTube cookies from (None = disabled)."""
    db = SessionLocal()
    try:
        record = db.query(SystemSetting).filter(SystemSetting.key == BROWSER_SETTING_KEY).first()
        value = (record.value or "").strip().lower() if record else ""
        return value if value in SUPPORTED_BROWSERS else None
    finally:
        db.close()


def set_cookie_browser(browser: str | None) -> None:
    db = SessionLocal()
    try:
        record = db.query(SystemSetting).filter(SystemSetting.key == BROWSER_SETTING_KEY).first()
        if record is None:
            record = SystemSetting(key=BROWSER_SETTING_KEY)
            db.add(record)
        record.value = browser or ""
        db.commit()
    finally:
        db.close()


def test_browser_cookies(browser: str) -> None:
    """
    Reads the browser's cookie store once. Raises if it can't (browser not
    installed, locked profile, or the user denied keychain access on macOS).
    """
    yt_dlp.cookies.extract_cookies_from_browser(browser)


class CookieManager:
    @staticmethod
    def get_cookie_opts() -> dict:
        """
        Cookie strategy for yt-dlp to avoid YouTube bot detection.
        1. A cookies.txt the user uploaded (tmp/cookies.txt).
        2. The browser the user explicitly enabled in Settings (off by default).
           Reading browser cookies needs keychain access on macOS and exposes
           the whole cookie store to this process, so it is never done
           without the user opting in.
        3. Otherwise no cookies.
        """
        cookie_path = settings.TMP_DIR / "cookies.txt"
        if cookie_path.exists():
            print("[CookieManager] Usando archivo local cookies.txt")
            return {"cookiefile": str(cookie_path)}

        browser = get_cookie_browser()
        if browser:
            print(f"[CookieManager] Usando cookies del navegador elegido por el usuario: {browser}")
            return {"cookiesfrombrowser": (browser,)}

        return {}
