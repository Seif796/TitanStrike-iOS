#!/usr/bin/env python3
"""
CyberFort Update Publisher Tool
- Automatically re-exports build/TitanStrike.pck using Godot 4.3 stable if available.
- Publishes update.pck and update.zip to server downloads and public downloads.
- Updates TitanStrike.ipa with latest PCK.
- Bundles TitanStrike-Mobile-Bundle.zip.
- Copies all fresh artifacts to Desktop.
- Updates version.json with new version, build code, SHA256, and size.
"""

import os
import sys
import json
import zipfile
import hashlib
import shutil
import subprocess
import argparse
from pathlib import Path
from datetime import date

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE_DIR = Path(__file__).resolve().parent
ROOT_DIR = BASE_DIR.parent
PUBLIC_DIR = BASE_DIR / "public"
DOWNLOADS_DIR = PUBLIC_DIR / "downloads"
ROOT_DOWNLOADS_DIR = ROOT_DIR / "public" / "downloads"
VERSION_FILE = PUBLIC_DIR / "version.json"
ROOT_VERSION_FILE = ROOT_DIR / "public" / "version.json"

DESKTOP_DIRS = [
    Path(os.environ.get("USERPROFILE", "C:/Users/Administrator")) / "Desktop",
    Path(os.environ.get("USERPROFILE", "C:/Users/Administrator")) / "OneDrive" / "Desktop"
]

DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)
ROOT_DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)

def calculate_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def export_pck():
    godot_exe = ROOT_DIR / "Godot_v4.3-stable_win64_console.exe"
    pck_dest = ROOT_DIR / "build" / "TitanStrike.pck"
    pck_dest.parent.mkdir(parents=True, exist_ok=True)

    if godot_exe.is_file():
        print(f"[*] Compiling latest PCK via Godot 4.3...")
        cmd = [str(godot_exe), "--headless", "--export-pack", "iOS", str(pck_dest)]
        res = subprocess.run(cmd, cwd=str(ROOT_DIR), capture_output=True, text=True)
        if res.returncode == 0 and pck_dest.is_file():
            print(f"[+] Compiled PCK: {pck_dest.stat().st_size} bytes")
        else:
            print(f"[!] Warning: Godot export returned code {res.returncode}")
    else:
        print(f"[*] Using existing PCK at {pck_dest}")
    return pck_dest

