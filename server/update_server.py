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
import re
import time
import socket
import urllib.parse
import urllib.request
import threading
import ipaddress
import base64
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

PORT = int(os.environ.get("PORT", 8080))
GUEST_PORT = int(os.environ.get("GUEST_PORT", 8081 if PORT != 8081 else 8082))
IS_CLOUD = bool(os.environ.get("RENDER") or os.environ.get("RAILWAY_ENVIRONMENT") or os.environ.get("DYNO") or (os.environ.get("PORT") and os.environ.get("PORT") != "8080"))
BASE_DIR = Path(__file__).resolve().parent
PUBLIC_DIR = BASE_DIR / "public" if (BASE_DIR / "public").exists() else (BASE_DIR / "server" / "public" if (BASE_DIR / "server" / "public").exists() else BASE_DIR)
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

def get_all_lan_ips() -> list[str]:
    """Returns all active local IPv4 addresses sorted by priority (LAN/Wi-Fi first, then Hotspot, vEthernet)."""
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        primary = s.getsockname()[0]
        s.close()
        if primary and primary != "127.0.0.1":
            ips.append(primary)
    except Exception:
        pass

    try:
        import psutil
        for iface, addrs in psutil.net_if_addrs().items():
            for a in addrs:
                if a.family == socket.AF_INET:
                    ip = a.address
                    if ip and not ip.startswith("127.") and not ip.startswith("169.254."):
                        if ip not in ips:
                            if not ip.startswith("172."):
                                ips.insert(0 if not ips else 1, ip)
                            else:
                                ips.append(ip)
    except Exception:
        pass

    if not ips:
        ips.append("127.0.0.1")
    return ips

def get_lan_ip() -> str:
    all_lan = get_all_lan_ips()
    return all_lan[0] if all_lan else "127.0.0.1"

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

def is_local_router_client(client_ip: str) -> bool:
    """Returns True if the client IP belongs to the local router subnet (Wi-Fi/LAN/localhost)."""
    try:
        clean_ip = str(client_ip).replace("::ffff:", "").strip()
        if clean_ip in ("127.0.0.1", "::1", "localhost"):
            return True
        ip = ipaddress.ip_address(clean_ip)
        return ip.is_private or ip.is_loopback
    except Exception:
        return False

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

def handle_verify_device_request(data: dict, client_ip: str) -> tuple[int, dict]:
    device_id = str(data.get("device_id", "")).strip()
    device_name = str(data.get("device_name", "Unknown Device")).strip()
    os_name = str(data.get("os", "Unknown OS")).strip()
    username = str(data.get("username", "")).strip()

    current_config = load_game_config()
    dev_sec = current_config.get("device_security", {
        "whitelist_enabled": True,
        "allowed_devices": [],
        "pending_devices": []
    })

    if not dev_sec.get("whitelist_enabled", True):
        return 200, {"allowed": True, "message": "Whitelist disabled - access granted"}

    clean_id = device_id.strip("{} ").lower()
    matched = None
    for dev in dev_sec.get("allowed_devices", []):
        if dev.get("id", "").strip("{} ").lower() == clean_id:
            matched = dev
            break

    if matched and matched.get("status", "APPROVED") == "APPROVED":
        return 200, {
            "allowed": True, 
            "device_id": device_id,
            "device_name": matched.get("name", device_name),
            "message": "Authorized device recognized"
        }
    else:
        pending = dev_sec.get("pending_devices", [])
        exists_pending = any(p.get("id", "").strip("{} ").lower() == clean_id for p in pending)
        if not exists_pending and clean_id:
            pending.append({
                "id": device_id,
                "name": device_name,
                "os": os_name,
                "username": username,
                "ip": client_ip,
                "requested_at": "2026-10-20"
            })
            dev_sec["pending_devices"] = pending
            current_config["device_security"] = dev_sec
            save_game_config(current_config)

        return 200, {
            "allowed": False,
            "device_id": device_id,
            "reason": "UNAUTHORIZED_DEVICE",
            "message": "⛔ هذا الجهاز غير مصرح له بالدخول. يرجى طلب التصريح من مدير السيرفر."
        }

def handle_device_request_submission(data: dict, client_ip: str) -> tuple[int, dict]:
    dev_name = str(data.get("device_name", "📱 جهاز زائر")).strip()
    dev_id = str(data.get("device_id", "")).strip()
    notes = str(data.get("notes", "")).strip()
    clean_id = dev_id.strip("{} ").lower()

    current_config = load_game_config()
    dev_sec = current_config.get("device_security", {
        "whitelist_enabled": True,
        "allowed_devices": [],
        "pending_devices": []
    })

    pending = dev_sec.get("pending_devices", [])
    exists = any(p.get("id", "").strip("{} ").lower() == clean_id for p in pending) if clean_id else False
    if not exists:
        if not clean_id:
            import uuid
            dev_id = f"guest-{uuid.uuid4().hex[:8]}"
        pending.append({
            "id": dev_id,
            "name": dev_name,
            "notes": notes,
            "ip": client_ip,
            "requested_at": "2026-10-20"
        })
        dev_sec["pending_devices"] = pending
        current_config["device_security"] = dev_sec
        save_game_config(current_config)

    return 200, {
        "success": True,
        "device_id": dev_id,
        "message": "Device request registered for admin approval!"
    }

# ==============================================================================
# LIVE GAME CONSOLE & ROOM TRACKING (Leader Real-time Operations)
# ==============================================================================
CONSOLE_LOGS = []
MAX_CONSOLE_LOGS = 250
ROOMS = {} # room_code: { "code": code, "host": host, "mode": mode, "players": count, "created_at": time, "status": "ACTIVE" }
TOTAL_ROOMS_CREATED = 0
TERMINATED_ROOMS = set()
ACTIVE_SESSIONS = {} # session_id: { "player": ..., "mode": ..., "hero": ..., "status": ..., "ip": ... }
GLOBAL_EMERGENCY_ALARM = {"active": False, "message": "", "id": 0}
GLOBAL_BROADCAST = {"message": "", "id": 0, "room_code": ""}
GLOBAL_AI_DUEL_TRIGGER = {"active": False, "message": "", "room_code": "AI1V1", "ai_name": "CyberAI", "id": 0}

# ==============================================================================
# GEMINI 3.5 FLASH AI INTEGRATION (CyberAI Engine)
# ==============================================================================
GEMINI_B64_KEY = "QVEuQWI4Uk42SW9IRnU1M000UkJBTlR6ZHcxaG1xQkJnckZTdXlzNzNwT3pfTUJ5R01FR0E="

def _resolve_gemini_key():
    env_k = os.environ.get("GEMINI_API_KEY")
    if env_k:
        return env_k
    cfg_file = BASE_DIR / "ai_config.json"
    if cfg_file.exists():
        try:
            with open(cfg_file, "r", encoding="utf-8") as f:
                d = json.load(f)
                if d.get("api_key"):
                    return d["api_key"]
        except Exception:
            pass
    try:
        return base64.b64decode(GEMINI_B64_KEY).decode("ascii")
    except Exception:
        return ""

GEMINI_API_KEY = _resolve_gemini_key()
GEMINI_MODEL = "gemini-3.5-flash-lite"
GEMINI_FALLBACK_MODELS = ["gemini-3.5-flash-lite", "gemini-flash-lite-latest", "gemini-3.5-flash"]


def execute_server_action(action_name: str, params: dict, context_type: str = "general") -> tuple[bool, str, dict]:
    global ROOMS, TOTAL_ROOMS_CREATED, GLOBAL_BROADCAST, GLOBAL_EMERGENCY_ALARM
    is_admin = (context_type == "admin_dashboard")
    action_data = {"name": action_name, "params": params}
    
    global GLOBAL_AI_DUEL_TRIGGER
    act_l = str(action_name).lower()
    if any(k in act_l for k in ["room", "1v1", "duel", "game", "ai_room"]):
        hero_name = params.get("hero", "Spider Hero")
        code = "AI1V1"
        now_ts = time.time()
        import datetime
        now_str = datetime.datetime.now().strftime("%H:%M:%S")
        all_lan = get_all_lan_ips()
        clean_lan = [ip for ip in all_lan if ip != "127.0.0.1"]
        host_ip = clean_lan[0] if clean_lan else "127.0.0.1"
        
        ROOMS[code] = {
            "code": code,
            "host": "CyberAI 🤖 [BOT 1v1]",
            "mode": "⚔️ 1v1 PvP Duel vs CyberAI",
            "map_id": 0,
            "players": 1,
            "players_list": ["CyberAI 🤖"],
            "created_at": now_str,
            "host_ip": host_ip,
            "candidate_ips": all_lan,
            "port": 7777,
            "last_seen": now_ts,
            "status": "WAITING_FOR_OPPONENT",
            "is_ai_room": True,
            "ai_hero": hero_name
        }
        TOTAL_ROOMS_CREATED += 1
        
        GLOBAL_AI_DUEL_TRIGGER["active"] = True
        GLOBAL_AI_DUEL_TRIGGER["id"] = int(time.time() * 1000)
        GLOBAL_AI_DUEL_TRIGGER["room_code"] = code
        GLOBAL_AI_DUEL_TRIGGER["message"] = f"⚔️ أنشأ CyberAI غرفة 1v1 بكود #{code} ويدعوك للنزال فوراً!"
        
        GLOBAL_BROADCAST["message"] = f"⚔️ أنشأ CyberAI غرفة 1v1 بكود #{code} ويدعوك لدخول الساحة فوراً!"
        GLOBAL_BROADCAST["id"] = int(time.time() * 1000)
        GLOBAL_BROADCAST["room_code"] = code
        
        msg = f"تم إنشاء وتجهيز غرفة المبارزة 1v1 بنجاح على السيرفر! كود الغرفة: #{code}"
        add_console_log("CYBER_AI", f"⚔️ دخل CyberAI السيرفر وأنشأ غرفة 1v1 بكود #{code} بانتظار القائد في الساحة فوراً!", "SUCCESS")
        return True, msg, action_data
        
    elif any(k in act_l for k in ["broadcast", "announce", "msg", "message"]):
        if not is_admin:
            return False, "عذراً! إرسال إعلانات عامة باللعبة متاح للقائد فقط من لوحة التحكم.", action_data
        b_msg = str(params.get("message", "")).strip()
        if not b_msg:
            return False, "نص الإعلان فارغ.", action_data
        GLOBAL_BROADCAST["message"] = b_msg
        GLOBAL_BROADCAST["id"] = int(time.time())
        GLOBAL_BROADCAST["room_code"] = ""
        add_console_log("ADMIN", f"📢 أرسل CyberAI إعلان القائد باللعبة: '{b_msg}'", "SUCCESS")
        return True, f"تم إرسال إعلان القائد لجميع اللاعبين باللعبة: '{b_msg}'", action_data
        
    elif any(k in act_l for k in ["alarm", "siren"]):
        if not is_admin:
            return False, "عذراً! التحكم بصفارات الإنذار متاح للقائد فقط.", action_data
        active = bool(params.get("active", True))
        msg = str(params.get("message", "🚨 إنذار عام صادر من القائد!")).strip()
        GLOBAL_EMERGENCY_ALARM["active"] = active
        GLOBAL_EMERGENCY_ALARM["message"] = msg if active else ""
        GLOBAL_EMERGENCY_ALARM["id"] = int(time.time())
        status_txt = "تشغيل" if active else "إيقاف"
        add_console_log("ADMIN", f"🚨 قام CyberAI بـ {status_txt} صفارات الإنذار بأمر من القائد!", "WARNING" if active else "INFO")
        return True, f"تم {status_txt} صفارة الإنذار العامة باللعبة بنجاح.", action_data
        
    elif any(k in act_l for k in ["server", "toggle", "maintenance", "open_server", "close_server"]):
        if not is_admin:
            return False, "عذراً! فتح أو إغلاق السيرفر متاح للقائد فقط.", action_data
        target_status = str(params.get("status", "OPEN")).upper()
        if target_status not in ["OPEN", "CLOSED"]:
            target_status = "OPEN"
        cfg = load_game_config()
        cfg["server_status"] = target_status
        save_game_config(cfg)
        status_ar = "مفتوح ومتاح للجميع 🟢" if target_status == "OPEN" else "مغلق للصيانة 🔴"
        add_console_log("ADMIN", f"⚙️ قام CyberAI بتغيير حالة السيرفر بأمر من القائد إلى: {target_status}", "WARNING" if target_status == "CLOSED" else "SUCCESS")
        return True, f"تم تعديل حالة السيرفر إلى: {status_ar}", action_data
        
    elif any(k in act_l for k in ["hero", "stat", "balance", "hp", "speed"]):
        if not is_admin:
            return False, "عذراً! تعديل طاقات الأبطال متاح للقائد فقط.", action_data
        hero_id = str(params.get("hero_id", 0))
        hp = params.get("hp")
        speed = params.get("speed")
        cfg = load_game_config()
        heroes = cfg.get("heroes", {})
        if hero_id in heroes:
            if hp is not None:
                heroes[hero_id]["hp"] = int(hp)
            if speed is not None:
                heroes[hero_id]["speed"] = float(speed)
            save_game_config(cfg)
            h_name = heroes[hero_id].get("name", f"Hero #{hero_id}")
            add_console_log("ADMIN", f"⚖️ قام CyberAI بتعديل طاقة البطل ({h_name}) بأمر من القائد!", "INFO")
            return True, f"تم تعديل طاقة {h_name} بنجاح.", action_data
        return False, "لم يتم العثور على البطل المطلوب.", action_data
        
    elif any(k in act_l for k in ["terminate", "kick", "delete"]):
        if not is_admin:
            return False, "عذراً! إغلاق الغرف متاح للقائد فقط.", action_data
        code = str(params.get("code", "")).strip().upper()
        if code:
            handle_rooms_terminate({"room_code": code})
            return True, f"تم طرد اللاعبين وإغلاق الغرفة #{code} بنجاح.", action_data
        return False, "كود الغرفة غير صحيح.", action_data
        
    return False, "أمر غير معروف.", action_data


