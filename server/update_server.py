#!/usr/bin/env python3
"""
CyberFort Game Update & Remote Control Server (OTA Auto-Patcher & Live Game Manager)
Serves game version metadata, live game configuration (characters, stats, maps),
and downloadable patch packages (.zip / .pck) for mobile (iOS / Android) and PC clients
across both Local Wi-Fi and WAN/Internet connections.
"""

import http.server
import socketserver
import os
import sys
import json
import socket
import urllib.parse
import urllib.request
import threading
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PORT = 8080
BASE_DIR = Path(__file__).resolve().parent
PUBLIC_DIR = BASE_DIR / "public"
DOWNLOADS_DIR = PUBLIC_DIR / "downloads"
VERSION_FILE = PUBLIC_DIR / "version.json"
GAME_CONFIG_FILE = PUBLIC_DIR / "game_config.json"

DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)

DEFAULT_VERSION_DATA = {
    "version": "1.1.3",
    "version_code": 5,
    "release_date": "2026-10-19",
    "title": "تحديث لوحة تحكم الشخصيات ودعم الاتصال عبر الإنترنت",
    "changelog": [
        "إمكانية إزالة أو تفعيل/تعطيل أي شخصية مباشرة من الموقع",
        "تعديل خصائص وسرعة وصحة الشخصيات فورياً من لوحة التحكم",
        "دعم الاتصال بالأجهزة عبر الإنترنت وبيانات الهاتف (WAN & Mobile Data)",
        "تحسين المظهر الجمالي للعبة والقوائم وواجهة المستخدم (Cyber Polish)"
    ],
    "download_url": "/downloads/update.zip",
    "file_size_bytes": 0,
    "sha256": "",
    "mandatory": False
}

DEFAULT_GAME_CONFIG = {
    "heroes": {
        "0": {
            "name": "🍉 Melon Knight (فارس البطيخ)",
            "enabled": True,
            "hp": 130,
            "speed": 7.5,
            "role": "The newly upgraded hero! Fully animated emerald watermelon warrior with ruby cyber-core, fires rapid seeds and builds sturdy walls."
        },
        "1": {
            "name": "🍓 Berry Striker (بطلة الفراولة)",
            "enabled": True,
            "hp": 100,
            "speed": 8.5,
            "role": "Super fast berry ranger with high critical seed shots and tactical speed ramps."
        },
        "2": {
            "name": "🍊 Citrus Tank (البرتقال المدرّع)",
            "enabled": True,
            "hp": 240,
            "speed": 5.6,
            "role": "Heavy armored citrus juggernaut with explosive melon cannons and auto-turrets."
        },
        "3": {
            "name": "👑 Admin (الأدمن الخارق)",
            "enabled": True,
            "hp": 500,
            "speed": 15.0,
            "role": "Legendary secret hero! Unlocked by beating all 3 waves and both Big Bosses. Has 500 HP and golden armor."
        },
        "4": {
            "name": "🕷️ Spider Hero (سبايدر هودي)",
            "enabled": True,
            "hp": 220,
            "speed": 9.2,
            "role": "The newly added 3D Chibi Spider-Hero! Wearing an oversized hoodie, denim cutoffs, and retro high-top sneakers. Highly agile with web attacks!"
        }
    },
    "active_maps": [0, 1, 2, 3, 4, 5, 6],
    "server_announcement": "مرحباً بكم في سيرفر سايبر فورت! جميع الأبطال متاحون للقتال.",
    "server_status": "ONLINE"
}

_cached_wan_ip = None

def get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def get_wan_ip():
    global _cached_wan_ip
    if _cached_wan_ip:
        return _cached_wan_ip
    try:
        req = urllib.request.Request(
            "https://api.ipify.org",
            headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=4) as response:
            _cached_wan_ip = response.read().decode("utf-8").strip()
            return _cached_wan_ip
    except Exception:
        return "105.197.151.212"

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

def load_game_config():
    if not GAME_CONFIG_FILE.exists():
        save_game_config(DEFAULT_GAME_CONFIG)
        return DEFAULT_GAME_CONFIG
    try:
        with open(GAME_CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[Error] Failed to read game_config.json: {e}")
        return DEFAULT_GAME_CONFIG

def save_game_config(data):
    with open(GAME_CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

class UpdateRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PUBLIC_DIR), **kwargs)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/version":
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.end_headers()
            v_data = load_version_info()
            self.wfile.write(json.dumps(v_data, ensure_ascii=False).encode("utf-8"))
            return

        elif path == "/api/game_config":
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.end_headers()
            cfg_data = load_game_config()
            self.wfile.write(json.dumps(cfg_data, ensure_ascii=False).encode("utf-8"))
            return

        elif path == "/api/network_info":
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.end_headers()
            net_data = {
                "lan_ip": get_lan_ip(),
                "wan_ip": get_wan_ip(),
                "port": PORT,
                "lan_url": f"http://{get_lan_ip()}:{PORT}",
                "wan_url": f"http://{get_wan_ip()}:{PORT}",
                "status": "ONLINE"
            }
            self.wfile.write(json.dumps(net_data, ensure_ascii=False).encode("utf-8"))
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
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                with open(index_file, "rb") as f:
                    self.wfile.write(f.read())
                return
            else:
                self.send_error(404, "index.html not found")
                return

        super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/publish":
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

        elif path == "/api/game_config":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8"))
                current_config = load_game_config()
                if "heroes" in data:
                    current_config["heroes"] = data["heroes"]
                if "active_maps" in data:
                    current_config["active_maps"] = data["active_maps"]
                if "server_announcement" in data:
                    current_config["server_announcement"] = data["server_announcement"]
                if "server_status" in data:
                    current_config["server_status"] = data["server_status"]
                
                save_game_config(current_config)
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps({
                    "success": True, 
                    "message": "Game configuration updated successfully!", 
                    "config": current_config
                }, ensure_ascii=False).encode("utf-8"))
            except Exception as e:
                self.send_error(500, f"Game config error: {e}")
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
    wan_ip = get_wan_ip()
    handler = UpdateRequestHandler
    with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), handler) as httpd:
        print("=" * 70)
        print("⚡ CyberFort: Titan Strike 3D - Live Control & OTA Server")
        print("=" * 70)
        print(f"[*] Localhost:      http://localhost:{PORT}")
        print(f"[*] Wi-Fi (LAN):    http://{lan_ip}:{PORT}")
        print(f"[*] Internet (WAN): http://{wan_ip}:{PORT}")
        print(f"[*] Config API:     http://{lan_ip}:{PORT}/api/game_config")
        print(f"[*] Network API:    http://{lan_ip}:{PORT}/api/network_info")
        print("=" * 70)
        print("[*] Server is running... Ready to serve mobile & PC clients!")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[*] Stopping server...")
            httpd.server_close()

if __name__ == "__main__":
    run_server()
