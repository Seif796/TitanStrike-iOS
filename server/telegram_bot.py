import os
import sys

# Ensure UTF-8 console output on Windows to prevent UnicodeEncodeError
try:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

import json
import time
import socket
import urllib.request
import urllib.parse
import threading
from pathlib import Path

# Telegram Bot Configuration - Enforce User's Active Bot Token
ACTIVE_BOT_TOKEN = "8993921362:AAFglRSgWPIiNZOLPEh8JSgBrW8RWPfaQ9c"
env_tok = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
if env_tok and env_tok.startswith("8993921362"):
    TELEGRAM_TOKEN = env_tok
else:
    TELEGRAM_TOKEN = ACTIVE_BOT_TOKEN

BASE_DIR = Path(__file__).resolve().parent
ADMIN_CHATS_FILE = BASE_DIR / "admin_chats.json"

# Default Commander ID
_admin_chat_ids: set[int] = {6322019827}

def load_admin_chats():
    global _admin_chat_ids
    if ADMIN_CHATS_FILE.exists():
        try:
            with open(ADMIN_CHATS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                _admin_chat_ids.update(data.get("admin_chats", []))
        except Exception:
            pass

def save_admin_chats():
    try:
        with open(ADMIN_CHATS_FILE, "w", encoding="utf-8") as f:
            json.dump({"admin_chats": list(_admin_chat_ids)}, f, indent=2)
    except Exception:
        pass

load_admin_chats()

def send_chat_action(chat_id: int | str, action: str = "typing") -> None:
    """Sends typing status indicator immediately so user knows bot is replying."""
    if not TELEGRAM_TOKEN:
        return
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendChatAction"
    try:
        body = json.dumps({"chat_id": chat_id, "action": action}).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json", "User-Agent": "TitanStrikeBot/2.0"}
        )
        urllib.request.urlopen(req, timeout=3)
    except Exception:
        pass

def send_telegram_message(chat_id: int | str, text: str, reply_markup: dict = None) -> bool:
    """Sends a Telegram message using the HTTP API ultra-fast."""
    if not TELEGRAM_TOKEN:
        return False
    url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML"
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    
    try:
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json", "User-Agent": "TitanStrikeBot/2.0"}
        )
        with urllib.request.urlopen(req, timeout=8) as resp:
            ok = (resp.status == 200)
            if ok:
                safe_text = str(text)[:50].replace("\n", " ")
                print(f"[TelegramBot] 📤 تم إرسال الرد لـ {chat_id}: {safe_text}")
            return ok
    except Exception as e:
        # Fallback to plain text if HTML parsing failed
        try:
            payload.pop("parse_mode", None)
            body = json.dumps(payload).encode("utf-8")
            req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=8) as resp:
                return resp.status == 200
        except Exception:
            print(f"[TelegramBot] ⚠️ فشل إرسال الرسالة إلى {chat_id}: {e}")
            return False

def broadcast_to_admins(text: str) -> None:
    """Broadcasts an urgent notification to all registered commanders."""
    for chat_id in list(_admin_chat_ids):
        send_telegram_message(chat_id, text)

def notify_server_error(source: str, error_msg: str) -> None:
    """Sends an instant alert to the commander whenever an error occurs on the server."""
    if not _admin_chat_ids:
        return
    now_str = time.strftime("%H:%M:%S")
    alert_text = (
        f"🚨 <b>[تنبيه عاجل من السيرفر - خطأ!]</b>\n"
        f"⏰ <b>الوقت:</b> <code>{now_str}</code>\n"
        f"📍 <b>المصدر:</b> <code>{source}</code>\n"
        f"⚠️ <b>تفاصيل الخطأ:</b>\n"
        f"<pre>{error_msg[:1200]}</pre>\n\n"
        f"<i>💡 أرسل /status لفحص حالة السيرفر الآن.</i>"
    )
    broadcast_to_admins(alert_text)

