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

PORT = 8080
GUEST_PORT = 8081
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
    
    act_l = str(action_name).lower()
    if any(k in act_l for k in ["room", "1v1", "duel", "game"]):
        hero_name = params.get("hero", "Spider Hero")
        code = "AI1V1"
        now_ts = time.time()
        ROOMS[code] = {
            "code": code,
            "host": "CyberAI 🤖 [BOT 1v1]",
            "mode": "⚔️ 1v1 PvP Duel vs CyberAI",
            "map_id": 0,
            "players": 1,
            "players_list": ["CyberAI 🤖"],
            "created_at": now_ts,
            "last_seen": now_ts,
            "status": "WAITING_FOR_OPPONENT",
            "is_ai_room": True,
            "ai_hero": hero_name
        }
        TOTAL_ROOMS_CREATED += 1
        msg = f"تم إنشاء وتجهيز غرفة المبارزة 1v1 بنجاح على السيرفر! كود الغرفة: #{code}"
        add_console_log("CYBER_AI", f"⚔️ دخل CyberAI السيرفر وأنشأ غرفة 1v1 بكود #{code} منتظراً المنافس في الساحة!", "SUCCESS")
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
    create_room_keywords = ["خش اللعبة", "خش العبه", "ادخل اللعبة", "ادخل العبه", "اعمل غرفة", "اعمل الغرفة", "اعمل روم", "العب معاك", "العب معايا", "نلعب سوا", "قولي الكود", "كود الغرفة", "كود الغرفه", "مبارزة 1v1", "تحدي 1v1"]
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

def call_gemini_ai(user_prompt: str, context_type: str = "general") -> tuple[int, dict]:
    """Generates intelligent game responses using Google Gemini 3.5 Flash with full executive action control."""
    user_prompt = str(user_prompt).strip()
    if not user_prompt:
        return 400, {"success": False, "error": "يرجى كتابة سؤال أو استفسار للذكاء الاصطناعي."}

    is_admin = (context_type == "admin_dashboard")
    
    if is_admin:
        sys_context = (
            "أنت 'CyberAI' - المساعد التنفيذي والذراع الأيمن لـ 'القائد' (مدير وصاحب سيرفر لعبة Titan Strike 3D). "
            "الشخص الذي يتحدث معك الآن هو 'القائد' (الأدمن وصاحب اللعبة بالكامل). خاطبه دائماً باحترام وطاعة تامة كقائد وزعيم ('أمرك يا قائدنا'، 'يا زعيم'، 'سمعاً وطاعة'). "
            "أنت تملك صلاحيات التحكم الكاملة في اللعبة والسيرفر: إنشاء غرف 1v1، إرسال إعلانات لجميع اللاعبين، تشغيل الإنذار، فتح وإغلاق السيرفر، وتعديل طاقات الأبطال. "
            "إذا طلب منك القائد دخول اللعبة أو عمل غرفة أو قال لك 'خش اللعبة واعمل الغرفة وقولي الكود كام عشان أدخل ألعب معاك'، رحب بأمره فوراً وأخبره أنك دخلت السيرفر وجهزت غرفة 1v1 باسم CyberAI، وأعطه كود الغرفة: #AI1V1 لتحديه في الساحة! "
            "إذا طلب القائد أي أمر تنفيذي، قم بتضمين تاج الأمر في نهاية ردك: <!--ACTION:{\"name\": \"<action_name>\", \"params\": {..}}--> "
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
        # Fallback offline smart response
        if is_admin:
            reply_text = "أمرك يا قائدنا! تم استلام طلبك وجاري تطبيقه في السيرفر فوراً."
        else:
            reply_text = "أهلاً بك يا بطل! أنا جاهز لمساعدتك في أي استفسار أو التحدي في الساحة!"

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
    
    TERMINATED_ROOMS.discard(code)
    ROOMS[code] = {
        "code": code,
        "host": host,
        "mode": mode,
        "players": max(len(p_list), players),
        "players_list": p_list,
        "created_at": now_str,
        "host_ip": clean_ip,
        "port": 7777,
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
        import time
        ROOMS[code]["last_seen"] = time.time()
        room = ROOMS[code]
        r_msg = room.get("broadcast_message", "") or b_msg
        r_id = room.get("message_id", 0) or b_id
        return 200, {
            "code": code, 
            "active": True, 
            "terminated": False,
            "host_ip": room.get("host_ip", ""),
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

class UpdateRequestHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PUBLIC_DIR), **kwargs)

    def check_router_access(self) -> bool:
        """Blocks access to the website & admin controls if client is not on the local router Wi-Fi/LAN."""
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

        elif path == "/api/server_status":
            cfg_data = load_game_config()
            st = cfg_data.get("server_status", "OPEN").upper()
            send_json_response(self, {
                "status": st, 
                "is_open": (st == "OPEN"),
                "emergency_alarm": GLOBAL_EMERGENCY_ALARM,
                "broadcast_message": GLOBAL_BROADCAST.get("message", ""),
                "broadcast_id": GLOBAL_BROADCAST.get("id", 0)
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

        elif path == "/api/network_info":
            if not self.check_router_access():
                return
            net_data = {
                "lan_ip": get_lan_ip(),
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
            import time
            now_ts = time.time()
            stale_keys = [k for k, v in ACTIVE_SESSIONS.items() if (now_ts - v.get("last_seen", 0)) > 45]
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

        if path == "/api/sync_github_ipa":
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
                import time
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
                import time
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

        if path in ("/", "/index.html", "/guest", "/guest.html"):
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
                "broadcast_id": GLOBAL_BROADCAST.get("id", 0)
            })
            return

        elif path == "/api/game_config":
            send_json_response(self, load_game_config())
            return

        elif path == "/api/version":
            send_json_response(self, load_version_info())
            return

        elif path == "/api/rooms":
            import time
            now_ts = time.time()
            stale_keys = [k for k, v in ACTIVE_SESSIONS.items() if (now_ts - v.get("last_seen", 0)) > 45]
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

        if path == "/api/request_device":
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
        guest_httpd = socketserver.ThreadingTCPServer(("0.0.0.0", GUEST_PORT), GuestRequestHandler)
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
