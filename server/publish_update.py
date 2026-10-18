#!/usr/bin/env python3
"""
CyberFort Update Publisher Tool
Packs modified game assets/scripts into update.zip and updates version.json
so clients immediately detect and download the update.
"""

import os
import sys
import json
import zipfile
import hashlib
import argparse
from pathlib import Path
from datetime import date

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE_DIR = Path(__file__).resolve().parent
ROOT_DIR = BASE_DIR.parent
PUBLIC_DIR = BASE_DIR / "public"
DOWNLOADS_DIR = PUBLIC_DIR / "downloads"
VERSION_FILE = PUBLIC_DIR / "version.json"

DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)

# Files and folders to include in the update package
INCLUDE_PATTERNS = ["scenes", "scripts", "project.godot", "icon.svg"]
EXCLUDE_EXTS = [".tmp", ".log", ".pyc", ".git", ".import"]

def calculate_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def publish_update(version: str, version_code: int, title: str, changelog: list, mandatory: bool = False):
    print(f"[*] Packaging update v{version} (Build {version_code})...")
    zip_dest = DOWNLOADS_DIR / "update.zip"

    # Create the zip archive
    file_count = 0
    with zipfile.ZipFile(zip_dest, "w", zipfile.ZIP_DEFLATED) as zf:
        for item in INCLUDE_PATTERNS:
            item_path = ROOT_DIR / item
            if item_path.is_file():
                zf.write(item_path, arcname=item)
                file_count += 1
            elif item_path.is_dir():
                for root, _, files in os.walk(item_path):
                    for file in files:
                        if any(file.endswith(ext) for ext in EXCLUDE_EXTS):
                            continue
                        full_path = Path(root) / file
                        rel_path = full_path.relative_to(ROOT_DIR)
                        zf.write(full_path, arcname=str(rel_path).replace("\\", "/"))
                        file_count += 1

    file_size = zip_dest.stat().st_size
    file_sha256 = calculate_sha256(zip_dest)

    version_data = {
        "version": version,
        "version_code": version_code,
        "release_date": str(date.today()),
        "title": title,
        "changelog": changelog,
        "download_url": "/downloads/update.zip",
        "file_size_bytes": file_size,
        "sha256": file_sha256,
        "mandatory": mandatory
    }

    with open(VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(version_data, f, indent=2, ensure_ascii=False)

    print(f"[+] Successfully bundled {file_count} files into {zip_dest.name} ({round(file_size / 1024, 1)} KB)")
    print(f"[+] Updated version.json to v{version} (Build {version_code})")
    print(f"[+] SHA256: {file_sha256[:16]}...")
    print(f"[+] Update published! All connected clients will now be notified.")
    return version_data

def main():
    parser = argparse.ArgumentParser(description="Publish game update to server")
    parser.add_argument("--version", type=str, default="1.1.0", help="Version name (e.g. 1.1.0)")
    parser.add_argument("--code", type=int, default=2, help="Version build number (e.g. 2)")
    parser.add_argument("--title", type=str, default="تحديث جديد: تحسينات وإصلاحات شاملة", help="Update title")
    parser.add_argument("--notes", nargs="+", default=[
        "إضافة نظام التحديث التلقائي للعبة (Auto-Updater)",
        "ربط اللعبة بسيرفر التحديثات المباشر",
        "إصلاح الاتصال وتحديث واجهة المستخدم"
    ], help="Changelog bullet points")
    parser.add_argument("--mandatory", action="store_true", help="Mark update as required")

    args = parser.parse_args()
    publish_update(
        version=args.version,
        version_code=args.code,
        title=args.title,
        changelog=args.notes,
        mandatory=args.mandatory
    )

if __name__ == "__main__":
    main()
