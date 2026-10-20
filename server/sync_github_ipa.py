#!/usr/bin/env python3
"""
GitHub IPA Synchronizer & Release Publisher for CyberFort: Titan Strike 3D
Fetches the latest built IPA from GitHub / Local build, saves it to the website downloads,
updates version.json & game_config.json, and announces the new IPA update to all players.
"""

import os
import sys
import json
import shutil
import urllib.request
from pathlib import Path
from datetime import datetime

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE_DIR = Path(__file__).resolve().parent
PUBLIC_DIR = BASE_DIR / "public"
DOWNLOADS_DIR = PUBLIC_DIR / "downloads"
VERSION_FILE = PUBLIC_DIR / "version.json"
GAME_CONFIG_FILE = PUBLIC_DIR / "game_config.json"

GITHUB_REPO = "Seif796/TitanStrike-iOS"
IPA_FILENAME = "TitanStrike-unsigned.ipa"
TARGET_IPA = DOWNLOADS_DIR / IPA_FILENAME

DESKTOP_PATH = Path.home() / "OneDrive" / "Desktop"
if not DESKTOP_PATH.exists():
    DESKTOP_PATH = Path.home() / "Desktop"

DOWNLOADS_USER_PATH = Path.home() / "Downloads"

def sync_ipa_from_github_or_local():
    print(f"[*] Starting IPA Synchronization for {GITHUB_REPO}...")
    DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)
    
    source_found = None
    source_method = "none"

    # 1. Check local Desktop for freshly generated IPA
    desktop_ipa = DESKTOP_PATH / IPA_FILENAME
    if desktop_ipa.is_file() and desktop_ipa.stat().st_size > 5_000_000:
        source_found = desktop_ipa
        source_method = "local_desktop"
        print(f"[+] Found fresh local IPA on Desktop: {desktop_ipa} ({desktop_ipa.stat().st_size} bytes)")

    # 2. Check Downloads folder
    if not source_found:
        user_dl_ipa = DOWNLOADS_USER_PATH / IPA_FILENAME
        if user_dl_ipa.is_file() and user_dl_ipa.stat().st_size > 5_000_000:
            source_found = user_dl_ipa
            source_method = "local_downloads"
            print(f"[+] Found local IPA in Downloads: {user_dl_ipa}")

    # 3. Check GitHub Releases
    if not source_found:
        try:
            req = urllib.request.Request(
                f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest",
                headers={"User-Agent": "Mozilla/5.0"}
            )
            with urllib.request.urlopen(req, timeout=8) as res:
                rel = json.loads(res.read().decode())
                for asset in rel.get("assets", []):
                    if asset.get("name", "").endswith(".ipa"):
                        dl_url = asset.get("browser_download_url")
                        print(f"[*] Downloading latest IPA from GitHub Release: {dl_url}...")
                        urllib.request.urlretrieve(dl_url, str(TARGET_IPA))
                        source_found = TARGET_IPA
                        source_method = "github_release"
                        break
        except Exception as e:
            print(f"[-] Note: GitHub releases check: {e}")

    # Copy source to target if local
    if source_found and source_found != TARGET_IPA:
        shutil.copy2(source_found, TARGET_IPA)
        print(f"[+] Copied IPA to website downloads: {TARGET_IPA}")

    # Ensure duplicate on Desktop & Downloads
    if TARGET_IPA.is_file():
        try:
            if not desktop_ipa.is_file() or desktop_ipa.stat().st_size != TARGET_IPA.stat().st_size:
                shutil.copy2(TARGET_IPA, desktop_ipa)
                print(f"[+] Duplicated to Desktop: {desktop_ipa}")
        except Exception as e:
            print(f"[-] Duplicate to desktop notice: {e}")

        try:
            target_user_dl = DOWNLOADS_USER_PATH / IPA_FILENAME
            if not target_user_dl.is_file() or target_user_dl.stat().st_size != TARGET_IPA.stat().st_size:
                shutil.copy2(TARGET_IPA, target_user_dl)
                print(f"[+] Duplicated to Downloads: {target_user_dl}")
        except Exception as e:
            print(f"[-] Duplicate to downloads notice: {e}")

    # Update version.json
    v_data = {}
    if VERSION_FILE.is_file():
        try:
            with open(VERSION_FILE, "r", encoding="utf-8") as f:
                v_data = json.load(f)
        except Exception:
            pass

    current_code = int(v_data.get("version_code", 5))
    new_code = current_code + 1
    new_version = f"1.2.{new_code}"

    file_size = TARGET_IPA.stat().st_size if TARGET_IPA.is_file() else 0
    size_mb = round(file_size / (1024 * 1024), 2)

    v_data.update({
        "version": new_version,
        "version_code": new_code,
        "release_date": datetime.now().strftime("%Y-%m-%d"),
        "has_new_ipa": True,
        "requires_ipa": True,
        "ipa_download_url": f"/downloads/{IPA_FILENAME}",
        "ipa_file_size_mb": size_mb,
        "title": "🔥 تحديث جديد متوفر: يرجى تحميل ملف IPA الجديد للايفون",
        "changelog": [
            f"تم تحديث وبناء ملف IPA الجديد للعبة بحجم {size_mb} MB",
            "تحسين المزامنة المباشرة مع سيرفر الزوار ومراقبة حالة الخادم 24/7",
            "جاهز للتثبيت المباشر عبر برنامج Sideloadly أو AltStore أو Scarlet"
        ],
        "mandatory": True
    })

    with open(VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(v_data, f, indent=2, ensure_ascii=False)
    print(f"[+] Updated {VERSION_FILE} to Version {new_version} (Code {new_code})")

    # Update game_config.json announcement
    if GAME_CONFIG_FILE.is_file():
        try:
            with open(GAME_CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            cfg["server_announcement"] = f"🔥 تم إطلاق إصدار جديد (v{new_version})! يرجى تنزيل ملف الـ IPA الجديد من الموقع لتثبيت أحدث الميزات."
            with open(GAME_CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2, ensure_ascii=False)
            print("[+] Updated server announcement in game_config.json")
        except Exception as e:
            print(f"[-] Config announcement notice: {e}")

    return {
        "success": True,
        "version": new_version,
        "version_code": new_code,
        "ipa_size_mb": size_mb,
        "source_method": source_method,
        "ipa_url": f"/downloads/{IPA_FILENAME}",
        "message": f"تم سحب وتحديث ملف IPA الجديد بنجاح (الإصدار v{new_version}) ونشره في الموقع!"
    }

if __name__ == "__main__":
    result = sync_ipa_from_github_or_local()
    print(json.dumps(result, indent=2, ensure_ascii=False))