def get_server_status_summary() -> str:
    """Builds a comprehensive live summary of the server in milliseconds."""
    try:
        from update_server import (
            ROOMS, ACTIVE_SESSIONS, GLOBAL_EMERGENCY_ALARM, GLOBAL_BROADCAST,
            load_game_config, get_lan_ip, get_wan_ip, PORT, GUEST_PORT
        )
        cfg = load_game_config()
        st = cfg.get("server_status", "OPEN").upper()
        status_emoji = "🟢 مفتوح ومتاح (ONLINE)" if st == "OPEN" else "🔴 مغلق للصيانة (CLOSED)"
        
        active_rooms_cnt = len(ROOMS)
        active_sess_cnt = len(ACTIVE_SESSIONS)
        alarm_active = GLOBAL_EMERGENCY_ALARM.get("active", False)
        alarm_txt = "🚨 شغال الآن!" if alarm_active else "✅ هادئ (متوقف)"
        
        now_str = time.strftime("%Y-%m-%d %H:%M:%S")
        
        sys_info = ""
        try:
            import psutil
            cpu = psutil.cpu_percent(interval=None)
            mem = psutil.virtual_memory().percent
            sys_info = f"💻 <b>المعالج:</b> {cpu}% | 🧠 <b>الرام:</b> {mem}%\n"
        except Exception:
            pass

        # Player list details
        players_details = []
        for s_id, s in list(ACTIVE_SESSIONS.items()):
            p_name = s.get("player", "لاعب")
            p_mode = s.get("mode", "متصل باللعبة")
            p_hero = s.get("hero", "بطل")
            players_details.append(f"  • 👤 <b>{p_name}</b> ({p_hero}) - <i>{p_mode}</i>")
        
        for code, r in list(ROOMS.items()):
            for pl in r.get("players_list", []):
                if not any(pl in d for d in players_details):
                    players_details.append(f"  • 👤 <b>{pl}</b> - <i>غرفة #{code}</i>")
        
        total_online = max(active_sess_cnt, len(players_details))
        players_section = f"👥 <b>اللاعبين المتصلين:</b> <code>{total_online}</code>\n"
        if players_details:
            players_section += "\n".join(players_details[:6]) + "\n"
        else:
            players_section += "  <i>(لا يوجد لاعبين متصلين حالياً)</i>\n"

        rooms_summary = ""
        if ROOMS:
            rooms_summary = "\n<b>🎮 الغرف النشطة الحالية:</b>\n"
            for code, r in list(ROOMS.items())[:5]:
                p_cnt = len(r.get("players_list", []))
                host = r.get("host", "لاعب")
                mode = r.get("mode", "مبارزة")
                rooms_summary += f"  • <b>#{code}</b> | {mode} | الهوست: {host} ({p_cnt} لاعبين)\n"
        else:
            rooms_summary = "\n🎮 <b>الغرف النشطة:</b> لا توجد غرف مفتوحة حالياً.\n"

        summary = (
            f"⚡ <b>[تقرير حالة سيرفر Titan Strike 3D]</b>\n"
            f"📅 <b>التوقيت:</b> <code>{now_str}</code>\n\n"
            f"📡 <b>حالة السيرفر:</b> {status_emoji}\n"
            f"{players_section}"
            f"🚪 <b>الغرف المفتوحة:</b> <code>{active_rooms_cnt}</code>\n"
            f"🚨 <b>صفارات الإنذار:</b> {alarm_txt}\n"
            f"{sys_info}"
            f"🌐 <b>IP المحلي:</b> <code>{get_lan_ip()}</code>\n"
            f"🌍 <b>IP الخارجي:</b> <code>{get_wan_ip()}</code>\n"
            f"🔌 <b>البورت:</b> <code>{PORT}</code>\n"
            f"{rooms_summary}\n"
            f"<i>💡 أجبني أو اطلب مني أي تعديل وسأنفذه فوراً!</i>"
        )
        return summary
    except Exception as e:
        return f"⚠️ تعذر جلب ملخص السيرفر: {e}"

def execute_code_or_file_action(prompt: str) -> tuple[bool, str]:
    """Restricts AI strictly to answering questions and in-game actions only (no code/file modifications)."""
    p = prompt.strip().lower()
    
    # 1. Reject any code/system file modifications
    if any(k in p for k in ["عدل الكود", "تعديل الكود", "غير الكود", "احذف كود", "شيل كود", "احذف ملف", "مسح ملف"]):
        return True, "🛡️ تم حظر تعديل الأكواد والملفات بأمرك يا قائدنا! الذكاء الاصطناعي مخصص فقط للرد على أسئلتك وتنفيذ الأوامر داخل اللعبة (إنشاء غرف، إعلانات، إنذار، فحص السيرفر)."

    # 2. In-game room closing (safe in-game action)
    if any(k in p for k in ["احذف", "حذف", "امسح", "مسح", "اقفل"]) and any(r in p for r in ["روم", "غرفة", "غرفه", "الرومات", "الغرف"]):
        from update_server import ROOMS, handle_rooms_terminate
        count = len(ROOMS)
        for code in list(ROOMS.keys()):
            handle_rooms_terminate({"room_code": code})
        return True, f"🗑️ تم قفل وحذف جميع الغرف داخل اللعبة ({count} غرفة) بنجاح يا قائدنا!"

    return False, ""

