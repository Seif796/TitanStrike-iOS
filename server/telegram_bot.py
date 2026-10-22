import os
import sys
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

_admin_chat_ids: set[int] = set()

def load_admin_chats():
    global _admin_chat_ids
    if ADMIN_CHATS_FILE.exists():
        try:
            with open(ADMIN_CHATS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                _admin_chat_ids = set(data.get("admin_chats", []))
        except Exception as e:
            print(f"[TelegramBot] Error loading admin chats: {e}")
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
    except Exception as e:
        print(f"[TelegramBot] Error saving admin chats: {e}")

load_admin_chats()

def send_telegram_message(chat_id: int | str, text: str, reply_markup: dict = None) -> bool:
    """Sends a Telegram message using the HTTP API."""
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
        with urllib.request.urlopen(req, timeout=12) as resp:
            ok = (resp.status == 200)
            if ok:
                print(f"[TelegramBot] 📤 تم إرسال الرد بنجاح لـ {chat_id}")
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
        f"<i>💡 يمكنك إرسال /status لفحص حالة السيرفر الآن.</i>"
    )
    broadcast_to_admins(alert_text)

def get_server_status_summary() -> str:
    """Builds a comprehensive live summary of the server."""
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
            sys_info = f"💻 <b>استهلاك المعالج:</b> {cpu}%\n🧠 <b>استهلاك الرام:</b> {mem}%\n"
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
            f"🔌 <b>البورتات:</b> Admin <code>{PORT}</code> | Guest <code>{GUEST_PORT}</code>\n"
            f"{rooms_summary}\n"
            f"<i>💡 اسألني أي سؤال باللغة العربية وسأجيبك فوراً بواسطة Gemini 3.5 Flash!</i>"
        )
        return summary
    except Exception as e:
        return f"⚠️ تعذر جلب ملخص السيرفر: {e}"

def handle_user_command(chat_id: int, text: str) -> bool:
    """Executes special commands or queries."""
    cmd = text.strip()
    cmd_lower = cmd.lower()
    
    # 1. Start Command
    if cmd_lower.startswith("/start"):
        _admin_chat_ids.add(chat_id)
        save_admin_chats()
        welcome = (
            "👑 <b>أهلاً بك يا قائدنا في المساعد الإداري الذكي لسيرفر Titan Strike 3D!</b>\n\n"
            "🤖 أنا <b>CyberAI</b> مدعوم بنموذج <b>Google Gemini 3.5 Flash</b>.\n"
            "✅ تم ربط حسابك كمدير وقائد للسيرفر بنجاح، وستصلك هنا إشعارات فورية في حال حدوث أي Error أو مشكلة بالسيرفر.\n\n"
            "<b>الأوامر السريعة:</b>\n"
            "/status - فحص حالة السيرفر واللاعبين والموارد\n"
            "/rooms - عرض الغرف النشطة في اللعبة\n"
            "/1v1 - إنشاء غرفة مبارزة 1v1 ودخول الساحة\n"
            "/alarm on - تشغيل صفارات الإنذار داخل اللعبة\n"
            "/alarm off - إيقاف صفارات الإنذار\n"
            "/announce [رسالة] - إرسال إعلان بمنتصف شاشات اللاعبين\n"
            "/help - قائمة الأوامر\n\n"
            "<i>💬 يمكنك أيضاً التحدث معي وطرح أي سؤال عن اللعبة أو السيرفر وسأجيبك فوراً!</i>"
        )
        send_telegram_message(chat_id, welcome)
        return True

    # 2. Status
    if cmd_lower in ["/status", "حالة السيرفر", "السيرفر شغال؟", "حاله السيرفر", "status"]:
        send_telegram_message(chat_id, get_server_status_summary())
        return True

    # 3. Rooms
    if cmd_lower in ["/rooms", "الغرف", "الرومات", "الغرف النشطة"]:
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
    if cmd_lower.startswith("/1v1") or any(k in cmd_lower for k in ["انشئ 1v1", "اعمل روم 1v1", "تحدي 1v1"]):
        try:
            from update_server import execute_server_action
            ok, msg, _ = execute_server_action("create_ai_room", {"hero": "Spider Hero"}, context_type="admin_dashboard")
            reply = (
                f"⚔️ <b>تم إنشاء غرفة المبارزة 1v1 بنجاح يا قائدنا!</b>\n\n"
                f"🔑 <b>كود الغرفة:</b> <code>#AI1V1</code>\n"
                f"🎮 تم إرسال إشعار الدخول المباشر لشاشة لعبتك بالكمبيوتر/الموبايل.\n"
                f"ادخل الساحة وستجد CyberAI بانتظارك فوراً!"
            )
            send_telegram_message(chat_id, reply)
            return True
        except Exception as e:
            send_telegram_message(chat_id, f"❌ حدث خطأ أثناء إنشاء الغرفة: {e}")
            return True

    # 5. Emergency Alarm
    if cmd_lower.startswith("/alarm"):
        parts = cmd.split(maxsplit=1)
        active = True
        if len(parts) > 1 and parts[1].strip().lower() in ["off", "stop", "اطفي", "وقف", "0"]:
            active = False
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
    if cmd_lower in ["/help", "مساعدة", "اوامر", "الأوامر"]:
        help_msg = (
            "🛠️ <b>أوامر إدارة سيرفر Titan Strike 3D:</b>\n\n"
            "/status - فحص حالة السيرفر، اللاعبين، واستهلاك الموارد\n"
            "/rooms - عرض جميع الغرف النشطة في اللعبة\n"
            "/1v1 - إنشاء غرفة مبارزة 1v1 ضد الذكاء الاصطناعي\n"
            "/alarm on - تشغيل صفارة الإنذار العامة باللعبة\n"
            "/alarm off - إيقاف صفارة الإنذار\n"
            "/announce [رسالة] - بث كلمة أو إعلان في منتصف شاشات اللاعبين\n\n"
            "💡 <b>الذكاء الاصطناعي Gemini 3.5:</b>\n"
            "يمكنك كتابة أي سؤال أو استفسار وسأجيبك فوراً!"
        )
        send_telegram_message(chat_id, help_msg)
        return True

    return False