def detect_user_intent_action(prompt: str, context_type: str = "general") -> dict:
    p = prompt.strip().lower()
    is_admin = (context_type == "admin_dashboard")
    
    # 1. Create Room / Enter Game / 1v1 Duel against CyberAI
    create_room_keywords = [
        "خش اللعبة", "خش العبه", "ادخل اللعبة", "ادخل العبه", "اعمل غرفة", "اعمل الغرفة", 
        "اعمل روم", "اعمل لي روم", "اعمل غرفه", "اعمل الغرفه", "اعمل الغرف", "اعمل لي الغرف", 
        "سوي روم", "سوي غرفة", "سوي غرفه", "سوي الغرف", "افتح روم", "افتح غرفة", "افتح غرفه", "افتح الغرف",
        "روم 1v1", "1v1", "العب معاك", "العب معايا", "نلعب سوا", "نلعب مع بعض", 
        "نلعب ضد بعض", "قولي الكود", "كود الغرفة", "كود الغرفه", "مبارزة", "تحدي", "روم", "غرفة", "غرفه", "الغرف", "غرف"
    ]
    if any(k in p for k in create_room_keywords):
        return {"name": "create_ai_room", "params": {"hero": "Spider Hero"}}
    
    # Admin only actions
    if is_admin:
        if "إنذار" in p or "انذار" in p or "صفارة" in p:
            active = not any(k in p for k in ["اطفي", "وقف", "إيقاف", "الغاء", "إلغاء"])
            return {"name": "alarm", "params": {"active": active}}
            
        if ("اقفل" in p or "قفل" in p or "اغلق" in p or "صيانة" in p) and ("سيرفر" in p or "السيرفر" in p or "سرفر" in p or "السرفر" in p):
            return {"name": "server_toggle", "params": {"status": "CLOSED"}}
            
        if ("افتح" in p or "تشغيل" in p) and ("سيرفر" in p or "السيرفر" in p or "سرفر" in p or "السرفر" in p):
            return {"name": "server_toggle", "params": {"status": "OPEN"}}
            
        if any(k in p for k in ["رسالة للاعبين", "اعلان للاعبين", "إعلان للاعبين"]) or (p.startswith("ابعت") and "لاعبين" in p):
            msg = p
            for prefix in ["ابعت رسالة للاعبين:", "ابعت رسالة للاعبين", "اكتب اعلان للاعبين:", "اكتب إعلان للاعبين:", "أعلن:"]:
                if prefix in msg:
                    msg = msg.split(prefix, 1)[1].strip()
                    break
            return {"name": "broadcast", "params": {"message": msg}}

    return None


def generate_smart_cyberai_response(prompt: str, is_admin: bool) -> str:
    p = prompt.strip().lower()
    
    # 1. Greetings
    if any(w in p for w in ["سلام", "مرحبا", "ازيك", "صباح", "مساء", "مين انت", "عرفني", "hello", "hi"]):
        if is_admin:
            return "يا مرحب يا قائدنا سيف! 👑 أنا CyberAI المساعد الذكي الخاص بك لسيرفر ولعبة Titan Strike 3D. كل الأنظمة تحت أمرك، تحب نفتح مبارزة 1v1، ولا نعدل إعدادات السيرفر أو نطلق إنذار؟"
        return "أهلاً بك يا بطل في Titan Strike 3D! 🍉⚔️ أنا CyberAI مساعدك الذكي في اللعبة. اسألني عن أي بطل، المابات، أزرار التحكم على الموبايل، أو تحداني في مبارزة 1v1!"

    # 2. Heroes / Characters
    if any(w in p for w in ["ابطال", "بطل", "شخصيات", "شخصيه", "الشخصية", "شخصيات اللعبة", "heroes", "hero", "فارس البطيخ", "ستروبري", "تانك", "سبايدر", "ادمن"]):
        return (
            "🍉 **دليل أبطال Titan Strike 3D المعتمدين:**\n\n"
            "1. 🍉 **Melon Knight (فارس البطيخ):** المحارب الزمردي المتوازن! صحة 130، سرعة 7.5، ورشاش بذور سريع.\n"
            "2. 🍓 **Berry Striker (صقر الفراولة):** أسرع مهاجم قناص! سرعة فائقة 9.2، صحة 90، ومحركات نفاثة خلفية.\n"
            "3. 🍊 **Citrus Tank (العملاق الحمضي):** المدرعة الثقيلة! صحة 220، سرعة 5.8، ومدفع عصير متفجر يهدم الأعداء.\n"
            "4. 👑 **Admin Overlord (القائد الأعلى):** بطل سري خارق! دروع ذهبية ملكية وصحة 300 لا تقهر (يُفتح عند هزيمة الزعيم).\n"
            "5. 🕷️ **Spider Hero (سبايدر هودي):** خفة حركة ورشاقة خارقة مستوحاة من سبايدرمان!"
        )

    # 3. Maps / Arenas
    if any(w in p for w in ["ماب", "مابات", "ساحة", "الخرائط", "خريطة", "map", "maps"]):
        return (
            "🗺️ **الساحات والمابات السبعة المتاحة:**\n\n"
            "1. 🍉 **Fruit Kingdom Arena:** الساحة الملكية الخضراء بحصون البطيخ.\n"
            "2. 🏙️ **Cyber Stadium 2077:** ستاد المستقبل المليء بإضاءات النيون والأبراج الليزرية.\n"
            "3. 🏜️ **Desert Titan Canyon:** وادي الصحراء الرملية الحارقة.\n"
            "4. 🌋 **Volcanic Magma Core:** قلب البركان الناري مع حمم متوهجة.\n"
            "5. ❄️ **Frozen Ice Glacier:** جليد متجمد وضباب قطبي أزرق كريستالي.\n"
            "6. 🌌 **Cosmic Galaxy Void:** الفضاء الكوني المظلم والنجوم البنفسجية.\n"
            "7. 🌆 **Neon Citadel:** مدينة المستقبل السايبربانك ذات الألوان الساحرة!"
        )

    # 4. Missions / Difficulty
    if any(w in p for w in ["مهمات", "مهمة", "اصعب", "صعب", "كابوس", "nightmare", "صعوبة", "الموجات", "الوحوش"]):
        return (
            "⚔️ **نظام المهمات الفائقة والصعوبة (Titan Nightmare Mode):**\n\n"
            "• **المرحلة 1:** 3 موجات متتالية من الروبوتات السريعة، تليها معركة الزعيم الآلي Blazing Titan!\n"
            "• **المرحلة 2 (الكابوس):** 5 موجات قتالية وحشية مع روبوتات متفجرة ومتحركة بسرعة مضاعفة!\n"
            "• **نصائح للفوز بالمهمات الصعبة:** استغل منصة الشحن التكتيكية، وابنِ حوائط البطيخ للاحتماء، ونسق بين المهاجم والمدرع!"
        )

    # 5. Mobile & Android APK
    if any(w in p for w in ["اندرويد", "موبايل", "apk", "android", "تلفون", "تحميل", "تنزيل", "download"]):
        return (
            "📱 **تشغيل اللعبة على أندرويد (Android APK):**\n\n"
            "اللعبة تدعم نظام أندرويد بالكامل مع تحكم Multi-Touch سلس (جويستيك حركة افتراضي، زر إطلاق النار، زر القفز، وبناء الحوائط).\n"
            "يمكنك تحميل ملف الـ APK مباشرة من زر 'تحميل APK للأندرويد' في الموقع أو من الرابط: /downloads/TitanStrike.apk وتثبيته فوراً على أي هاتف!"
        )

    # 6. Accounts / Sign in & Sign up
    if any(w in p for w in ["تسجيل", "حساب", "دخول", "sign in", "sign up", "register", "login", "password"]):
        return (
            "🔐 **نظام الحسابات وقاعدة البيانات:**\n\n"
            "• يمكنك إنشاء حسابك الجديد وتسجيل الدخول بسهولة من شاشة اللعبة الرئيسية أو من الموقع مباشرة.\n"
            "• قاعدة البيانات تحفظ تقدمك ومستواك وسجل انتصاراتك تلقائياً.\n"
            "• بمجرد التسجيل باسم مستخدم وكلمة مرور، يمكنك فتح حسابك من أي موبايل أو كمبيوتر ومزامنة تقدمك فوراً!"
        )

    # 7. Training / Dummies
    if any(w in p for w in ["تدريب", "روبوت التدريب", "dummy", "تمارين", "تدرب"]):
        return (
            "🎯 **حلبة التدريب المتطورة (Training Grounds):**\n\n"
            "تم تحديث حلبة التدريب بالكامل وإصلاح تصادم الرصاص:\n"
            "1. 🎯 **الروبوت القياسي:** لقياس معدل الضرر الحقيقي بالثانية (DPS).\n"
            "2. 🛡️ **الهدف المدرع الثقيل:** صحة 3500 HP لتجربة الأسلحة الثقيلة وإطلاق النار المتواصل.\n"
            "3. 🛸 **الهدف الطائر المتحرك:** يتحرك أفقياً لتمرين دقة التصويب على الأهداف السريعة.\n"
            "4. ⚡ **منصة الشحن:** تعيد ملء صحتك وذخيرتك 100% فور الوقوف عليها!"
        )

    # Default fallback
    if is_admin:
        return f"أمرك يا قائدنا سيف! تلقيت رسالتك: '{prompt}'. أنا متابع كل تفاصيل السيرفر واللعبة وجاهز لأي أمر أو تشغيل فوري!"
    return f"مرحباً بك يا بطل! سؤالك بخصوص '{prompt}' مهم جداً. يمكنك تجربة الأبطال ومحاربة الروبوتات في طور Co-op أو التدريب في Training Grounds لتحطيم أعلى DPS!"