def inject_pck_into_ipa(ipa_path: Path, pck_path: Path):
    if not ipa_path.is_file() or not pck_path.is_file():
        return False
    temp_ipa = ipa_path.with_suffix(".tmp")
    try:
        with zipfile.ZipFile(ipa_path, "r") as zin, zipfile.ZipFile(temp_ipa, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                if item.filename == "Payload/TitanStrike.app/TitanStrike.pck":
                    zout.write(pck_path, arcname=item.filename)
                else:
                    zout.writestr(item, zin.read(item.filename))
        shutil.move(temp_ipa, ipa_path)
        print(f"[+] Injected fresh PCK into {ipa_path.name}")
        return True
    except Exception as e:
        print(f"[!] Error injecting PCK into IPA: {e}")
        if temp_ipa.exists():
            temp_ipa.unlink()
        return False

def publish_update(version: str, version_code: int, title: str, changelog: list, mandatory: bool = True):
    print(f"[*] Packaging update v{version} (Build {version_code})...")
    
    # 1. Export fresh PCK
    pck_source = export_pck()
    if not pck_source.is_file():
        raise FileNotFoundError(f"PCK not found at {pck_source}")
    
    # 2. Copy PCK to server downloads and public downloads
    pck_dest = DOWNLOADS_DIR / "update.pck"
    shutil.copy2(pck_source, pck_dest)
    shutil.copy2(pck_source, ROOT_DOWNLOADS_DIR / "update.pck")
    print(f"[+] Published update.pck ({round(pck_dest.stat().st_size / (1024*1024), 2)} MB)")
    
    # 3. Create zip fallback archive containing PCK and scenes/scripts
    zip_dest = DOWNLOADS_DIR / "update.zip"
    with zipfile.ZipFile(zip_dest, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(pck_source, arcname="TitanStrike.pck")
        # Also include scenes and scripts for maximum backward-compatibility
        for folder in ["scenes", "scripts"]:
            f_path = ROOT_DIR / folder
            if f_path.is_dir():
                for root, _, files in os.walk(f_path):
                    for file in files:
                        full_path = Path(root) / file
                        rel_path = full_path.relative_to(ROOT_DIR)
                        zf.write(full_path, arcname=str(rel_path).replace("\\", "/"))
    shutil.copy2(zip_dest, ROOT_DOWNLOADS_DIR / "update.zip")
    print(f"[+] Published update.zip ({round(zip_dest.stat().st_size / (1024*1024), 2)} MB)")
    
    # 4. Update TitanStrike.ipa in downloads and desktops
    ipa_candidates = [
        DOWNLOADS_DIR / "TitanStrike.ipa",
        ROOT_DOWNLOADS_DIR / "TitanStrike.ipa"
    ]
    for d_dir in DESKTOP_DIRS:
        if d_dir.exists():
            ipa_candidates.append(d_dir / "TitanStrike.ipa")
    
    for ipa_f in set(ipa_candidates):
        if ipa_f.is_file():
            inject_pck_into_ipa(ipa_f, pck_source)
    
    # 5. Update bundle zip
    apk_file = DOWNLOADS_DIR / "TitanStrike.apk"
    ipa_file = DOWNLOADS_DIR / "TitanStrike.ipa"
    bundle_dest = DOWNLOADS_DIR / "TitanStrike-Mobile-Bundle.zip"
    if apk_file.is_file() and ipa_file.is_file():
        with zipfile.ZipFile(bundle_dest, "w", zipfile.ZIP_DEFLATED) as bzf:
            bzf.write(apk_file, arcname="TitanStrike.apk")
            bzf.write(ipa_file, arcname="TitanStrike.ipa")
        shutil.copy2(bundle_dest, ROOT_DOWNLOADS_DIR / "TitanStrike-Mobile-Bundle.zip")
        print(f"[+] Updated TitanStrike-Mobile-Bundle.zip")
    
    # 6. Copy all binaries to desktops
    for d_dir in DESKTOP_DIRS:
        if d_dir.exists():
            for fname in ["TitanStrike.apk", "TitanStrike.ipa", "TitanStrike-Mobile-Bundle.zip", "update.pck", "update.zip"]:
                src = DOWNLOADS_DIR / fname
                if src.is_file():
                    shutil.copy2(src, d_dir / fname)
            print(f"[+] Synced fresh game binaries to {d_dir}")
    # Create Admin Manager shortcut on Desktop
    url_content = f"""[InternetShortcut]
URL=http://localhost:8080/admin
IconIndex=0
"""
    for d_dir in DESKTOP_DIRS:
        if d_dir.exists():
            try:
                with open(d_dir / "Admin-Manager.url", "w", encoding="utf-8") as uf:
                    uf.write(url_content)
                print(f"[+] Created Admin-Manager shortcut on {d_dir}")
            except Exception as e:
                pass

    
    # 7. Write version.json
    pck_size = pck_dest.stat().st_size
    pck_sha256 = calculate_sha256(pck_dest)
    
    version_data = {
        "version": version,
        "version_code": version_code,
        "release_date": str(date.today()),
        "title": title,
        "changelog": changelog,
        "download_url": "/downloads/update.pck",
        "file_size_bytes": pck_size,
        "sha256": pck_sha256,
        "mandatory": mandatory
    }
    
    with open(VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(version_data, f, indent=2, ensure_ascii=False)
    with open(ROOT_VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(version_data, f, indent=2, ensure_ascii=False)
        
    print(f"[+] Updated version.json -> v{version} (Build {version_code})")
    print(f"[+] Update published successfully!")
    return version_data

def main():
    parser = argparse.ArgumentParser(description="Publish game update to server")
    parser.add_argument("--version", type=str, default="1.3.1", help="Version name")
    parser.add_argument("--code", type=int, default=7, help="Version build code")
    parser.add_argument("--title", type=str, default="🚀 تحديث مباشر v1.3.1: دعم فوري للأندرويد والآيفون", help="Update title")
    parser.add_argument("--notes", nargs="+", default=[
        "تحديث مباشر وفوري عبر السيرفر لجميع الأجهزة",
        "إضافة زر الطلبات (Requests) وزر تيليجرام بوت في القائمة الرئيسية",
        "تحسين استقرار المحرك على أندرويد وآيفون"
    ], help="Changelog notes")
    parser.add_argument("--mandatory", action="store_true", default=True, help="Mandatory update")
    
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