def handle_user_command(chat_id: int, text: str) -> bool:
    """Executes special commands or queries in < 0.1 second."""
    cmd = text.strip()
    cmd_lower = cmd.lower()
    
    # 1. Start Command
    if cmd_lower.startswith("/start"):
        _admin_chat_ids.add(chat_id)
        save_admin_chats()
        welcome = (
            "👑 <b>أهلاً بك يا قائدنا سيف في بوت Titan Strike 3D الذكي!</b>\n\n"
            "🤖 أنا <b>CyberAI</b> مساعدك التنفيذي المباشر، شغال معاك 24 ساعة بدون توقف!\n"
            "⚡ أرد على كل أسئلتك، وأنَفّذ أوامرك داخل اللعبة فوراً!\n\n"
            "<b>الأوامر السريعة:</b>\n"
            "/status - فحص حالة السيرفر واللاعبين والموارد فوري\n"
            "/rooms - عرض الغرف النشطة في اللعبة\n"
            "/1v1 - إنشاء وتجهيز غرفة مبارزة 1v1 فوراً\n"
            "/alarm on - تشغيل صفارات الإنذار داخل اللعبة\n"
            "/alarm off - إيقاف صفارات الإنذار\n"
            "/announce [رسالة] - بث إعلان بمنتصف شاشات اللاعبين\n"
            "/help - قائمة الأوامر\n\n"
            "<i>💬 كلمني في أي وقت بالعامية وسأجيبك فوراً كقائد وزعيم!</i>"
        )
        send_telegram_message(chat_id, welcome)
        return True

    # 2. Greetings & Check-ins ("عامل ايه", "الو", "ازيك", etc.)
    greetings = ["عامل ايه", "عامل ايخ", "عامل إيه", "الو", "ألو", "هلا", "مرحبا", "سلام عليكم", "صباح الخير", "مساء الخير", "انت هنا", "فينك"]
    if any(cmd_lower == g or cmd_lower.startswith(g) for g in greetings):
        reply = (
            "👑 <b>الحمد لله يا قائدنا! أنا هنا وشغال معاك 24 ساعة ومتابع السيرفر خطوة بخطوة!</b> ⚡\n\n"
            "السيرفر شغال وتمام التمام، وأنا مستعد لتنفيذ أي أمر تطلبه: تعديل كود، فحص السيرفر، أو تحدي مبارزة 1v1!\n"
            "<i>طلبك إيه يا زعيم؟</i>"
        )
        send_telegram_message(chat_id, reply)
        return True

    # 3. Status variations (/status, /statues, /state, etc.)
    status_variations = [
        "/status", "/statues", "/state", "/statu", "/stats",
        "status", "statues", "state", "stats",
        "حالة السيرفر", "حاله السيرفر", "السيرفر شغال؟", "السيرفر شغال", "اخبار السيرفر", "أخبار السيرفر",
        "مين بيلعب", "مين متصل", "اللاعبين", "كم لاعب"
    ]
    if cmd_lower in status_variations or any(cmd_lower == s for s in status_variations) or ("حالة" in cmd_lower and "سيرفر" in cmd_lower):
        send_telegram_message(chat_id, get_server_status_summary())
        return True

    # 4. Rooms list query (only when inquiring about rooms)
    if cmd_lower in ["/rooms", "/room", "الغرف", "الرومات", "الغرف النشطة", "rooms"] or (cmd_lower.startswith("عرض") and "غرف" in cmd_lower):
        from update_server import ROOMS
        if not ROOMS:
            send_telegram_message(chat_id, "🎮 <b>لا توجد غرف نشطة حالياً بالسيرفر.</b>\nيمكنك إنشاء غرفة مبارزة فوراً بكتابة:\n<i>اعمل لي الغرف</i> أو <i>/1v1</i>")
        else:
            txt = f"🎮 <b>الغرف النشطة بالسيرفر ({len(ROOMS)}):</b>\n\n"
            for code, r in ROOMS.items():
                txt += f"🔑 <b>كود الغرفة:</b> <code>#{code}</code>\n"
                txt += f"👑 <b>المضيف:</b> {r.get('host', 'لاعب')}\n"
                txt += f"⚔️ <b>الطور:</b> {r.get('mode', 'مبارزة')}\n"
                txt += f"👥 <b>اللاعبين:</b> {r.get('players', 1)} ({', '.join(r.get('players_list', []))})\n\n"
            send_telegram_message(chat_id, txt)
        return True

    # 5. Room Creation & 1v1 Duel against CyberAI (instant < 0.1s execution)
    is_room_create = False
    if cmd_lower.startswith("/1v1") or cmd_lower.startswith("/create") or cmd_lower.startswith("/createroom"):
        is_room_create = True
    else:
        create_verbs = ["اعمل", "سوي", "انشئ", "أنشئ", "افتح", "كريت", "جهز", "ادخل", "خش", "نلعب", "العب", "هات", "طلع"]
        room_nouns = ["غرفة", "غرفه", "غرف", "الغرف", "الغرفه", "الغرفة", "روم", "رومات", "الروم", "الرومات", "1v1", "تحدي", "مبارزة", "مبارزه"]
        if any(v in cmd_lower for v in create_verbs) and any(n in cmd_lower for n in room_nouns):
            is_room_create = True
        elif any(phrase in cmd_lower for phrase in [
            "اعمل لي الغرف", "اعمل الغرف", "سوي الغرف", "اعمل روم", "اعمل لي روم", "اعمل غرفه", "اعمل غرفة",
            "سوي روم", "سوي غرفة", "سوي غرفه", "انشئ روم", "افتح روم", "افتح غرفه", "افتح غرفة",
            "خش اللعبة", "خش العبه", "ادخل اللعبة", "ادخل العبه", "العب معاك", "العب معايا", "نلعب سوا", "نلعب مع بعض"
        ]):
            is_room_create = True

    if is_room_create:
        try:
            from update_server import execute_server_action
            ok, msg, _ = execute_server_action("create_ai_room", {"hero": "Spider Hero"}, context_type="admin_dashboard")
            reply = (
                "⚔️ <b>سمعاً وطاعة يا قائدنا سيف! تم إنشاء وتجهيز الغرفة بنجاح!</b>\n\n"
                "🔑 <b>كود الغرفة:</b> <code>#AI1V1</code>\n"
                "🎮 تم بث إشعار التحدي فوراً في منتصف شاشات اللعبة بالكمبيوتر والموبايل!\n"
                "ادخل الساحة وستجد CyberAI بانتظارك فوراً يا زعيم! ⚡"
            )
            send_telegram_message(chat_id, reply)
            return True
        except Exception as e:
            send_telegram_message(chat_id, f"❌ حدث خطأ أثناء إنشاء الغرفة: {e}")
            return True

    # 6. Direct Code / File / Config modification
    executed, exec_msg = execute_code_or_file_action(text)
    if executed:
        send_telegram_message(chat_id, f"👑 <b>سمعاً وطاعة يا قائدنا!</b>\n\n{exec_msg}")
        return True

    # 7. Emergency Alarm
    if cmd_lower.startswith("/alarm") or "صفارة" in cmd_lower or "إنذار" in cmd_lower:
        active = not any(k in cmd_lower for k in ["off", "stop", "اطفي", "وقف", "0", "إلغاء"])
        try:
            from update_server import execute_server_action
            ok, msg, _ = execute_server_action("emergency_alarm", {"active": active}, context_type="admin_dashboard")
            status_t = "تشغيل 🚨" if active else "إيقاف ✅"
            send_telegram_message(chat_id, f"تم {status_t} صفارات الإنذار في اللعبة بنجاح يا قائدنا!")
            return True
        except Exception as e:
            send_telegram_message(chat_id, f"❌ خطأ: {e}")
            return True

    # 8. Broadcast announcement
    if cmd_lower.startswith("/announce") or cmd_lower.startswith("/broadcast"):
        parts = cmd.split(maxsplit=1)
        if len(parts) < 2 or not parts[1].strip():
            send_telegram_message(chat_id, "⚠️ يرجى كتابة نص الإعلان بعد الأمر، مثال:\n<code>/announce مرحباً بالجميع في السيرفر!</code>")
            return True
        msg_text = parts[1].strip()
        try:
            from update_server import execute_server_action
            ok, res_msg, _ = execute_server_action("broadcast_message", {"message": msg_text}, context_type="admin_dashboard")
            send_telegram_message(chat_id, f"📢 <b>تم إرسال إعلانك في منتصف شاشات جميع اللاعبين فوراً!</b>\nالرسالة: <i>{msg_text}</i>")
            return True
        except Exception as e:
            send_telegram_message(chat_id, f"❌ خطأ: {e}")
            return True

    # 9. Help
    if cmd_lower in ["/help", "مساعدة", "اوامر", "الأوامر", "help"]:
        help_msg = (
            "🛠️ <b>أوامر إدارة سيرفر Titan Strike 3D السريعة:</b>\n\n"
            "/status - فحص حالة السيرفر، اللاعبين، واستهلاك الموارد\n"
            "/rooms - عرض جميع الغرف النشطة في اللعبة\n"
            "/1v1 - إنشاء غرفة مبارزة 1v1 ضد الذكاء الاصطناعي\n"
            "/alarm on - تشغيل صفارة الإنذار العامة باللعبة\n"
            "/alarm off - إيقاف صفارة الإنذار\n"
            "/announce [رسالة] - بث كلمة أو إعلان في منتصف شاشات اللاعبين\n\n"
            "💡 <b>المهام المخصصة:</b>\n"
            "1. الإجابة على أي سؤال أو استفسار عن اللعبة والسيرفر والأبطال\n"
            "2. تنفيذ أوامر اللعبة فوراً (إنشاء غرف 1v1، إعلانات، إنذار، فحص السيرفر)"
        )
        send_telegram_message(chat_id, help_msg)
        return True

    return False