def handle_gemini_chat_message(chat_id: int, user_text: str) -> None:
    """Passes natural conversation to Gemini AI with live server context."""
    from update_server import call_gemini_ai
    try:
        status_code, ai_res = call_gemini_ai(user_text, context_type="admin_dashboard")
        if ai_res.get("success") and ai_res.get("reply"):
            reply = ai_res["reply"]
            act_res = ai_res.get("action_result", "")
            if act_res:
                reply += f"\n\n⚡ <b>تم تنفيذ الأمر:</b> <code>{act_res}</code>"
            send_telegram_message(chat_id, reply)
        else:
            err = ai_res.get("error", "لم أتمكن من معالجة الطلب حالياً.")
            send_telegram_message(chat_id, f"⚠️ {err}")
    except Exception as e:
        send_telegram_message(chat_id, f"⚠️ حدث خطأ أثناء التحدث مع Gemini: {e}")

def run_telegram_polling() -> None:
    """Long-polling thread for receiving Telegram messages with zero external dependencies."""
    if not TELEGRAM_TOKEN or TELEGRAM_TOKEN == "YOUR_TELEGRAM_BOT_TOKEN":
        print("[TelegramBot] No bot token configured, polling disabled.")
        return

    print(f"[TelegramBot] 🚀 Starting Telegram Gemini Bot Agent (@cyberfort3d_bot)...")
    last_update_id = 0

    while True:
        try:
            url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/getUpdates?offset={last_update_id + 1}&timeout=15"
            req = urllib.request.Request(url, headers={"User-Agent": "TitanStrikeBot/2.0"})
            with urllib.request.urlopen(req, timeout=25) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if not data.get("ok"):
                    time.sleep(2)
                    continue

                for update in data.get("result", []):
                    last_update_id = update["update_id"]
                    msg = update.get("message")
                    if not msg or "text" not in msg:
                        continue

                    chat_id = msg["chat"]["id"]
                    text = msg["text"].strip()
                    print(f"[TelegramBot] 📩 وصل طلب جديد من القائد ({chat_id}): '{text}'")
                    
                    if chat_id not in _admin_chat_ids:
                        _admin_chat_ids.add(chat_id)
                        save_admin_chats()

                    if handle_user_command(chat_id, text):
                        continue

                    handle_gemini_chat_message(chat_id, text)

        except urllib.error.URLError as e:
            time.sleep(3)
        except Exception as e:
            time.sleep(2)

def start_telegram_bot_thread() -> threading.Thread:
    """Launches the Telegram bot in an independent background daemon thread."""
    t = threading.Thread(target=run_telegram_polling, daemon=True, name="TelegramBotAgent")
    t.start()
    return t
