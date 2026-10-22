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

# Telegram Bot Configuration
DEFAULT_TELEGRAM_TOKEN = "8993921362:AAFglRSgWPIiNZOLPEh8JSgBrW8RWPfaQ9c"
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", DEFAULT_TELEGRAM_TOKEN).strip()

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
        except Exception as e:
            pass
    env_chat = os.environ.get("TELEGRAM_ADMIN_CHAT_ID")
    if env_chat:
        try:
            _admin_chat_ids.add(int(env_chat))
        except ValueError:
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
            f"👥 <b>اللاعبين المتصلين:</b> <code>{active_sess_cnt}</code>\n"
            f"🚪 <b>الغرف المفتوحة:</b> <code>{active_rooms_cnt}</code>\n"
            f"🚨 <b>صفارات الإنذار:</b> {alarm_txt}\n"
            f"{sys_info}"
            f"🌐 <b>IP المحلي:</b> <code>{get_lan_ip()}</code>\n"
            f"🌍 <b>IP الخارجي:</b> <code>{get_wan_ip()}</code>\n"
            f"🔌 <b>البورت:</b> <code>{PORT}</code>\n"
            f"{rooms_summary}\n"
            f"<i>💡 أجبني أو اسألني أي سؤال وسأرد عليك في لمح البصر!</i>"
        )
        return summary
    except Exception as e:
        return f"⚠️ تعذر جلب ملخص السيرفر: {e}"

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
            "🤖 أنا <b>CyberAI</b> مساعدك التنفيذي المباشر، مدعوم بـ <b>Gemini 3.5 Flash</b>.\n"
            "⚡ سأرد عليك دائماً في أقل من ثانية واحدة، وسأرسل لك إشعاراً فورياً هنا إذا حدث أي Error بالسيرفر!\n\n"
            "<b>الأوامر السريعة:</b>\n"
            "/status - فحص حالة السيرفر واللاعبين والموارد فوري\n"
            "/rooms - عرض الغرف النشطة في اللعبة\n"
            "/1v1 - إنشاء وتجهيز غرفة مبارزة 1v1 فوراً\n"
            "/alarm on - تشغيل صفارات الإنذار داخل اللعبة\n"
            "/alarm off - إيقاف صفارات الإنذار\n"
            "/announce [رسالة] - بث إعلان بمنتصف شاشات اللاعبين\n"
            "/help - قائمة الأوامر\n\n"
            "<i>💬 كلمني في أي وقت وسأجيبك فوراً كقائد وزعيم!</i>"
        )
        send_telegram_message(chat_id, welcome)
        return True

    # 2. Status variations (/status, /statues, /state, etc.)
    status_variations = ["/status", "/statues", "/state", "/statu", "حالة السيرفر", "السيرفر شغال؟", "حاله السيرفر", "status", "statues", "اخبار السيرفر", "أخبار السيرفر"]
    if cmd_lower in status_variations or any(cmd_lower == s for s in status_variations):
        send_telegram_message(chat_id, get_server_status_summary())
        return True

    # 3. Rooms
    if cmd_lower in ["/rooms", "/room", "الغرف", "الرومات", "الغرف النشطة", "rooms"]:
        from update_server import ROOMS
        if not ROOMS:
            send_telegram_message(chat_id, "🎮 <b>لا توجد غرف نشطة حالياً بالسيرفر.</b>\nيمكنك إنشاء غرفة مبارزة 1v1 بكتابة: /1v1")
        else:
            txt = f"🎮 <b>الغرف النشطة بالسيرفر ({len(ROOMS)}):</b>\n\n"
            for code, r in ROOMS.items():
                txt += f"🔑 <b>كود الغرفة:</b> <code>#{code}</code>\n"
                txt += f"👑 <b>المضيف:</b> {r.get('host', 'لاعب')}\n"
                txt += f"⚔️ <b>الطور:</b> {r.get('mode', 'مبارزة')}\n"
                txt += f"👥 <b>اللاعبين:</b> {r.get('players', 1)} ({', '.join(r.get('players_list', []))})\n\n"
            send_telegram_message(chat_id, txt)
        return True

    # 4. 1v1 Room creation
    if cmd_lower.startswith("/1v1") or any(k in cmd_lower for k in ["انشئ 1v1", "اعمل روم 1v1", "تحدي 1v1", "1v1"]):
        try:
            from update_server import execute_server_action
            ok, msg, _ = execute_server_action("create_ai_room", {"hero": "Spider Hero"}, context_type="admin_dashboard")
            reply = (
                f"⚔️ <b>أمرك يا قائدنا! تم إنشاء غرفة المبارزة 1v1 فوراً!</b>\n\n"
                f"🔑 <b>كود الغرفة:</b> <code>#AI1V1</code>\n"
                f"🎮 تم إرسال إشعار التحدي المباشر لشاشة لعبتك بالكمبيوتر/الموبايل.\n"
                f"ادخل الساحة وستجد CyberAI بانتظارك فوراً!"
            )
            send_telegram_message(chat_id, reply)
            return True
        except Exception as e:
            send_telegram_message(chat_id, f"❌ حدث خطأ أثناء إنشاء الغرفة: {e}")
            return True

    # 5. Emergency Alarm
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

    # 6. Broadcast announcement
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

    # 7. Help
    if cmd_lower in ["/help", "مساعدة", "اوامر", "الأوامر", "help"]:
        help_msg = (
            "🛠️ <b>أوامر إدارة سيرفر Titan Strike 3D السريعة:</b>\n\n"
            "/status - فحص حالة السيرفر، اللاعبين، واستهلاك الموارد\n"
            "/rooms - عرض جميع الغرف النشطة في اللعبة\n"
            "/1v1 - إنشاء غرفة مبارزة 1v1 ضد الذكاء الاصطناعي\n"
            "/alarm on - تشغيل صفارة الإنذار العامة باللعبة\n"
            "/alarm off - إيقاف صفارة الإنذار\n"
            "/announce [رسالة] - بث كلمة أو إعلان في منتصف شاشات اللاعبين\n\n"
            "💡 <b>الذكاء الاصطناعي Gemini 3.5:</b>\n"
            "يمكنك كتابة أي سؤال أو استفسار وسأجيبك في أقل من ثانية واحدة!"
        )
        send_telegram_message(chat_id, help_msg)
        return True

    return False

def handle_gemini_chat_message(chat_id: int, user_text: str) -> None:
    """Passes natural conversation to Gemini AI with fast response watchdog."""
    from update_server import call_gemini_ai
    try:
        # Fast typing indicator
        send_chat_action(chat_id, "typing")
        status_code, ai_res = call_gemini_ai(user_text, context_type="admin_dashboard")
        if ai_res.get("success") and ai_res.get("reply"):
            reply = ai_res["reply"]
            act_res = ai_res.get("action_result", "")
            if act_res:
                reply += f"\n\n⚡ <b>تم تنفيذ الأمر:</b> <code>{act_res}</code>"
            send_telegram_message(chat_id, reply)
        else:
            err = ai_res.get("error", "أمرك يا قائدنا! السيرفر شغال ومستعد لأوامرك.")
            send_telegram_message(chat_id, err)
    except Exception as e:
        send_telegram_message(chat_id, f"أمرك يا قائدنا! السيرفر شغال ومستعد لأي استفسار.")

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
            url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/getUpdates?offset={last_update_id + 1}&timeout=10"
            req = urllib.request.Request(url, headers={"User-Agent": "TitanStrikeBot/2.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
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