def handle_gemini_chat_message(chat_id: int, user_text: str) -> None:
    """Passes natural conversation to Gemini AI with sub-second response."""
    from update_server import call_gemini_ai
    try:
        send_chat_action(chat_id, "typing")
        status_code, ai_res = call_gemini_ai(user_text, context_type="admin_dashboard")
        if ai_res.get("success") and ai_res.get("reply"):
            reply = ai_res["reply"]
            act_res = ai_res.get("action_result", "")
            if act_res:
                reply += f"\n\n⚡ <b>تم تنفيذ الأمر:</b> <code>{act_res}</code>"
            send_telegram_message(chat_id, reply)
        else:
            send_telegram_message(chat_id, "أمرك يا قائدنا سيف! السيرفر شغال وتمام ومستعد لأي تعديل أو أمر تطلبه!")
    except Exception as e:
        send_telegram_message(chat_id, "أمرك يا قائدنا! أنا متصل بالسيرفر وجاهز لأوامرك فوراً!")

def process_single_update(update: dict) -> None:
    """Processes a single Telegram update in a non-blocking thread."""
    try:
        msg = update.get("message")
        if not msg or "text" not in msg:
            return

        chat_id = msg["chat"]["id"]
        text = msg["text"].strip()
        
        safe_name = str(msg.get("from", {}).get("first_name", "User"))
        safe_text = text.replace("\n", " ")
        print(f"[TelegramBot] 📩 وصل طلب جديد من القائد {safe_name} ({chat_id}): '{safe_text}'")
        
        if chat_id not in _admin_chat_ids:
            _admin_chat_ids.add(chat_id)
            save_admin_chats()

        # Immediate typing feedback
        send_chat_action(chat_id, "typing")

        # 1. Fast Command check
        if handle_user_command(chat_id, text):
            return

        # 2. Natural language conversation with Gemini
        handle_gemini_chat_message(chat_id, text)
    except Exception as ex:
        print(f"[TelegramBot] Error processing update: {ex}")