def call_gemini_ai(user_prompt: str, context_type: str = "general") -> tuple[int, dict]:
    """Generates intelligent game responses using Google Gemini 3.5 Flash with full executive action control."""
    user_prompt = str(user_prompt).strip()
    if not user_prompt:
        return 400, {"success": False, "error": "يرجى كتابة سؤال أو استفسار للذكاء الاصطناعي."}

    is_admin = (context_type == "admin_dashboard")
    
    if is_admin:
        sys_context = (
            "أنت 'CyberAI' - المساعد الذكي لـ 'القائد' في لعبة Titan Strike 3D.\n" 
            "مهمتك وصلاحياتك محددة في أمرين اثنين فقط لا غير بأمر القائد:\n" 
            "1. الرد بدقة وذكاء وسرعة على أي أسئلة يطرحها القائد (سواء عن اللعبة، الأبطال، التكتيكات، حالة السيرفر، أو أي سؤال عام).\n" 
            "2. تنفيذ الأوامر داخل اللعبة حصراً: (إنشاء غرفة مبارزة 1v1 ودخول الساحة، إرسال إعلان للاعبين باللعبة، تشغيل أو إيقاف صفارات الإنذار، فتح أو إغلاق السيرفر).\n" 
            "⚠️ تنبيه صارم: لا تقم بأي تعديل على ملفات الكود أو حذف ملفات النظام أو أي إجراء خارج اللعبة. عملك محصور فقط في الإجابة على الأسئلة ثم تنفيذ فعاليات داخل اللعبة فقط!\n" 
            "إذا طلب منك القائد دخول اللعبة أو عمل غرفة 1v1، رحب بأمره فوراً وأخبره بكود الغرفة: #AI1V1 لتحديه في الساحة!\n" 
            "إذا طلب القائد أي أمر تنفيذي داخل اللعبة، قم بتضمين تاج الأمر: <!--ACTION:{\"name\": \"<action_name>\", \"params\": {..}}-->\n" 
            "أجب دائماً بلغة عربية حماسية ومباشرة وذكية في سطرين إلى 3 أسطر كحد أقصى."
        )
    else:
        sys_context = (
            "أنت 'CyberAI' - المساعد التكتيكي الذكي للعبة سايبر فورت (Titan Strike 3D). "
            "الشخص الذي يتحدث معك الآن هو 'لاعب عادي / مقاتل'. خاطبه بلقب 'يا بطل' أو 'يا مقاتل'. "
            "أنت تساعده في أسرار اللعب، نصائح الأبطال، استراتيجيات الفوز، ويمكنك التحدي معه في مبارزة 1v1. "
            "إذا طلب منك اللعب معه أو عمل غرفة 1v1 ('العب معايا'، 'خش اللعبة واعمل غرفة وقولي الكود')، رحب بالتحدي بحماس وأعطه كود الغرفة: #AI1V1 وقل له أنك بانتظاره في ساحة القتال! "
            "إذا طلب اللاعب أوامر إدارية (مثل إغلاق السيرفر أو تغيير طاقات الأبطال أو طرد لاعبين)، ارفض بلباقة وأخبره أن هذه الصلاحيات الإدارية حصرية فقط لـ 'القائد' من لوحة التحكم في الموقع. "
            "أجب دائماً بلغة عربية حماسية ومباشرة في سطرين إلى 3 أسطر."
        )

    payload = {
        "contents": [
            {
                "parts": [
                    {"text": f"[تعليمات النظام]: {sys_context}\n\n[طلب {'القائد' if is_admin else 'اللاعب'}]: {user_prompt}"}
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 300
        }
    }
    encoded_body = json.dumps(payload).encode("utf-8")

    reply_text = ""
    used_model = "gemini-3.5-flash-lite"
    
    for m in GEMINI_FALLBACK_MODELS:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{m}:generateContent?key={GEMINI_API_KEY}"
        try:
            req = urllib.request.Request(
                url, 
                data=encoded_body, 
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                candidates = data.get("candidates", [])
                if candidates and "content" in candidates[0]:
                    parts = candidates[0]["content"].get("parts", [])
                    reply_text = "".join(p.get("text", "") for p in parts).strip()
                    used_model = m
                    break
        except Exception:
            continue

    if not reply_text:
        reply_text = generate_smart_cyberai_response(user_prompt, is_admin)

    # Parse and execute actions
    action_info = None
    action_msg = ""
    
    # 1. Check for action tag in Gemini response
    m_action = re.search(r'<!--ACTION:(.*?)-->', reply_text, re.DOTALL)
    if m_action:
        try:
            raw_act = json.loads(m_action.group(1).strip())
            act_name = raw_act.get("name")
            act_params = raw_act.get("params", {})
            reply_text = reply_text.replace(m_action.group(0), "").strip()
            ok, action_msg, action_info = execute_server_action(act_name, act_params, context_type)
        except Exception as ex:
            print("Action parse error:", ex)
            
    # 2. Safety Net: If no action parsed, use intent detection
    if not action_info:
        detected = detect_user_intent_action(user_prompt, context_type)
        if detected:
            ok, action_msg, action_info = execute_server_action(detected["name"], detected.get("params", {}), context_type)

    if action_info and any(k in str(action_info.get("name", "")).lower() for k in ["room", "1v1", "duel"]):
        reply_text = (
            "أمرك يا قائدنا وسمعاً وطاعة! ⚔️\n"
            "دخلت اللعبة وجهزتلك غرفة المبارزة 1v1 فوراً كخصم ومنافس لك في الساحة!\n"
            "🔑 كود الغرفة: #AI1V1\n"
            "تم إرسال إشعار التحدي المباشر لشاشة لعبتك الآن، أو اضغط على الزر بالأسفل للبدء فوراً!"
        )

    add_console_log("CYBER_AI", f"🤖 ({'👑 القائد' if is_admin else '👤 اللاعب'}): '{user_prompt[:30]}...' -> {reply_text[:40]}...", "SUCCESS" if action_info else "INFO")

    return 200, {
        "success": True,
        "reply": reply_text,
        "model": used_model,
        "role": "commander" if is_admin else "player",
        "action": action_info,
        "action_result": action_msg
    }


def add_console_log(source: str, message: str, level: str = "INFO"):
    global CONSOLE_LOGS
    import datetime
    now_str = datetime.datetime.now().strftime("%H:%M:%S")
    entry = {
        "time": now_str,
        "source": source,
        "message": message,
        "level": level
    }
    CONSOLE_LOGS.append(entry)
    if len(CONSOLE_LOGS) > MAX_CONSOLE_LOGS:
        CONSOLE_LOGS.pop(0)
    
    # Instant Telegram Alert on any server or game error
    if level == "ERROR":
        try:
            from discord_bot import notify_server_error
            notify_server_error(source, message)
        except Exception:
            pass

def handle_session_update(data: dict, client_ip: str) -> tuple[int, dict]:
    global ACTIVE_SESSIONS
    session_id = str(data.get("session_id", "")).strip()
    if not session_id:
        session_id = f"sess_{str(client_ip).replace(':', '_')}"
    
    action = str(data.get("action", "heartbeat")).strip()
    if action == "leave":
        removed = ACTIVE_SESSIONS.pop(session_id, None)
        if removed:
            add_console_log("SESSION", f"👋 خرج اللاعب '{removed.get('player', '')}' من الجلسة", "INFO")
        return 200, {"success": True, "active_count": len(ACTIVE_SESSIONS)}
    
    import datetime
    import time
    now_str = datetime.datetime.now().strftime("%H:%M:%S")
    clean_ip = str(client_ip).replace("::ffff:", "").strip()
    
    is_new = session_id not in ACTIVE_SESSIONS
    ACTIVE_SESSIONS[session_id] = {
        "id": session_id,
        "player": str(data.get("player_name", "لاعب")).strip(),
        "mode": str(data.get("mode", "⚔️ 1v1 PvP Duel")).strip(),
        "hero": str(data.get("hero", "Melon Boy")).strip(),
        "status": str(data.get("status", "PLAYING")).strip(),
        "ip": clean_ip,
        "time": now_str,
        "last_seen": time.time()
    }
    if is_new:
        p_name = ACTIVE_SESSIONS[session_id]["player"]
        m_name = ACTIVE_SESSIONS[session_id]["mode"]
        add_console_log("SESSION", f"🎮 دخل اللاعب '{p_name}' طور ({m_name}) الآن!", "SUCCESS")
    
    return 200, {"success": True, "active_count": len(ACTIVE_SESSIONS), "sessions": list(ACTIVE_SESSIONS.values())}

def handle_rooms_update(data: dict) -> tuple[int, dict]:
    global ROOMS, TOTAL_ROOMS_CREATED
    code = str(data.get("room_code", "")).strip().upper()
    if not code:
        return 400, {"success": False, "error": "Missing room code"}
    
    import datetime
    import time
    now_ts = time.time()
    
    if code in ROOMS:
        ROOMS[code]["last_seen"] = now_ts
        if "mode" in data and data["mode"]:
            old_mode = ROOMS[code].get("mode", "")
            new_mode = str(data["mode"]).strip()
            ROOMS[code]["mode"] = new_mode
            if old_mode != new_mode:
                add_console_log("ROOM", f"🔄 تم تغيير طور الغرفة #{code} إلى ({new_mode})", "INFO")
        if "players_list" in data:
            ROOMS[code]["players_list"] = data["players_list"]
        if "players" in data and data["players"] is not None:
            p_cnt = int(data["players"])
            if "players_list" in ROOMS[code] and len(ROOMS[code]["players_list"]) > p_cnt:
                p_cnt = len(ROOMS[code]["players_list"])
            ROOMS[code]["players"] = max(1, p_cnt)
        if "candidate_ips" in data and data["candidate_ips"]:
            ROOMS[code]["candidate_ips"] = data["candidate_ips"]
        if "status" in data and data["status"]:
            ROOMS[code]["status"] = str(data["status"]).strip()
        return 200, {"success": True, "room": ROOMS[code]}
    else:
        # Re-register room if host is still running
        p_list = data.get("players_list", [])
        ROOMS[code] = {
            "code": code,
            "host": str(data.get("host_name", "لاعب")).strip(),
            "mode": str(data.get("mode", "Multiplayer")).strip(),
            "players": max(1, len(p_list), int(data.get("players", 1))),
            "players_list": p_list,
            "created_at": datetime.datetime.now().strftime("%H:%M:%S"),
            "host_ip": get_lan_ip(),
            "port": 7777,
            "status": str(data.get("status", "ACTIVE")).strip(),
            "broadcast_message": "",
            "message_id": 0,
            "last_seen": now_ts
        }
        TOTAL_ROOMS_CREATED += 1
        return 200, {"success": True, "room": ROOMS[code]}

def handle_rooms_create(data: dict, client_ip: str = "") -> tuple[int, dict]:
    global TOTAL_ROOMS_CREATED, ROOMS, TERMINATED_ROOMS
    code = str(data.get("room_code", "")).strip().upper()
    host = str(data.get("host_name", "لاعب")).strip()
    mode = str(data.get("mode", "Co-op")).strip()
    players = int(data.get("players", 1))
    
    if not code:
        return 400, {"success": False, "error": "Missing room code"}
    
    import datetime
    import time
    now_str = datetime.datetime.now().strftime("%H:%M:%S")
    
    clean_ip = str(client_ip).replace("::ffff:", "").strip()
    if not clean_ip or clean_ip in ("127.0.0.1", "localhost", "::1"):
        clean_ip = get_lan_ip()
    
    p_list = data.get("players_list", [host])
    if not p_list:
        p_list = [host]
    
    candidate_ips = data.get("candidate_ips", [])
    if not candidate_ips:
        candidate_ips = [clean_ip]
    elif clean_ip not in candidate_ips and clean_ip not in ("127.0.0.1", "localhost"):
        candidate_ips.insert(0, clean_ip)
    
    # Include all server local interface IPs
    for sip in get_all_lan_ips():
        if sip not in candidate_ips and sip != "127.0.0.1":
            candidate_ips.append(sip)

    TERMINATED_ROOMS.discard(code)
    ROOMS[code] = {
        "code": code,
        "host": host,
        "mode": mode,
        "players": max(len(p_list), players),
        "players_list": p_list,
        "created_at": now_str,
        "host_ip": clean_ip,
        "candidate_ips": candidate_ips,
        "port": int(data.get("port", 7777)),
        "status": "ACTIVE",
        "broadcast_message": "",
        "message_id": 0,
        "last_seen": time.time()
    }
    TOTAL_ROOMS_CREATED += 1
    add_console_log("ROOM", f"🎮 تم إنشاء الغرفة #{code} بواسطة المضيف '{host}' (IP: {clean_ip} | الطور: {mode})", "SUCCESS")
    return 200, {
        "success": True, 
        "room": ROOMS[code], 
        "total_rooms_created": TOTAL_ROOMS_CREATED,
        "active_rooms_count": len(ROOMS)
    }

def handle_rooms_close(data: dict) -> tuple[int, dict]:
    global ROOMS
    code = str(data.get("room_code", "")).strip().upper()
    if code in ROOMS:
        room = ROOMS.pop(code)
        add_console_log("ROOM", f"🚪 تم إغلاق الغرفة #{code} بواسطة المضيف '{room.get('host', '')}'", "INFO")
    return 200, {"success": True, "active_rooms_count": len(ROOMS)}

def handle_rooms_terminate(data: dict) -> tuple[int, dict]:
    global ROOMS, TERMINATED_ROOMS, ACTIVE_SESSIONS
    code = str(data.get("room_code", "")).strip().upper()
    if not code:
        return 400, {"success": False, "error": "Missing room code"}
    
    TERMINATED_ROOMS.add(code)
    room = ROOMS.pop(code, None)
    
    # Also pop any matching session or players belonging to this room
    removed_sessions = []
    for s_id in list(ACTIVE_SESSIONS.keys()):
        s = ACTIVE_SESSIONS[s_id]
        if code in s.get("mode", "") or code == s.get("id", "") or code in s.get("player", ""):
            removed_sessions.append(ACTIVE_SESSIONS.pop(s_id))
    
    host_name = room.get("host", "") if room else ""
    if not host_name and removed_sessions:
        host_name = removed_sessions[0].get("player", "لاعب")
    if not host_name:
        host_name = "اللاعبين"

    add_console_log("ADMIN", f"🛑 قام القائد بقفل وإغلاق الغرفة #{code} وطرد جميع لاعبيها فوراً (المضيف: {host_name})!", "ERROR")
    return 200, {
        "success": True, 
        "message": f"تم إغلاق الغرفة #{code} وطرد اللاعبين بنجاح وفصلهم!",
        "active_rooms_count": len(ROOMS)
    }

def handle_rooms_message(data: dict) -> tuple[int, dict]:
    global ROOMS, GLOBAL_BROADCAST
    code = str(data.get("room_code", "")).strip().upper()
    msg = str(data.get("message", "")).strip()
    if not msg:
        return 400, {"success": False, "error": "رسالة فارغة"}
    
    import time
    msg_id = int(time.time() * 1000)
    
    GLOBAL_BROADCAST = {
        "message": msg,
        "id": msg_id,
        "room_code": code
    }
    
    for r_code in ROOMS:
        ROOMS[r_code]["broadcast_message"] = msg
        ROOMS[r_code]["message_id"] = msg_id
    
    if not code or code == "ALL":
        add_console_log("ADMIN", f"📢 أرسل القائد كلمة في نص الشاشة لجميع اللاعبين: '{msg}'", "SUCCESS")
        return 200, {"success": True, "message": f"تم إرسال '{msg}' في نص شاشات اللاعبين فوراً!"}
    
    if code in ROOMS:
        add_console_log("ADMIN", f"💬 أرسل القائد كلمة للاعبي الغرفة #{code}: '{msg}'", "INFO")
        return 200, {"success": True, "message": f"تم إرسال '{msg}' في نص الشاشة بنجاح!"}
    else:
        add_console_log("ADMIN", f"📢 أرسل القائد كلمة للاعبين: '{msg}'", "INFO")
        return 200, {"success": True, "message": f"تم إرسال '{msg}' في نص الشاشة بنجاح!"}

def handle_rooms_check(code: str) -> tuple[int, dict]:
    global GLOBAL_EMERGENCY_ALARM, GLOBAL_BROADCAST
    code = code.strip().upper()
    alarm_info = dict(GLOBAL_EMERGENCY_ALARM)
    b_msg = GLOBAL_BROADCAST.get("message", "")
    b_id = GLOBAL_BROADCAST.get("id", 0)
    if code in TERMINATED_ROOMS:
        return 200, {
            "code": code, 
            "active": False, 
            "terminated": True, 
            "emergency_alarm": alarm_info,
            "message": b_msg,
            "message_id": b_id,
            "broadcast_message": b_msg,
            "broadcast_id": b_id
        }
    if code in ROOMS:
        ROOMS[code]["last_seen"] = time.time()
        room = ROOMS[code]
        r_msg = room.get("broadcast_message", "") or b_msg
        r_id = room.get("message_id", 0) or b_id
        return 200, {
            "code": code, 
            "active": True, 
            "terminated": False,
            "host_ip": room.get("host_ip", ""),
            "candidate_ips": room.get("candidate_ips", [room.get("host_ip", "")]),
            "port": room.get("port", 7777),
            "message": r_msg,
            "message_id": r_id,
            "broadcast_message": r_msg,
            "broadcast_id": r_id,
            "emergency_alarm": alarm_info
        }
    return 200, {
        "code": code, 
        "active": False, 
        "terminated": False, 
        "emergency_alarm": alarm_info,
        "message": b_msg,
        "message_id": b_id,
        "broadcast_message": b_msg,
        "broadcast_id": b_id
    }


# ==============================================================================
# TITAN STRIKE 3D - USER DATABASE & MOBILE AUTH SYSTEM (SQLite/JSON Engine)
# ==============================================================================
import secrets
import hashlib

DATA_DIR = BASE_DIR / "data" if (BASE_DIR / "data").exists() else (BASE_DIR / "server" / "data" if (BASE_DIR / "server" / "data").exists() else BASE_DIR / "server" / "data")
DATA_DIR.mkdir(parents=True, exist_ok=True)
ACCOUNTS_DB_FILE = DATA_DIR / "accounts.json"

def load_accounts_db() -> dict:
    if not ACCOUNTS_DB_FILE.exists():
        default_db = {
            "users": {
                "admin": {
                    "username": "admin",
                    "password_hash": hashlib.sha256("admin2026".encode()).hexdigest(),
                    "display_name": "👑 Commander Seif",
                    "role": "admin",
                    "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                    "level": 20,
                    "coins": 99999,
                    "wins": 99,
                    "kills": 500,
                    "unlocked_heroes": [0, 1, 2, 3, 4],
                    "device": "Command Center"
                }
            },
            "sessions": {}
        }
        save_accounts_db(default_db)
        return default_db
    try:
        with open(ACCOUNTS_DB_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[!] Error loading accounts db: {e}")
        return {"users": {}, "sessions": {}}

def save_accounts_db(db: dict) -> None:
    try:
        with open(ACCOUNTS_DB_FILE, "w", encoding="utf-8") as f:
            json.dump(db, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[!] Error saving accounts db: {e}")

def auth_register(username: str, password: str, nickname: str = "", device: str = "", ip: str = "", device_id: str = "") -> tuple[bool, str, dict]:
    u = str(username).strip().lower()
    p = str(password).strip()
    if len(u) < 2:
        return False, "⚠️ اسم المستخدم يجب أن يكون حرفين على الأقل!", {}
    if len(p) < 3:
        return False, "⚠️ كلمة المرور يجب أن تكون 3 أحرف على الأقل!", {}
    
    db = load_accounts_db()
    if u in db.get("users", {}):
        return False, "⚠️ هذا الحساب مسجل بالفعل! جرب تسجيل الدخول.", {}
    
    token = secrets.token_hex(16)
    user_record = {
        "username": u,
        "password_hash": hashlib.sha256(p.encode()).hexdigest(),
        "display_name": nickname if nickname else u,
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "last_login": time.strftime("%Y-%m-%d %H:%M:%S"),
        "last_ip": ip,
        "device_id": device_id,
        "role": "player",
        "level": 1,
        "coins": 500,
        "wins": 0,
        "kills": 0,
        "unlocked_heroes": [1, 2, 3, 4],
        "device": device if device else "Mobile/Browser"
    }
    db.setdefault("users", {})[u] = user_record
    db.setdefault("sessions", {})[token] = u
    save_accounts_db(db)
    add_console_log("AUTH", f"🎉 تسجيل لاعب جديد بنجاح: '{u}' (IP: {ip}, Dev: {device_id})", "SUCCESS")
    return True, f"🎉 تم إنشاء الحساب بنجاح! مرحباً بك يا {u}", {"token": token, "username": u, "user": user_record}

def auth_login(username: str, password: str, device: str = "", ip: str = "", device_id: str = "") -> tuple[bool, str, dict]:
    u = str(username).strip().lower()
    p = str(password).strip()
    db = load_accounts_db()
    users = db.get("users", {})
    if u not in users:
        return False, "⚠️ اسم المستخدم غير مسجل! اضغط على 'إنشاء حساب جديد'.", {}
    
    p_hash = hashlib.sha256(p.encode()).hexdigest()
    user_record = users[u]
    if user_record.get("password_hash") != p_hash:
        return False, "⚠️ كلمة المرور غير صحيحة!", {}
    
    token = secrets.token_hex(16)
    db.setdefault("sessions", {})[token] = u
    user_record["last_login"] = time.strftime("%Y-%m-%d %H:%M:%S")
    if ip:
        user_record["last_ip"] = ip
    if device_id:
        user_record["device_id"] = device_id
    if device:
        user_record["device"] = device
    save_accounts_db(db)
    add_console_log("AUTH", f"🔑 تسجيل دخول ناجح للاعب: '{u}' (IP: {ip})", "INFO")
    return True, f"🔑 تم تسجيل الدخول بنجاح! مرحباً بعودتك يا {u}", {"token": token, "username": u, "user": user_record}

def auth_quick_auth(username: str, device: str = "", ip: str = "", device_id: str = "") -> tuple[bool, str, dict]:
    u = str(username).strip()
    if len(u) < 2:
        return False, "⚠️ اسم المستخدم يجب أن يكون حرفين على الأقل!", {}
    
    db = load_accounts_db()
    users = db.setdefault("users", {})
    now_str = time.strftime("%Y-%m-%d %H:%M:%S")
    
    matched_key = None
    for k in users:
        if k.lower() == u.lower():
            matched_key = k
            break
            
    if matched_key:
        user_record = users[matched_key]
        user_record["last_login"] = now_str
        if ip:
            user_record["last_ip"] = ip
        if device_id:
            user_record["device_id"] = device_id
        if device:
            user_record["device"] = device
        token = secrets.token_hex(16)
        db.setdefault("sessions", {})[token] = matched_key
        save_accounts_db(db)
        add_console_log("AUTH", f"✨ دخول سريع بالاسم فقط: '{matched_key}' (IP: {ip}, Dev: {device_id})", "SUCCESS")
        return True, f"🎉 مرحباً بك مجدداً يا {matched_key}!", {"token": token, "username": matched_key, "user": user_record}
    else:
        token = secrets.token_hex(16)
        user_record = {
            "username": u,
            "password_hash": "",
            "display_name": u,
            "created_at": now_str,
            "last_login": now_str,
            "last_ip": ip,
            "device_id": device_id,
            "role": "player",
            "level": 1,
            "coins": 500,
            "wins": 0,
            "kills": 0,
            "unlocked_heroes": [1, 2, 3, 4],
            "device": device if device else "Mobile/Android"
        }
        users[u] = user_record
        db.setdefault("sessions", {})[token] = u
        save_accounts_db(db)
        add_console_log("AUTH", f"🎉 إنشاء مستخدم جديد سريعاً: '{u}' (IP: {ip}, Dev: {device_id})", "SUCCESS")
        return True, f"🎉 تم إنشاء الحساب بنجاح! مرحباً بك يا {u}", {"token": token, "username": u, "user": user_record}

def auth_get_user(token: str) -> dict:
    if not token:
        return None
    db = load_accounts_db()
    u = db.get("sessions", {}).get(token)
    if u and u in db.get("users", {}):
        return db["users"][u]
    return None

def auth_get_stats() -> dict:
    db = load_accounts_db()
    users = db.get("users", {})
    leaderboard = []
    for uname, udata in users.items():
        leaderboard.append({
            "username": uname,
            "display_name": udata.get("display_name", uname),
            "level": udata.get("level", 1),
            "wins": udata.get("wins", 0),
            "kills": udata.get("kills", 0),
            "role": udata.get("role", "player")
        })
    leaderboard.sort(key=lambda x: (x["wins"], x["level"]), reverse=True)
    return {
        "total_registered_players": len(users),
        "active_sessions": len(db.get("sessions", {})),
        "leaderboard": leaderboard[:10]
    }


# ==============================================================================
# TITAN STRIKE 3D - LIVE PARTY INVITATIONS SYSTEM
# ==============================================================================
GLOBAL_PARTY_INVITES = {} # { "username": [ { "id": "...", "from": "...", "time": ... } ] }
GLOBAL_PARTY_GROUPS = {}  # { "username": ["userA", "userB"] }

def handle_party_invite(data: dict) -> tuple[int, dict]:
    from_u = str(data.get("from", "")).strip().lower()
    to_u = str(data.get("to", "")).strip().lower()
    if not from_u or not to_u:
        return 400, {"success": False, "message": "بيانات الدعوة غير مكتملة!"}
    
    inv_id = secrets.token_hex(6)
    inv_obj = {
        "id": inv_id,
        "from": from_u,
        "to": to_u,
        "time": time.time()
    }
    inv_list = GLOBAL_PARTY_INVITES.setdefault(to_u, [])
    if not any(i["from"] == from_u for i in inv_list):
        inv_list.append(inv_obj)
    
    add_console_log("PARTY", f"💌 دعوة بارتي جديدة: من '{from_u}' إلى '{to_u}'", "INFO")
    return 200, {"success": True, "message": f"🎉 تم إرسال دعوة اللعب معاً إلى {to_u} بنجاح!", "invite_id": inv_id}

def handle_party_respond(data: dict) -> tuple[int, dict]:
    u = str(data.get("user", "")).strip().lower()
    from_u = str(data.get("from", "")).strip().lower()
    action = str(data.get("action", "reject")).strip().lower()
    inv_id = str(data.get("invite_id", "")).strip()

    if u in GLOBAL_PARTY_INVITES:
        GLOBAL_PARTY_INVITES[u] = [i for i in GLOBAL_PARTY_INVITES[u] if i.get("id") != inv_id and i.get("from") != from_u]

    if action == "accept":
        members = list(set([u, from_u]))
        if from_u in GLOBAL_PARTY_GROUPS:
            members = list(set(GLOBAL_PARTY_GROUPS[from_u] + [u]))
        if u in GLOBAL_PARTY_GROUPS:
            members = list(set(members + GLOBAL_PARTY_GROUPS[u]))
        for m in members:
            GLOBAL_PARTY_GROUPS[m] = members
        add_console_log("PARTY", f"✅ قبل اللاعب '{u}' دعوة البارتي من '{from_u}' وانضم للبارتي! الأعضاء: {members}", "SUCCESS")
        return 200, {"success": True, "action": "accept", "party_members": members, "message": f"تم قبول دعوة {from_u} ودخول البارتي!"}
    else:
        add_console_log("PARTY", f"❌ رفض اللاعب '{u}' دعوة البارتي من '{from_u}'.", "INFO")
        return 200, {"success": True, "action": "reject", "message": "تم رفض الدعوة."}

def handle_party_leave(data: dict) -> tuple[int, dict]:
    u = str(data.get("user", "")).strip().lower()
    if u in GLOBAL_PARTY_GROUPS:
        old_members = GLOBAL_PARTY_GROUPS.pop(u, [])
        for m in old_members:
            if m in GLOBAL_PARTY_GROUPS:
                GLOBAL_PARTY_GROUPS[m] = [x for x in GLOBAL_PARTY_GROUPS[m] if x != u]
        add_console_log("PARTY", f"🚪 غادر اللاعب '{u}' البارتي.", "INFO")
    return 200, {"success": True, "message": "تمت مغادرة البارتي بنجاح."}


# ==============================================================================
# TITAN STRIKE 3D - LIVE FRIEND REQUESTS SYSTEM
# ==============================================================================
GLOBAL_FRIEND_REQUESTS = {} # { "username": [ { "id": "...", "from": "...", "time": ... } ] }

def handle_friend_request(data: dict) -> tuple[int, dict]:
    from_u = str(data.get("from", "")).strip().lower()
    to_u = str(data.get("to", "")).strip().lower()
    if not from_u or not to_u:
        return 400, {"success": False, "message": "بيانات طلب الصداقة غير مكتملة!"}
    if from_u == to_u:
        return 400, {"success": False, "message": "لا يمكنك إرسال طلب صداقة لنفسك!"}
    
    db = load_accounts_db()
    users = db.get("users", {})
    from_record = users.get(from_u, {})
    if to_u in from_record.get("friends", []):
        return 200, {"success": True, "message": f"ℹ️ {to_u} موجود بالفعل في قائمة أصدقائك!"}

    req_id = secrets.token_hex(6)
    req_obj = {
        "id": req_id,
        "from": from_u,
        "to": to_u,
        "time": time.time()
    }
    req_list = GLOBAL_FRIEND_REQUESTS.setdefault(to_u, [])
    if not any(i["from"] == from_u for i in req_list):
        req_list.append(req_obj)

    add_console_log("FRIENDS", f"👥 طلب صداقة جديد: من '{from_u}' إلى '{to_u}'", "INFO")
    return 200, {"success": True, "message": f"🎉 تم إرسال طلب الصداقة إلى {to_u} بنجاح!", "request_id": req_id}

def handle_friend_respond(data: dict) -> tuple[int, dict]:
    u = str(data.get("user", "")).strip().lower()
    from_u = str(data.get("from", "")).strip().lower()
    action = str(data.get("action", "reject")).strip().lower()
    req_id = str(data.get("request_id", "")).strip()

    if u in GLOBAL_FRIEND_REQUESTS:
        GLOBAL_FRIEND_REQUESTS[u] = [i for i in GLOBAL_FRIEND_REQUESTS[u] if i.get("id") != req_id and i.get("from") != from_u]

    if action == "accept":
        db = load_accounts_db()
        users = db.setdefault("users", {})
        if u not in users:
            users[u] = {"friends": []}
        if from_u not in users:
            users[from_u] = {"friends": []}
        
        u_friends = users[u].setdefault("friends", [])
        if from_u not in u_friends:
            u_friends.append(from_u)
            
        from_friends = users[from_u].setdefault("friends", [])
        if u not in from_friends:
            from_friends.append(u)
            
        save_accounts_db(db)
        add_console_log("FRIENDS", f"✅ قبل اللاعب '{u}' طلب صداقة '{from_u}' وأصبحا أصدقاء!", "SUCCESS")
        return 200, {"success": True, "action": "accept", "message": f"تم قبول صداقة {from_u} بنجاح!"}
    else:
        add_console_log("FRIENDS", f"❌ رفض اللاعب '{u}' طلب صداقة '{from_u}'.", "INFO")
        return 200, {"success": True, "action": "reject", "message": "تم رفض طلب الصداقة."}

def handle_friend_list(username: str) -> dict:
    u = username.strip().lower()
    db = load_accounts_db()
    friends = db.get("users", {}).get(u, {}).get("friends", [])
    return {"success": True, "friends": friends}


# ==============================================================================
# TITAN STRIKE 3D - LIVE TELEGRAM SUPPORT REQUESTS SYSTEM
# ==============================================================================
GLOBAL_SUPPORT_REQUESTS = {} # { "username": { "status": "PENDING" | "ACCEPTED" | "REJECTED", "time": ... } }

def handle_support_request(data: dict) -> tuple[int, dict]:
    u = str(data.get("user", "")).strip().lower()
    dev = str(data.get("device", "Unknown Device")).strip()
    if not u:
        return 400, {"success": False, "message": "اسم المستخدم مطلوب!"}

    if GLOBAL_SUPPORT_REQUESTS.get(u, {}).get("status") == "REJECTED":
        return 200, {"success": True, "status": "REJECTED", "message": "تم رفض طلب المحادثة مسبقاً من الأدمن."}

    GLOBAL_SUPPORT_REQUESTS[u] = {"status": "PENDING", "time": time.time(), "device": dev}
    add_console_log("SUPPORT", f"🔔 طلب محادثة جديد من اللاعب '{u}' عبر جهاز '{dev}'", "INFO")

    try:
        from discord_bot import send_support_request_to_discord
        send_support_request_to_discord(u, dev)
    except Exception as ex:
        add_console_log("SUPPORT", f"⚠️ فشل إرسال تنبيه الديسكورد: {ex}", "WARNING")

    return 200, {
        "success": True,
        "status": "PENDING",
        "message": "📩 تم إرسال طلب المحادثة للأدمن في ديسكورد بنجاح! بانتظار الموافقة..."
    }

def handle_support_status(username: str) -> dict:
    u = username.strip().lower()
    status = "NONE"
    status_file = BASE_DIR / "data" / "support_status.json"
    if status_file.exists():
        try:
            with open(status_file, "r", encoding="utf-8") as f:
                saved = json.load(f)
                if u in saved:
                    status = str(saved[u].get("status", "NONE"))
        except Exception:
            pass
    if status == "NONE":
        req = GLOBAL_SUPPORT_REQUESTS.get(u, {})
        status = req.get("status", "NONE")
    return {
        "success": True,
        "status": status,
        "bot_username": "Cyberfort",
        "chat_url": "https://discord.com/channels/1564558038826754110/1564558039556816918"
    }

def send_json_response(handler, data, status_code: int = 200):
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    handler.send_response(status_code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")
    handler.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
    handler.end_headers()
    handler.wfile.write(body)

def handle_ip_auto_login(handler, parsed):
    clean_ip = handler.client_address[0]
    if clean_ip.startswith("::ffff:"):
        clean_ip = clean_ip[7:]
    parsed_q = urllib.parse.parse_qs(parsed.query)
    dev_id = parsed_q.get("device_id", [""])[0].strip()
    
    db = load_accounts_db()
    users = db.get("users", {})
    matched_user = None
    matched_uname = ""
    
    # 1. Match by device_id
    if dev_id:
        for uname, udata in users.items():
            if udata.get("device_id") and udata.get("device_id") == dev_id:
                matched_user = udata
                matched_uname = uname
                break
    
    # 2. Match by IP address
    if not matched_user and clean_ip not in ["127.0.0.1", "localhost", ""]:
        for uname, udata in users.items():
            if udata.get("last_ip") == clean_ip:
                matched_user = udata
                matched_uname = uname
                break
    
    # 3. Fallback for localhost
    if not matched_user and clean_ip in ["127.0.0.1", "localhost"]:
        if "admin" in users:
            matched_user = users["admin"]
            matched_uname = "admin"
        elif users:
            matched_uname = list(users.keys())[0]
            matched_user = users[matched_uname]

    if matched_user and matched_uname:
        token = secrets.token_hex(16)
        db.setdefault("sessions", {})[token] = matched_uname
        matched_user["last_login"] = time.strftime("%Y-%m-%d %H:%M:%S")
        matched_user["last_ip"] = clean_ip
        if dev_id:
            matched_user["device_id"] = dev_id
        save_accounts_db(db)
        add_console_log("AUTH", f"⚡ دخول تلقائي لحساب '{matched_uname}' عبر IP ({clean_ip})", "SUCCESS")
        send_json_response(handler, {
            "success": True,
            "found": True,
            "username": matched_uname,
            "token": token,
            "user": matched_user,
            "message": f"🎉 تم التعرف على جهازك ({clean_ip}) والدخول تلقائياً!"
        })
    else:
        send_json_response(handler, {
            "success": True,
            "found": False,
            "ip": clean_ip,
            "message": "لا يوجد حساب مسجل لهذا الـ IP حالياً."
        })

class UpdateRequestHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PUBLIC_DIR), **kwargs)

    def check_router_access(self) -> bool:
        """Blocks access to the website & admin controls if client is not on the local router Wi-Fi/LAN."""
        if IS_CLOUD or os.environ.get("DISABLE_ROUTER_CHECK", "").lower() in ("1", "true", "yes"):
            return True
        client_ip = self.client_address[0]
        if not is_local_router_client(client_ip):
            self.send_response(403)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            blocked_html = f"""<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>403 - الوصول محظور (خاص براوتر الشبكة المحلية فقط)</title>
<style>
body {{ background: #070a12; color: #fff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; text-align: center; }}
.card {{ background: rgba(239, 68, 68, 0.08); border: 2px solid #ef4444; border-radius: 20px; padding: 40px 30px; max-width: 540px; box-shadow: 0 0 50px rgba(239, 68, 68, 0.25); }}
.badge {{ display: inline-block; background: #ef4444; color: #fff; padding: 8px 18px; border-radius: 30px; font-weight: bold; font-size: 14px; margin-bottom: 20px; }}
h1 {{ color: #ff5c5c; margin: 0 0 15px; font-size: 26px; }}
p {{ color: #cbd5e1; font-size: 16px; line-height: 1.7; margin: 0 0 20px; }}
.info-box {{ background: rgba(0, 0, 0, 0.4); border-radius: 12px; padding: 14px; font-size: 14px; color: #94a3b8; font-family: monospace; }}
</style>
</head>
<body>
<div class="card">
<div class="badge">🛡️ حماية شبكة الراوتر مفعلة</div>
<h1>⛔ محظور: الموقع متاح فقط من الراوتر</h1>
<p>عذراً! هذا الموقع ولوحة التحكم مخصصة <b>حصرياً للأجهزة المتصلة براوتر الواي فاي المنزلي (Local Wi-Fi / Router)</b>.</p>
<p>لا يُسمح لأي جهاز خارج نطاق الراوتر بالدخول إلى لوحة التحكم أو الموقع.</p>
<div class="info-box">عنوان IP جهازك: <b>{client_ip}</b> (خارج شبكة الراوتر)</div>
</div>
</body>
</html>"""
            self.wfile.write(blocked_html.encode("utf-8"))
            return False
        return True

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/version":
            send_json_response(self, load_version_info())
            return

        elif path == "/api/game_config":
            send_json_response(self, load_game_config())
            return

        elif path == "/api/party/invites":
            u = urllib.parse.parse_qs(parsed.query).get("user", [""])[0].strip().lower()
            now = time.time()
            invs = [inv for inv in GLOBAL_PARTY_INVITES.get(u, []) if now - inv.get("time", 0) < 300]
            GLOBAL_PARTY_INVITES[u] = invs
            send_json_response(self, {"success": True, "invites": invs, "party_members": GLOBAL_PARTY_GROUPS.get(u, [u] if u else [])})
            return

        elif path == "/api/friends/requests":
            u = urllib.parse.parse_qs(parsed.query).get("user", [""])[0].strip().lower()
            now = time.time()
            reqs = [r for r in GLOBAL_FRIEND_REQUESTS.get(u, []) if now - r.get("time", 0) < 600]
            GLOBAL_FRIEND_REQUESTS[u] = reqs
            send_json_response(self, {"success": True, "requests": reqs})
            return

        elif path == "/api/accounts/ip_auto_login":
            handle_ip_auto_login(self, parsed)
            return

        elif path == "/api/friends/list":
            u = urllib.parse.parse_qs(parsed.query).get("user", [""])[0].strip().lower()
            send_json_response(self, handle_friend_list(u))
            return

        elif path == "/api/support/status":
            u = urllib.parse.parse_qs(parsed.query).get("user", [""])[0].strip().lower()
            send_json_response(self, handle_support_status(u))
            return

        elif path == "/api/auth/stats":
            send_json_response(self, auth_get_stats())
            return

        elif path == "/api/accounts/ip_auto_login":
            handle_ip_auto_login(self, parsed)
            return

        elif path == "/api/auth/me":
            token = urllib.parse.parse_qs(parsed.query).get("token", [""])[0]
            if not token:
                auth_hdr = self.headers.get("Authorization", "")
                if auth_hdr.startswith("Bearer "):
                    token = auth_hdr.split("Bearer ")[-1].strip()
            user_data = auth_get_user(token)
            if user_data:
                send_json_response(self, {"success": True, "user": user_data})
            else:
                send_json_response(self, {"success": False, "message": "غير مسجل"}, status_code=401)
            return

        elif path == "/api/server_status":
            cfg_data = load_game_config()
            st = cfg_data.get("server_status", "OPEN").upper()
            send_json_response(self, {
                "status": st, 
                "is_open": (st == "OPEN"),
                "emergency_alarm": GLOBAL_EMERGENCY_ALARM,
                "broadcast_message": GLOBAL_BROADCAST.get("message", ""),
                "broadcast_id": GLOBAL_BROADCAST.get("id", 0),
                "ai_duel_trigger": GLOBAL_AI_DUEL_TRIGGER
            })
            return

        elif path == "/api/devices":
            if not self.check_router_access():
                return
            cfg_data = load_game_config()
            dev_sec = cfg_data.get("device_security", {
                "whitelist_enabled": True,
                "allowed_devices": [],
                "pending_devices": []
            })
            send_json_response(self, dev_sec)
            return

        elif path == "/api/verify_network":
            client_ip = self.client_address[0]
            forwarded = self.headers.get("X-Forwarded-For")
            if forwarded:
                client_ip = forwarded.split(",")[0].strip()
            server_wan = get_wan_ip()
            is_local = is_local_router_client(client_ip)
            is_same_wan = (client_ip == server_wan)
            allowed = is_local or is_same_wan
            send_json_response(self, {
                "allowed": allowed,
                "client_ip": client_ip,
                "server_wan": server_wan,
                "is_local_router": is_local,
                "network_match": allowed,
                "message": "تم التحقق من شبكة الاتصال بنجاح" if allowed else "شبكة إنترنت غير مطابقة لشبكة السيرفر"
            })
            return

        elif path == "/api/network_info":
            if not self.check_router_access():
                return
            net_data = {
                "lan_ip": get_lan_ip(),
                "all_lan_ips": get_all_lan_ips(),
                "wan_ip": get_wan_ip(),
                "port": PORT,
                "lan_url": f"http://{get_lan_ip()}:{PORT}",
                "wan_url": f"http://{get_wan_ip()}:{PORT}",
                "router_only_protection": True,
                "status": "ONLINE"
            }
            send_json_response(self, net_data)
            return

        elif path == "/api/rooms":
            now_ts = time.time()
            stale_keys = [k for k, v in ACTIVE_SESSIONS.items() if (now_ts - v.get("last_seen", 0)) > 180]
            for k in stale_keys:
                ACTIVE_SESSIONS.pop(k, None)
            
            # Clean up stale rooms not seen in 90 seconds
            stale_rooms = [k for k, v in ROOMS.items() if (now_ts - v.get("last_seen", now_ts)) > 90]
            for k in stale_rooms:
                ROOMS.pop(k, None)
            
            total_active = len(ROOMS) + len(ACTIVE_SESSIONS)
            total_players = len(ACTIVE_SESSIONS) + sum(max(len(r.get("players_list", [])), int(r.get("players", 1))) for r in ROOMS.values())
            send_json_response(self, {
                "total_created": max(TOTAL_ROOMS_CREATED, total_active),
                "active_count": total_active,
                "rooms": list(ROOMS.values()),
                "active_sessions": list(ACTIVE_SESSIONS.values()),
                "online_players_count": total_players,
                "emergency_alarm": GLOBAL_EMERGENCY_ALARM
            })
            return

        elif path == "/api/rooms/check":
            code = urllib.parse.parse_qs(parsed.query).get("code", [""])[0]
            status_code, res = handle_rooms_check(code)
            send_json_response(self, res, status_code)
            return

        elif path == "/api/console_logs":
            send_json_response(self, {"logs": CONSOLE_LOGS})
            return



        elif path.startswith("/downloads/"):
            filename = path.replace("/downloads/", "").strip("/")
            file_path = DOWNLOADS_DIR / filename
            if file_path.is_file():
                file_size = file_path.stat().st_size
                self.send_response(200)
                if filename.lower().endswith(".ipa"):
                    self.send_header("Content-Type", "application/octet-stream")
                else:
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

        elif path in ("/guest", "/guest.html"):
            guest_file = PUBLIC_DIR / "guest.html"
            if guest_file.is_file():
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                with open(guest_file, "rb") as f:
                    self.wfile.write(f.read())
                return
            else:
                self.send_error(404, "guest.html not found")
                return

        elif path == "/" or path == "/index.html":
            if not self.check_router_access():
                return
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

        if not self.check_router_access():
            return
        super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/launch_game":
            global GLOBAL_AI_DUEL_TRIGGER
            GLOBAL_AI_DUEL_TRIGGER["active"] = True
            GLOBAL_AI_DUEL_TRIGGER["id"] = int(time.time() * 1000)
            GLOBAL_AI_DUEL_TRIGGER["room_code"] = "AI1V1"
            GLOBAL_AI_DUEL_TRIGGER["message"] = "⚔️ انطلقت مبارزة 1v1 مع CyberAI! جاري إدخالك للساحة..."
            try:
                import subprocess, psutil
                godot_running = any("godot" in p.name().lower() for p in psutil.process_iter(['name']))
                if not godot_running:
                    godot_exe = r"C:\Users\Administrator\OneDrive\Desktop\Godot.exe"
                    proj_dir = r"c:\Users\Administrator\OneDrive\Desktop\Game"
                    subprocess.Popen([godot_exe, "--path", proj_dir])
            except Exception as ex:
                print("Launch game error:", ex)
            send_json_response(self, {"success": True, "message": "تم إرسال أمر فتح ودخول اللعبة بنجاح!"})
            return

        elif path == "/api/sync_github_ipa":
            if not self.check_router_access():
                return
            try:
                from sync_github_ipa import sync_ipa_from_github_or_local
                result = sync_ipa_from_github_or_local()
                send_json_response(self, result)
            except Exception as e:
                self.send_error(500, f"Sync error: {e}")
            return

        elif path == "/api/publish":
            if not self.check_router_access():
                return
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
                send_json_response(self, {"success": True, "message": "Version updated successfully!", "data": updated_data})
            except Exception as e:
                self.send_error(500, f"Publish error: {e}")
            return

        elif path == "/api/game_config":
            if not self.check_router_access():
                return
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
                send_json_response(self, {
                    "success": True, 
                    "message": "Game configuration updated successfully!", 
                    "config": current_config
                })
            except Exception as e:
                self.send_error(500, f"Game config error: {e}")
            return

        elif path in ("/api/server_status", "/api/server_toggle"):
            if not self.check_router_access():
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                current_config = load_game_config()
                current_st = current_config.get("server_status", "OPEN").upper()
                if "status" in data:
                    new_st = str(data["status"]).strip().upper()
                else:
                    new_st = "CLOSED" if current_st == "OPEN" else "OPEN"
                
                current_config["server_status"] = new_st
                save_game_config(current_config)
                
                send_json_response(self, {
                    "success": True,
                    "status": new_st,
                    "is_open": (new_st == "OPEN"),
                    "message": f"Server status updated to {new_st}"
                })
            except Exception as e:
                self.send_error(500, f"Server toggle error: {e}")
            return

        elif path == "/api/shutdown":
            if not self.check_router_access():
                return
            send_json_response(self, {"success": True, "message": "Server process is stopping..."})
            def kill_soon():
                time.sleep(0.5)
                os._exit(0)
            threading.Thread(target=kill_soon, daemon=True).start()
            return

        elif path == "/api/verify_device":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_verify_device_request(data, self.client_address[0])
                self.send_response(code)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps(resp, ensure_ascii=False).encode("utf-8"))
                return
            except Exception as e:
                self.send_error(500, f"Verify device error: {e}")
            return

        elif path == "/api/party/invite":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_party_invite(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/friends/request":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_friend_request(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/friends/respond":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_friend_respond(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/support/request":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_support_request(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/party/leave":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_party_leave(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/party/respond":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_party_respond(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/friends/request":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_friend_request(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/friends/respond":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_friend_respond(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/support/request":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_support_request(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        if path == "/api/auth/register":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                u = data.get("username", "")
                p = data.get("password", "")
                nick = data.get("nickname", "")
                dev = data.get("device", self.headers.get("User-Agent", "Mobile"))
                clean_ip = self.client_address[0]
                if clean_ip.startswith("::ffff:"): clean_ip = clean_ip[7:]
                dev_id = str(data.get("device_id", "")).strip()
                ok, msg, res_data = auth_register(u, p, nick, dev, ip=clean_ip, device_id=dev_id)
                send_json_response(self, {"success": ok, "message": msg, "data": res_data}, status_code=200 if ok else 400)
            except Exception as e:
                send_json_response(self, {"success": False, "message": f"خطأ: {e}"}, status_code=500)
            return

        elif path == "/api/auth/quick_auth":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                u = data.get("username", "")
                dev = data.get("device", self.headers.get("User-Agent", "Mobile"))
                clean_ip = self.client_address[0]
                if clean_ip.startswith("::ffff:"): clean_ip = clean_ip[7:]
                dev_id = str(data.get("device_id", "")).strip()
                ok, msg, res_data = auth_quick_auth(u, dev, ip=clean_ip, device_id=dev_id)
                send_json_response(self, {"success": ok, "message": msg, "data": res_data}, status_code=200 if ok else 400)
            except Exception as e:
                send_json_response(self, {"success": False, "message": f"خطأ: {e}"}, status_code=500)
            return

        elif path == "/api/auth/login":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                u = data.get("username", "")
                p = data.get("password", "")
                dev = data.get("device", self.headers.get("User-Agent", "Mobile"))
                clean_ip = self.client_address[0]
                if clean_ip.startswith("::ffff:"): clean_ip = clean_ip[7:]
                dev_id = str(data.get("device_id", "")).strip()
                ok, msg, res_data = auth_login(u, p, dev, ip=clean_ip, device_id=dev_id)
                send_json_response(self, {"success": ok, "message": msg, "data": res_data}, status_code=200 if ok else 400)
            except Exception as e:
                send_json_response(self, {"success": False, "message": f"خطأ: {e}"}, status_code=500)
            return

        elif path == "/api/request_device":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_device_request_submission(data, self.client_address[0])
                self.send_response(code)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps(resp, ensure_ascii=False).encode("utf-8"))
                return
            except Exception as e:
                self.send_error(500, f"Request device error: {e}")
            return

        elif path == "/api/device_action":
            if not self.check_router_access():
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                action = data.get("action", "")
                target_id = str(data.get("device_id", "")).strip()
                custom_name = str(data.get("device_name", "")).strip()

                current_config = load_game_config()
                dev_sec = current_config.get("device_security", {
                    "whitelist_enabled": True,
                    "allowed_devices": [],
                    "pending_devices": []
                })

                if action == "approve":
                    clean_id = target_id.strip("{} ").lower()
                    # Find in pending or create
                    found_item = None
                    new_pending = []
                    for p in dev_sec.get("pending_devices", []):
                        if p.get("id", "").strip("{} ").lower() == clean_id:
                            found_item = p
                        else:
                            new_pending.append(p)
                    dev_sec["pending_devices"] = new_pending

                    # Add to allowed
                    dev_name = custom_name or (found_item.get("name") if found_item else "📱 هاتف مصرح له (Authorized Mobile)")
                    allowed = dev_sec.get("allowed_devices", [])
                    # Remove existing if any
                    allowed = [a for a in allowed if a.get("id", "").strip("{} ").lower() != clean_id]
                    allowed.append({
                        "id": target_id,
                        "name": dev_name,
                        "status": "APPROVED",
                        "approved_at": "2026-10-19"
                    })
                    dev_sec["allowed_devices"] = allowed

                elif action == "remove":
                    clean_id = target_id.strip("{} ").lower()
                    dev_sec["allowed_devices"] = [
                        a for a in dev_sec.get("allowed_devices", [])
                        if a.get("id", "").strip("{} ").lower() != clean_id
                    ]

                elif action == "toggle_whitelist":
                    new_val = not dev_sec.get("whitelist_enabled", True)
                    dev_sec["whitelist_enabled"] = new_val

                elif action == "add_manual":
                    clean_id = target_id.strip("{} ").lower()
                    allowed = dev_sec.get("allowed_devices", [])
                    allowed = [a for a in allowed if a.get("id", "").strip("{} ").lower() != clean_id]
                    allowed.append({
                        "id": target_id,
                        "name": custom_name or "📱 جهاز يدوي مصرح له",
                        "status": "APPROVED",
                        "approved_at": "2026-10-19"
                    })
                    dev_sec["allowed_devices"] = allowed

                elif action == "approve_with_action":
                    clean_id = target_id.strip("{} ").lower()
                    selected_act = str(data.get("selected_action", "FULL_ACCESS")).upper()
                    
                    found_item = None
                    new_pending = []
                    for p in dev_sec.get("pending_devices", []):
                        if p.get("id", "").strip("{} ").lower() == clean_id:
                            found_item = p
                        else:
                            new_pending.append(p)
                    dev_sec["pending_devices"] = new_pending
                    
                    base_name = custom_name or (found_item.get("name") if found_item else "📱 جهاز مصرح")
                    allowed = dev_sec.get("allowed_devices", [])
                    allowed = [a for a in allowed if a.get("id", "").strip("{} ").lower() != clean_id]
                    
                    import datetime
                    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
                    
                    if selected_act == "FULL_ACCESS":
                        allowed.append({
                            "id": target_id,
                            "name": f"{base_name} 👑 (كامل الصلاحيات)",
                            "status": "APPROVED",
                            "role": "FULL_ACCESS",
                            "approved_at": now_str
                        })
                        add_console_log("ADMIN", f"👑 وافق القائد على جهاز '{base_name}' ومنحه صلاحيات كاملة!", "SUCCESS")
                    elif selected_act == "NORMAL_PLAYER":
                        allowed.append({
                            "id": target_id,
                            "name": f"{base_name} 🎮 (لاعب عادي)",
                            "status": "APPROVED",
                            "role": "NORMAL_PLAYER",
                            "approved_at": now_str
                        })
                        add_console_log("ADMIN", f"🎮 وافق القائد على جهاز '{base_name}' كلاعب عادي", "INFO")
                    elif selected_act == "GIFT_COINS":
                        allowed.append({
                            "id": target_id,
                            "name": f"{base_name} 🎁 (مكافأة 1000 عملة)",
                            "status": "APPROVED",
                            "role": "GIFT_COINS",
                            "approved_at": now_str
                        })
                        add_console_log("ADMIN", f"🎁 وافق القائد على جهاز '{base_name}' وأهداه 1000 عملة ذهبية!", "SUCCESS")
                    elif selected_act == "BLOCK":
                        add_console_log("ADMIN", f"⛔ رفض وحظر القائد طلب الجهاز '{base_name}'", "ERROR")
                    
                    dev_sec["allowed_devices"] = allowed

                current_config["device_security"] = dev_sec
                save_game_config(current_config)

                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps({
                    "success": True,
                    "action": action,
                    "device_security": dev_sec,
                    "message": "Device action completed successfully!"
                }, ensure_ascii=False).encode("utf-8"))
                return
            except Exception as e:
                self.send_error(500, f"Device action error: {e}")
            return

        elif path == "/api/rooms/create":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_rooms_create(data, self.client_address[0])
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Rooms create error: {e}")
            return

        elif path == "/api/rooms/close":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_rooms_close(data)
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Rooms close error: {e}")
            return

        elif path == "/api/rooms/terminate":
            if not self.check_router_access():
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_rooms_terminate(data)
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Rooms terminate error: {e}")
            return

        elif path == "/api/rooms/message":
            if not self.check_router_access():
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_rooms_message(data)
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Rooms message error: {e}")
            return

        elif path == "/api/rooms/update":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_rooms_update(data)
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Rooms update error: {e}")
            return

        elif path == "/api/sessions/update":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_session_update(data, self.client_address[0])
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Session update error: {e}")
            return

        elif path == "/api/emergency_alarm":
            if not self.check_router_access():
                return
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                active = bool(data.get("active", True))
                msg = str(data.get("message", "🚨 إنذار طارئ من قائد السيرفر!")).strip()
                global GLOBAL_EMERGENCY_ALARM
                GLOBAL_EMERGENCY_ALARM = {
                    "active": active,
                    "message": msg,
                    "id": int(time.time() * 1000)
                }
                status_txt = "تفعيل" if active else "إيقاف"
                add_console_log("ADMIN", f"🚨 قام القائد بـ ({status_txt}) صفارة الإنذار العامة باللعبة: '{msg}'", "WARNING" if active else "INFO")
                send_json_response(self, {"success": True, "emergency_alarm": GLOBAL_EMERGENCY_ALARM})
            except Exception as e:
                self.send_error(500, f"Alarm error: {e}")
            return

        elif path == "/api/ai/chat":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                prompt = str(data.get("prompt", "")).strip()
                ctx = str(data.get("context", "general")).strip()
                code, resp = call_gemini_ai(prompt, ctx)
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"AI chat error: {e}")
            return

        elif path == "/api/console_log":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                msg = str(data.get("message", "")).strip()
                source = str(data.get("source", "GAME")).strip()
                lvl = str(data.get("level", "INFO")).strip()
                if msg:
                    add_console_log(source, msg, lvl)
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps({"success": True}).encode("utf-8"))
            except Exception as e:
                self.send_error(500, f"Console log error: {e}")
            return

        elif path == "/api/console_clear":
            if not self.check_router_access():
                return
            CONSOLE_LOGS.clear()
            add_console_log("SYSTEM", "تم مسح سجلات الكونسول بواسطة القائد 🧹", "INFO")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "message": "Console cleared"}).encode("utf-8"))
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

class GuestRequestHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    """
    Dedicated Guest & Player handler (Port 8081):
    - Default page '/' serves guest.html
    - All admin POST endpoints (/api/publish, /api/game_config, /api/toggle_server, /api/shutdown, /api/device_action) are blocked (403 Forbidden)
    - Allows read-only APIs (/api/server_status, /api/game_config, /api/version) and downloads
    - Allows /api/request_device and /api/verify_device
    - Accessible from any client without router restriction
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PUBLIC_DIR), **kwargs)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/party/invites":
            u = urllib.parse.parse_qs(parsed.query).get("user", [""])[0].strip().lower()
            now = time.time()
            invs = [inv for inv in GLOBAL_PARTY_INVITES.get(u, []) if now - inv.get("time", 0) < 300]
            GLOBAL_PARTY_INVITES[u] = invs
            send_json_response(self, {"success": True, "invites": invs, "party_members": GLOBAL_PARTY_GROUPS.get(u, [u] if u else [])})
            return

        elif path == "/api/friends/requests":
            u = urllib.parse.parse_qs(parsed.query).get("user", [""])[0].strip().lower()
            now = time.time()
            reqs = [r for r in GLOBAL_FRIEND_REQUESTS.get(u, []) if now - r.get("time", 0) < 600]
            GLOBAL_FRIEND_REQUESTS[u] = reqs
            send_json_response(self, {"success": True, "requests": reqs})
            return

        elif path == "/api/accounts/ip_auto_login":
            handle_ip_auto_login(self, parsed)
            return

        elif path == "/api/friends/list":
            u = urllib.parse.parse_qs(parsed.query).get("user", [""])[0].strip().lower()
            send_json_response(self, handle_friend_list(u))
            return

        elif path == "/api/support/status":
            u = urllib.parse.parse_qs(parsed.query).get("user", [""])[0].strip().lower()
            send_json_response(self, handle_support_status(u))
            return

        elif path in ("/", "/index.html", "/guest", "/guest.html"):
            guest_file = PUBLIC_DIR / "guest.html"
            if guest_file.is_file():
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                with open(guest_file, "rb") as f:
                    self.wfile.write(f.read())
                return
            else:
                self.send_error(404, "guest.html not found")
                return

        elif path == "/api/server_status":
            cfg_data = load_game_config()
            st = cfg_data.get("server_status", "OPEN").upper()
            send_json_response(self, {
                "status": st, 
                "is_open": (st == "OPEN"),
                "emergency_alarm": GLOBAL_EMERGENCY_ALARM,
                "broadcast_message": GLOBAL_BROADCAST.get("message", ""),
                "broadcast_id": GLOBAL_BROADCAST.get("id", 0),
                "ai_duel_trigger": GLOBAL_AI_DUEL_TRIGGER
            })
            return

        elif path == "/api/game_config":
            send_json_response(self, load_game_config())
            return

        elif path == "/api/auth/stats":
            send_json_response(self, auth_get_stats())
            return

        elif path == "/api/accounts/ip_auto_login":
            handle_ip_auto_login(self, parsed)
            return

        elif path == "/api/auth/me":
            token = urllib.parse.parse_qs(parsed.query).get("token", [""])[0]
            if not token:
                auth_hdr = self.headers.get("Authorization", "")
                if auth_hdr.startswith("Bearer "):
                    token = auth_hdr.split("Bearer ")[-1].strip()
            user_data = auth_get_user(token)
            if user_data:
                send_json_response(self, {"success": True, "user": user_data})
            else:
                send_json_response(self, {"success": False, "message": "غير مسجل"}, status_code=401)
            return

        elif path == "/api/version":
            send_json_response(self, load_version_info())
            return

        elif path == "/api/rooms":
            now_ts = time.time()
            stale_keys = [k for k, v in ACTIVE_SESSIONS.items() if (now_ts - v.get("last_seen", 0)) > 180]
            for k in stale_keys:
                ACTIVE_SESSIONS.pop(k, None)
            
            # Clean up stale rooms not seen in 90 seconds
            stale_rooms = [k for k, v in ROOMS.items() if (now_ts - v.get("last_seen", now_ts)) > 90]
            for k in stale_rooms:
                ROOMS.pop(k, None)
            
            total_active = len(ROOMS) + len(ACTIVE_SESSIONS)
            total_players = len(ACTIVE_SESSIONS) + sum(max(len(r.get("players_list", [])), int(r.get("players", 1))) for r in ROOMS.values())
            send_json_response(self, {
                "total_created": max(TOTAL_ROOMS_CREATED, total_active),
                "active_count": total_active,
                "rooms": list(ROOMS.values()),
                "active_sessions": list(ACTIVE_SESSIONS.values()),
                "online_players_count": total_players,
                "emergency_alarm": GLOBAL_EMERGENCY_ALARM
            })
            return

        elif path == "/api/rooms/check":
            code = urllib.parse.parse_qs(parsed.query).get("code", [""])[0]
            status_code, res = handle_rooms_check(code)
            send_json_response(self, res, status_code)
            return

        elif path.startswith("/downloads/"):
            filename = path.replace("/downloads/", "").strip("/")
            file_path = DOWNLOADS_DIR / filename
            if file_path.is_file():
                file_size = file_path.stat().st_size
                self.send_response(200)
                if filename.lower().endswith(".ipa"):
                    self.send_header("Content-Type", "application/octet-stream")
                else:
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

        super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/party/invite":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_party_invite(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/friends/request":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_friend_request(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/friends/respond":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_friend_respond(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/support/request":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_support_request(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/party/leave":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_party_leave(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/party/respond":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_party_respond(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/friends/request":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_friend_request(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/friends/respond":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_friend_respond(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/support/request":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, res = handle_support_request(data)
                send_json_response(self, res, status_code=code)
            except Exception as e:
                send_json_response(self, {"success": False, "message": str(e)}, status_code=500)
            return

        elif path == "/api/auth/register":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                u = data.get("username", "")
                p = data.get("password", "")
                nick = data.get("nickname", "")
                dev = data.get("device", self.headers.get("User-Agent", "Mobile"))
                clean_ip = self.client_address[0]
                if clean_ip.startswith("::ffff:"): clean_ip = clean_ip[7:]
                dev_id = str(data.get("device_id", "")).strip()
                ok, msg, res_data = auth_register(u, p, nick, dev, ip=clean_ip, device_id=dev_id)
                send_json_response(self, {"success": ok, "message": msg, "data": res_data}, status_code=200 if ok else 400)
            except Exception as e:
                send_json_response(self, {"success": False, "message": f"خطأ: {e}"}, status_code=500)
            return

        elif path == "/api/auth/quick_auth":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                u = data.get("username", "")
                dev = data.get("device", self.headers.get("User-Agent", "Mobile"))
                clean_ip = self.client_address[0]
                if clean_ip.startswith("::ffff:"): clean_ip = clean_ip[7:]
                dev_id = str(data.get("device_id", "")).strip()
                ok, msg, res_data = auth_quick_auth(u, dev, ip=clean_ip, device_id=dev_id)
                send_json_response(self, {"success": ok, "message": msg, "data": res_data}, status_code=200 if ok else 400)
            except Exception as e:
                send_json_response(self, {"success": False, "message": f"خطأ: {e}"}, status_code=500)
            return

        elif path == "/api/auth/login":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                u = data.get("username", "")
                p = data.get("password", "")
                dev = data.get("device", self.headers.get("User-Agent", "Mobile"))
                clean_ip = self.client_address[0]
                if clean_ip.startswith("::ffff:"): clean_ip = clean_ip[7:]
                dev_id = str(data.get("device_id", "")).strip()
                ok, msg, res_data = auth_login(u, p, dev, ip=clean_ip, device_id=dev_id)
                send_json_response(self, {"success": ok, "message": msg, "data": res_data}, status_code=200 if ok else 400)
            except Exception as e:
                send_json_response(self, {"success": False, "message": f"خطأ: {e}"}, status_code=500)
            return

        elif path == "/api/request_device":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_device_request_submission(data, self.client_address[0])
                send_json_response(self, resp, code)
                return
            except Exception as e:
                self.send_error(500, f"Request device error: {e}")
                return

        elif path == "/api/verify_device":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_verify_device_request(data, self.client_address[0])
                send_json_response(self, resp, code)
                return
            except Exception as e:
                self.send_error(500, f"Verify device error: {e}")
                return

        elif path == "/api/rooms/create":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_rooms_create(data, self.client_address[0])
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Rooms create error: {e}")
            return

        elif path == "/api/rooms/update":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_rooms_update(data)
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Rooms update error: {e}")
            return

        elif path == "/api/sessions/update":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_session_update(data, self.client_address[0])
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Session update error: {e}")
            return

        elif path == "/api/rooms/close":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                code, resp = handle_rooms_close(data)
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"Rooms close error: {e}")
            return

        elif path == "/api/console_log":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                msg = str(data.get("message", "")).strip()
                source = str(data.get("source", "GAME")).strip()
                lvl = str(data.get("level", "INFO")).strip()
                if msg:
                    add_console_log(source, msg, lvl)
                send_json_response(self, {"success": True})
            except Exception as e:
                self.send_error(500, f"Console log error: {e}")
            return

        elif path == "/api/ai/chat":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else b"{}"
            try:
                data = json.loads(body.decode("utf-8")) if body else {}
                prompt = str(data.get("prompt", "")).strip()
                ctx = str(data.get("context", "general")).strip()
                code, resp = call_gemini_ai(prompt, ctx)
                send_json_response(self, resp, code)
            except Exception as e:
                self.send_error(500, f"AI chat error: {e}")
            return

        # Block any admin modification attempts on the guest server
        send_json_response(self, {
            "error": "Forbidden",
            "message": "⛔ هذا السيرفر مخصص للزوار واللاعبين فقط (Guest Only). التحكم الكامل متاح لمدير السيرفر فقط على البورت 8080."
        }, 403)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()


def run_cloud_keep_alive() -> None:
    """Keeps Render / cloud instance alive 24/7 by pinging it before the 15-minute idle sleep threshold."""
    target_url = os.environ.get("RENDER_EXTERNAL_URL", "").strip()
    if not target_url:
        target_url = os.environ.get("KEEP_ALIVE_URL", "").strip()
    if not target_url and IS_CLOUD:
        app_name = os.environ.get("RENDER_SERVICE_NAME", "titanstrike-server").strip()
        target_url = f"https://{app_name}.onrender.com"

    if not target_url:
        return

    target_url = target_url.rstrip("/") + "/api/server_status"
    print(f"[KeepAlive] 🕒 Starting 24/7 Cloud Keep-Alive pinger to: {target_url}")
    
    time.sleep(25)
    while True:
        try:
            req = urllib.request.Request(target_url, headers={"User-Agent": "TitanStrike-KeepAlive/1.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                if resp.status == 200:
                    pass
        except Exception:
            pass
        # Sleep for 9 minutes (540s) so Render's 15-minute sleep timer is never reached!
        time.sleep(540)

def start_keep_alive_thread() -> threading.Thread:
    t = threading.Thread(target=run_cloud_keep_alive, daemon=True, name="KeepAliveAgent")
    t.start()
    return t

def run_server():
    lan_ip = get_lan_ip()
    wan_ip = get_wan_ip()

    socketserver.TCPServer.allow_reuse_address = True

    try:
        admin_httpd = socketserver.ThreadingTCPServer(("0.0.0.0", PORT), UpdateRequestHandler)
    except Exception as e:
        print(f"[!] Warning: Could not bind Admin server on port {PORT}: {e}")
        admin_httpd = None

    try:
        if not IS_CLOUD:
            guest_httpd = socketserver.ThreadingTCPServer(("0.0.0.0", GUEST_PORT), GuestRequestHandler)
        else:
            guest_httpd = None
    except Exception as e:
        print(f"[!] Warning: Could not bind Guest server on port {GUEST_PORT}: {e}")
        guest_httpd = None

    if not admin_httpd and not guest_httpd:
        print("[Error] Failed to start servers! Ports might be busy.")
        sys.exit(1)

    print("=" * 75)
    print("⚡ CyberFort: Titan Strike 3D - Live Control & Guest Server System")
    print("=" * 75)
    if admin_httpd:
        admin_thread = threading.Thread(target=admin_httpd.serve_forever, daemon=True)
        admin_thread.start()
        print(f"👑 [Admin Server] (Port {PORT}) - لوحة التحكم الكاملة والمحمية للمدير:")
        print(f"    - الرابط المحلي (Localhost):   http://localhost:{PORT}")
        print(f"    - رابط شبكة الواي فاي (Wi-Fi):  http://{lan_ip}:{PORT}")
    print()
    if guest_httpd:
        guest_thread = threading.Thread(target=guest_httpd.serve_forever, daemon=True)
        guest_thread.start()
        print(f"👥 [Guest Server] (Port {GUEST_PORT}) - سيرفر وبوابة الزوار واللاعبين:")
        print(f"    - رابط الزوار (Wi-Fi):          http://{lan_ip}:{GUEST_PORT}")
        print(f"    - رابط الإنترنت (WAN):          http://{wan_ip}:{GUEST_PORT}")
    print("=" * 75)
    # Launch Discord Bot Gemini Agent Daemon
    try:
        from discord_bot import start_discord_bot_thread
        start_discord_bot_thread()
        print("🤖 [Discord Bot Agent] نشط ويعمل بنجاح لاستقبال الأوامر وإرسال تنبيهات الأخطاء عبر ديسكورد!")
    except Exception as e:
        print(f"[!] Warning: Could not start Discord Bot: {e}")

    # Launch Cloud 24/7 Keep-Alive Thread (Prevents Render 15-min Sleep)
    try:
        start_keep_alive_thread()
    except Exception as e:
        print(f"[!] Warning: Could not start Keep-Alive thread: {e}")

    print("[*] All servers are running actively! Ready to serve clients.")
    print("[*] Press Ctrl+C anytime to stop.")
    print("=" * 75)

    add_console_log("SYSTEM", "🚀 تم تشغيل سيرفر Titan Strike 3D بنجاح!", "SUCCESS")
    add_console_log("SYSTEM", f"👑 لوحة تحكم القائد نشطة على البورت {PORT}", "INFO")
    add_console_log("SYSTEM", f"👥 بوابة الزوار نشطة على البورت {GUEST_PORT}", "INFO")

    try:
        while True:
            threading.Event().wait(3600)
    except KeyboardInterrupt:
        print("\n[*] Stopping all servers...")
        if admin_httpd:
            admin_httpd.server_close()
        if guest_httpd:
            guest_httpd.server_close()

if __name__ == "__main__":
    run_server()
