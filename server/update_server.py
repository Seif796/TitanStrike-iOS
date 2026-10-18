#!/usr/bin/env python3
"""
CyberFort Game Update Server (OTA Auto-Patcher)
Serves game version metadata and downloadable patch packages (.zip / .pck)
for mobile (iOS / Android) and PC clients.
"""

import http.server
import socketserver
import os
import sys
import json
import socket
import urllib.parse
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PORT = 8080
BASE_DIR = Path(__file__).resolve().parent
PUBLIC_DIR = BASE_DIR / "public"
DOWNLOADS_DIR = PUBLIC_DIR / "downloads"
VERSION_FILE = PUBLIC_DIR / "version.json"

DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)

# Default version data if none exists
DEFAULT_VERSION_DATA = {
    "version": "1.0.0",
    "version_code": 1,
    "release_date": "2026-10-18",
    "title": "إصدار الإطلاق الرسمي (Official Launch)",
    "changelog": [
        "إضافة نظام الحسابات (Sign In / Sign Up / Sign Out)",
        "إضافة طور اللعب الفردي وطور الأونلاين",
        "إضافة قائمة الأصدقاء ودعوة البارتي",
        "نظام استرداد الأكواد (Redeem Code) لفتح الأبطال",
        "موسيقى سايبر إلكترونية خالية من أي محرمات"
    ],
    "download_url": "/downloads/update.zip",
    "file_size_bytes": 0,
    "sha256": "",
    "mandatory": False
}

def get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def load_version_info():
    if not VERSION_FILE.exists():
        save_version_info(DEFAULT_VERSION_DATA)
        return DEFAULT_VERSION_DATA
    try:
        with open(VERSION_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[Error] Failed to read version.json: {e}")
        return DEFAULT_VERSION_DATA

def save_version_info(data):
    with open(VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

class UpdateRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PUBLIC_DIR), **kwargs)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # CORS Headers for all requests
        if path == "/api/version":
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.end_headers()
            v_data = load_version_info()
            self.wfile.write(json.dumps(v_data, ensure_ascii=False).encode("utf-8"))
            return

        elif path.startswith("/downloads/"):
            filename = path.replace("/downloads/", "").strip("/")
            file_path = DOWNLOADS_DIR / filename
            if file_path.is_file():
                file_size = file_path.stat().st_size
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(file_size))
                self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                with open(file_path, "rb") as f:
                    while chunk := f.read(65536):
                        self.wfile.write(chunk)
                return
            else:
                self.send_error(404, f"File {filename} not found")
                return

        elif path == "/" or path == "/index.html":
            index_file = PUBLIC_DIR / "index.html"
            if index_file.is_file():
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                with open(index_file, "rb") as f:
                    self.wfile.write(f.read())
                return
            else:
                self.send_error(404, "index.html not found")
                return

        super().do_GET()

    def do_POST(self):
        if self.path == "/api/publish":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8"))
                from publish_update import publish_update
                version = data.get("version", "1.1.3")
                version_code = int(data.get("version_code", 5))
                title = data.get("title", "تحديث جديد من لوحة التحكم")
                changelog = data.get("changelog", ["تحسينات عامة على النظام واللعبة"])
                mandatory = data.get("mandatory", False)
                updated_data = publish_update(version, version_code, title, changelog, mandatory)
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "message": "Version updated successfully!", "data": updated_data}).encode("utf-8"))
            except Exception as e:
                self.send_error(500, f"Publish error: {e}")
            return
        self.send_error(404, "Endpoint not found")

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

def run_server():
    lan_ip = get_lan_ip()
    handler = UpdateRequestHandler
    with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), handler) as httpd:
        print("=" * 65)
        print("⚡ CyberFort: Titan Strike 3D - Auto-Update Server")
        print("=" * 65)
        print(f"[*] Local URL:    http://localhost:{PORT}")
        print(f"[*] Network URL:  http://{lan_ip}:{PORT}")
        print(f"[*] API Endpoint: http://{lan_ip}:{PORT}/api/version")
        print("=" * 65)
        print("[*] Server is running... Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[*] Stopping server...")
            httpd.server_close()

if __name__ == "__main__":
    run_server()