def run_telegram_polling() -> None:
    """Ultra-fast concurrent polling thread for receiving Telegram messages."""
    if not TELEGRAM_TOKEN or TELEGRAM_TOKEN == "YOUR_TELEGRAM_BOT_TOKEN":
        print("[TelegramBot] No bot token configured, polling disabled.")
        return

    print(f"[TelegramBot] 🚀 Starting Ultra-Fast Telegram Gemini Bot Agent (@cyberfort3d_bot)...")
    last_update_id = 0

    while True:
        try:
            url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/getUpdates?offset={last_update_id + 1}&timeout=8"
            req = urllib.request.Request(url, headers={"User-Agent": "TitanStrikeBot/2.0"})
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if not data.get("ok"):
                    time.sleep(1)
                    continue

                results = data.get("result", [])
                for update in results:
                    last_update_id = update["update_id"]
                    # Process each message concurrently in a background thread for < 1s response!
                    threading.Thread(target=process_single_update, args=(update,), daemon=True).start()

        except urllib.error.URLError:
            time.sleep(2)
        except Exception as e:
            time.sleep(1)

def start_telegram_bot_thread() -> threading.Thread:
    """Launches the Telegram bot in an independent background daemon thread."""
    t = threading.Thread(target=run_telegram_polling, daemon=True, name="TelegramBotAgent")
    t.start()
    return t

if __name__ == "__main__":
    print(f"[*] Running standalone Telegram Bot Agent (@cyberfort3d_bot)...")
    run_telegram_polling()
