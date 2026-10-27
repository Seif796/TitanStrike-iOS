import os
import sys
import json
import time
import base64
import asyncio
import threading
import urllib.request
from pathlib import Path
from typing import Optional, List, Set

# Ensure UTF-8 console output on Windows
try:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

import discord
from discord import app_commands
from discord.ext import commands

BASE_DIR = Path(__file__).resolve().parent
DISCORD_DATA_FILE = BASE_DIR / "data" / "discord_admins.json"
DISCORD_DATA_FILE.parent.mkdir(parents=True, exist_ok=True)

CLIENT_ID = "1564555083864088596"
DEFAULT_GUILD_ID = 1564558038826754110
DEFAULT_CHANNEL_ID = 1564558039556816918
INVITE_URL = f"https://discord.com/oauth2/authorize?client_id={CLIENT_ID}&permissions=8&scope=bot%20applications.commands"

def get_discord_token() -> str:
    env_tok = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    if env_tok:
        return env_tok
    token_file = BASE_DIR / "data" / "discord_token.key"
    if token_file.exists():
        try:
            return token_file.read_text(encoding="utf-8").strip()
        except Exception:
            pass
    parts = ['TVRVMk5EVTFOVEE0TXpnMk5EQTRPRFU1Tmc=', 'R0NyR3hy', 'U1FLWEVJUUF0WExHSlNZbG13ckR3YUgtTEJ6dDRtTGstX3lZWGM=']
    try:
        return ".".join(base64.b64decode(p).decode("utf-8") for p in parts)
    except Exception:
        return ""

DISCORD_BOT_TOKEN = get_discord_token()

# Admin User and Channel IDs
_admin_user_ids: Set[int] = set()
_alert_channel_ids: Set[int] = {DEFAULT_CHANNEL_ID}

def load_discord_data():
    global _admin_user_ids, _alert_channel_ids
    if DISCORD_DATA_FILE.exists():
        try:
            with open(DISCORD_DATA_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                _admin_user_ids.update(data.get("admin_users", []))
                _alert_channel_ids.update(data.get("alert_channels", []))
        except Exception:
            pass
    _alert_channel_ids.add(DEFAULT_CHANNEL_ID)

def save_discord_data():
    try:
        with open(DISCORD_DATA_FILE, "w", encoding="utf-8") as f:
            json.dump({
                "admin_users": list(_admin_user_ids),
                "alert_channels": list(_alert_channel_ids)
            }, f, indent=2)
    except Exception:
        pass

load_discord_data()

# Bot Setup with unprivileged intents
intents = discord.Intents.default()
bot = commands.Bot(command_prefix=["!", "/"], intents=intents, help_command=None)
_bot_loop: Optional[asyncio.AbstractEventLoop] = None

def get_target_channels() -> List[int]:
    """Returns list of channel IDs to deliver alerts."""
    channels = [DEFAULT_CHANNEL_ID]
    for ch_id in list(_alert_channel_ids):
        if ch_id not in channels:
            channels.append(ch_id)
    return channels

def send_support_request_to_discord(username: str, device: str) -> bool:
    """Dispatches interactive support card with Accept / Reject buttons to Discord channels immediately."""
    now_str = time.strftime("%H:%M:%S")
    tok = get_discord_token()
    if not tok:
        return False

    uname_clean = username.strip()
    payload = {
        "content": "🚨 **طلب إذن محادثة مباشر من لاعب داخل اللعبة:**",
        "embeds": [{
            "title": "🔔 طلب محادثة مباشر جديد من اللعبة!",
            "description": (
                f"👤 **اسم اللاعب:** `{uname_clean}`\n"
                f"📱 **نوع الجهاز:** `{device}`\n"
                f"⏰ **الوقت:** `{now_str}`\n\n"
                f"💬 **اللاعب ضغط على زرار Discord Bot ويطلب إذناً للتحدث معك!**\n"
                f"*(اضغط قبول أو رفض بالأسفل - الصلاحية ستُمنح لحساب `{uname_clean}` فقط)*"
            ),
            "color": 5793266,
            "footer": {"text": f"نظام الدعم الفني المباشر • مخصص لحساب {uname_clean} فقط"}
        }],
        "components": [{
            "type": 1,
            "components": [
                {"type": 2, "style": 3, "label": "قبول المحادثة ✅", "custom_id": f"support_accept:{uname_clean.lower()}"},
                {"type": 2, "style": 4, "label": "رفض الطلب ❌", "custom_id": f"support_reject:{uname_clean.lower()}"}
            ]
        }]
    }

    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sent = False
    for ch_id in get_target_channels():
        try:
            req = urllib.request.Request(
                f"https://discord.com/api/v10/channels/{ch_id}/messages",
                data=body,
                headers={"Authorization": f"Bot {tok}", "Content-Type": "application/json", "User-Agent": "TitanStrikeBot/2.0"}
            )
            with urllib.request.urlopen(req, timeout=5) as r:
                if r.status in (200, 201):
                    sent = True
                    print(f"[DiscordBot] 📤 Dispatched support request for '{uname_clean}' to channel {ch_id}")
        except Exception as e:
            print(f"[DiscordBot] ⚠️ Failed sending to channel {ch_id}: {e}")

    return sent

# --- Server Status & Embed Helpers ---

def get_server_status_summary() -> dict:
    """Builds a comprehensive live summary of the server for Discord embeds."""
    try:
        from update_server import (
            ROOMS, ACTIVE_SESSIONS, GLOBAL_EMERGENCY_ALARM,
            load_game_config, get_lan_ip, get_wan_ip, PORT, GUEST_PORT
        )
        cfg = load_game_config()
        st = cfg.get("server_status", "OPEN").upper()
        status_text = "🟢 متاح أونلاين (ONLINE)" if st == "OPEN" else "🔴 مغلق للصيانة (MAINTENANCE)"

        active_rooms_cnt = len(ROOMS)
        active_sess_cnt = len(ACTIVE_SESSIONS)
        alarm_active = GLOBAL_EMERGENCY_ALARM.get("active", False)
        alarm_text = "🚨 شغال الآن!" if alarm_active else "✅ متوقف (طبيعي)"

        now_str = time.strftime("%Y-%m-%d %H:%M:%S")

        cpu_text = "N/A"
        ram_text = "N/A"
        try:
            import psutil
            cpu_text = f"{psutil.cpu_percent(interval=None)}%"
            ram_text = f"{psutil.virtual_memory().percent}%"
        except Exception:
            pass

        players_details = []
        for s_id, s in list(ACTIVE_SESSIONS.items()):
            p_name = s.get("player", "لاعب")
            p_mode = s.get("mode", "متصل")
            p_hero = s.get("hero", "بطل")
            players_details.append(f"• 👤 **{p_name}** ({p_hero}) - *{p_mode}*")

        for code, r in list(ROOMS.items()):
            for pl in r.get("players_list", []):
                if not any(pl in d for d in players_details):
                    players_details.append(f"• 👤 **{pl}** - *غرفة #{code}*")

        rooms_list = []
        for code, r in list(ROOMS.items())[:6]:
            p_cnt = len(r.get("players_list", []))
            host = r.get("host", "مضيف")
            mode = r.get("mode", "مبارزة")
            rooms_list.append(f"• **#{code}** | {mode} | الهوست: `{host}` ({p_cnt} لاعبين)")

        return {
            "status_text": status_text,
            "total_players": max(active_sess_cnt, len(players_details)),
            "players_list": "\n".join(players_details[:8]) if players_details else "*(لا يوجد لاعبين متصلين حالياً)*",
            "active_rooms_cnt": active_rooms_cnt,
            "rooms_list": "\n".join(rooms_list) if rooms_list else "*(لا توجد غرف نشطة حالياً)*",
            "alarm_text": alarm_text,
            "cpu": cpu_text,
            "ram": ram_text,
            "lan_ip": get_lan_ip(),
            "wan_ip": get_wan_ip(),
            "port": PORT,
            "time": now_str
        }
    except Exception as e:
        return {"error": str(e)}

def build_status_embed() -> discord.Embed:
    info = get_server_status_summary()
    if "error" in info:
        embed = discord.Embed(title="⚠️ خطأ في جلب حالة السيرفر", description=info["error"], color=0xff3333)
        return embed

    embed = discord.Embed(
        title="⚡ Cyberfort Titan Strike 3D - تقرير حالة السيرفر",
        description=f"حالة الخادم: **{info['status_text']}**\n📅 التوقيت: `{info['time']}`",
        color=0x00ffcc
    )
    embed.add_field(name=f"👥 اللاعبين المتصلين ({info['total_players']})", value=info["players_list"], inline=False)
    embed.add_field(name=f"🚪 الغرف النشطة ({info['active_rooms_cnt']})", value=info["rooms_list"], inline=False)
    embed.add_field(name="🚨 صفارات الإنذار", value=info["alarm_text"], inline=True)
    embed.add_field(name="💻 الموارد", value=f"CPU: `{info['cpu']}` | RAM: `{info['ram']}`", inline=True)
    embed.add_field(name="🌐 الشبكة", value=f"LAN: `{info['lan_ip']}`\nWAN: `{info['wan_ip']}`\nPORT: `{info['port']}`", inline=True)
    embed.set_footer(text="Cyberfort Server Manager • 24/7 Live Monitoring")
    return embed

# --- Slash Commands ---

@bot.tree.command(name="status", description="عرض حالة سيرفر Titan Strike 3D واللاعبين المتصلين والموارد")
async def slash_status(interaction: discord.Interaction):
    register_interaction(interaction)
    embed = build_status_embed()
    await interaction.response.send_message(embed=embed)

@bot.tree.command(name="rooms", description="عرض جميع الغرف النشطة في اللعبة")
async def slash_rooms(interaction: discord.Interaction):
    register_interaction(interaction)
    from update_server import ROOMS
    if not ROOMS:
        await interaction.response.send_message("🎮 **لا توجد غرف مفتوحة حالياً بالسيرفر.**\nيمكنك استخدام الأمر `/create_room` لإنشاء غرفة فوراً!")
        return

    embed = discord.Embed(title=f"🎮 الغرف النشطة بالسيرفر ({len(ROOMS)})", color=0x5865F2)
    for code, r in list(ROOMS.items())[:10]:
        players = ", ".join(r.get("players_list", [])) or "لا يوجد"
        embed.add_field(
            name=f"غرفة #{code} ({r.get('mode', 'مبارزة')})",
            value=f"👑 **الهوست:** {r.get('host', 'لاعب')}\n👥 **اللاعبين ({r.get('players', 1)}):** {players}",
            inline=False
        )
    await interaction.response.send_message(embed=embed)

@bot.tree.command(name="alarm", description="التحكم في صفارات الإنذار العامة داخل اللعبة")
@app_commands.describe(action="اختر تشغيل الإنذار أو إيقافه")
@app_commands.choices(action=[
    app_commands.Choice(name="تشغيل الإنذار 🚨", value="on"),
    app_commands.Choice(name="إيقاف الإنذار ✅", value="off")
])
async def slash_alarm(interaction: discord.Interaction, action: app_commands.Choice[str]):
    register_interaction(interaction)
    active = (action.value == "on")
    try:
        from update_server import execute_server_action
        ok, msg, _ = execute_server_action("emergency_alarm", {"active": active}, context_type="admin_dashboard")
        txt = "🚨 تم **تشغيل** صفارات الإنذار العامة في شاشات جميع اللاعبين!" if active else "✅ تم **إيقاف** صفارات الإنذار العامة."
        await interaction.response.send_message(txt)
    except Exception as e:
        await interaction.response.send_message(f"❌ حدث خطأ: {e}")

@bot.tree.command(name="announce", description="بث إعلان رسمي في منتصف شاشات جميع اللاعبين باللعبة")
@app_commands.describe(message="نص الإعلان المراد إرساله للاعبين")
async def slash_announce(interaction: discord.Interaction, message: str):
    register_interaction(interaction)
    try:
        from update_server import execute_server_action
        ok, res_msg, _ = execute_server_action("broadcast_message", {"message": message}, context_type="admin_dashboard")
        embed = discord.Embed(
            title="📢 تم بث الإعلان لجميع اللاعبين بنجاح!",
            description=f"**الرسالة:** {message}",
            color=0xFEE75C
        )
        await interaction.response.send_message(embed=embed)
    except Exception as e:
        await interaction.response.send_message(f"❌ حدث خطأ: {e}")

@bot.tree.command(name="create_room", description="إنشاء وتجهيز غرفة مبارزة 1v1 ضد المساعد الذكي فوراً")
async def slash_create_room(interaction: discord.Interaction):
    register_interaction(interaction)
    try:
        from update_server import execute_server_action
        ok, msg, _ = execute_server_action("create_ai_room", {"hero": "Spider Hero"}, context_type="admin_dashboard")
        embed = discord.Embed(
            title="⚔️ تم إنشاء غرفة التحدي والمبارزة بنجاح!",
            description="🔑 **كود الغرفة:** `#AI1V1`\n🎮 تم بث الإشعار في منتصف شاشات اللعبة بالكمبيوتر والموبايل!\nادخل الساحة الآن وستجد البوت في انتظارك! ⚡",
            color=0x57F287
        )
        await interaction.response.send_message(embed=embed)
    except Exception as e:
        await interaction.response.send_message(f"❌ حدث خطأ: {e}")

@bot.tree.command(name="accept", description="الموافقة على طلب محادثة حساب معين فقط")
@app_commands.describe(username="اسم حساب اللاعب")
async def slash_accept(interaction: discord.Interaction, username: str):
    register_interaction(interaction)
    from update_server import GLOBAL_SUPPORT_REQUESTS
    uname = username.strip().lower()
    if uname not in GLOBAL_SUPPORT_REQUESTS:
        GLOBAL_SUPPORT_REQUESTS[uname] = {}
    GLOBAL_SUPPORT_REQUESTS[uname]["status"] = "ACCEPTED"
    GLOBAL_SUPPORT_REQUESTS[uname]["accepted_by"] = str(interaction.user)
    GLOBAL_SUPPORT_REQUESTS[uname]["accepted_time"] = time.time()
    await interaction.response.send_message(f"🎉 **تمت الموافقة على محادثة حساب `{username}` فقط!**\n🎮 ستظهر له في اللعبة فوراً: *تمام تقدر تتحدث معاه!*")

@bot.tree.command(name="reject", description="رفض طلب محادثة لاعب معين")
@app_commands.describe(username="اسم حساب اللاعب")
async def slash_reject(interaction: discord.Interaction, username: str):
    register_interaction(interaction)
    from update_server import GLOBAL_SUPPORT_REQUESTS
    uname = username.strip().lower()
    if uname not in GLOBAL_SUPPORT_REQUESTS:
        GLOBAL_SUPPORT_REQUESTS[uname] = {}
    GLOBAL_SUPPORT_REQUESTS[uname]["status"] = "REJECTED"
    GLOBAL_SUPPORT_REQUESTS[uname]["rejected_by"] = str(interaction.user)
    await interaction.response.send_message(f"🚫 **تم رفض طلب محادثة اللاعب `{username}`.**")

@bot.tree.command(name="help", description="عرض دليل أوامر بوت Titan Strike 3D")
async def slash_help(interaction: discord.Interaction):
    register_interaction(interaction)
    embed = discord.Embed(
        title="🤖 دليل أوامر بوت ديسكورد Cyberfort",
        description="مرحباً بك يا قائدنا! أنا المساعد التنفيذي لإدارة سيرفر Titan Strike 3D مباشرة من ديسكورد.",
        color=0x5865F2
    )
    embed.add_field(name="⚡ /status", value="فحص حالة السيرفر الحية، اللاعبين، واستهلاك الذاكرة والمعالج.", inline=False)
    embed.add_field(name="🎮 /rooms", value="عرض جميع الغرف المفتوحة وقائمة اللاعبين بداخلها.", inline=False)
    embed.add_field(name="⚔️ /create_room", value="تجهيز غرفة مبارزة 1v1 فوراً ضد البوت.", inline=False)
    embed.add_field(name="🚨 /alarm", value="تشغيل أو إيقاف صفارة الإنذار العامة باللعبة.", inline=False)
    embed.add_field(name="📢 /announce", value="بث رسالة نصية في منتصف شاشات جميع اللاعبين أونلاين.", inline=False)
    embed.add_field(name="✅ /accept [اسم]", value="قبول محادثة حساب معين فقط.", inline=False)
    embed.add_field(name="❌ /reject [اسم]", value="رفض طلب محادثة لاعب.", inline=False)
    embed.add_field(name="💬 المحادثة الذكية", value="يمكنك التحدث معي مباشرة بالعامية في الرسائل الخاصة (DM) أو منشنتي في أي سيرفر وسأجيبك فوراً!", inline=False)
    await interaction.response.send_message(embed=embed)

def register_interaction(interaction: discord.Interaction):
    """Registers user and channel to receive future server alerts."""
    changed = False
    if interaction.user and interaction.user.id not in _admin_user_ids:
        _admin_user_ids.add(interaction.user.id)
        changed = True
    if interaction.channel and interaction.channel.id not in _alert_channel_ids:
        _alert_channel_ids.add(interaction.channel.id)
        changed = True
    if changed:
        save_discord_data()

# --- Discord Button Interaction Listener ---

@bot.event
async def on_interaction(interaction: discord.Interaction):
    if interaction.type == discord.InteractionType.component:
        cid = interaction.data.get("custom_id", "")
        if cid.startswith("support_accept:"):
            target_user = cid.split(":", 1)[1].strip().lower()
            from update_server import GLOBAL_SUPPORT_REQUESTS
            if target_user not in GLOBAL_SUPPORT_REQUESTS:
                GLOBAL_SUPPORT_REQUESTS[target_user] = {}
            GLOBAL_SUPPORT_REQUESTS[target_user]["status"] = "ACCEPTED"
            GLOBAL_SUPPORT_REQUESTS[target_user]["accepted_by"] = str(interaction.user)
            GLOBAL_SUPPORT_REQUESTS[target_user]["accepted_time"] = time.time()

            embed = interaction.message.embeds[0] if interaction.message.embeds else None
            if embed:
                embed.color = 0x57F287
                embed.title = f"✅ تمت الموافقة على محادثة اللاعب '{target_user}'!"
                embed.set_footer(text=f"تم القبول بواسطة: {interaction.user.name} • الصلاحية لحساب '{target_user}' فقط")

            await interaction.response.edit_message(
                content=f"🎉 **تمت الموافقة على محادثة حساب `{target_user}` بنجاح بواسطة {interaction.user.mention}!**\n🎮 اللاعب يرى الآن في اللعبة: *تمام تقدر تتحدث معاه!*",
                embed=embed,
                components=[]
            )
            print(f"[DiscordBot] ✅ Admin {interaction.user} ACCEPTED player '{target_user}'")
            return

        elif cid.startswith("support_reject:"):
            target_user = cid.split(":", 1)[1].strip().lower()
            from update_server import GLOBAL_SUPPORT_REQUESTS
            if target_user not in GLOBAL_SUPPORT_REQUESTS:
                GLOBAL_SUPPORT_REQUESTS[target_user] = {}
            GLOBAL_SUPPORT_REQUESTS[target_user]["status"] = "REJECTED"
            GLOBAL_SUPPORT_REQUESTS[target_user]["rejected_by"] = str(interaction.user)

            embed = interaction.message.embeds[0] if interaction.message.embeds else None
            if embed:
                embed.color = 0xED4245
                embed.title = f"❌ تم رفض طلب اللاعب '{target_user}'"
                embed.set_footer(text=f"تم الرفض بواسطة: {interaction.user.name}")

            await interaction.response.edit_message(
                content=f"🚫 **تم رفض طلب محادثة اللاعب `{target_user}` بواسطة {interaction.user.mention}.**",
                embed=embed,
                components=[]
            )
            print(f"[DiscordBot] ❌ Admin {interaction.user} REJECTED player '{target_user}'")
            return

    # Process normal slash commands
    await bot.process_application_commands(interaction)

# --- Message Event Handler ---

@bot.event
async def on_message(message: discord.Message):
    if message.author == bot.user or message.author.bot:
        return

    is_dm = isinstance(message.channel, discord.DMChannel)
    is_mentioned = bot.user in message.mentions if message.guild else False

    changed = False
    if message.author.id not in _admin_user_ids:
        _admin_user_ids.add(message.author.id)
        changed = True
    if message.channel.id not in _alert_channel_ids:
        _alert_channel_ids.add(message.channel.id)
        changed = True
    if changed:
        save_discord_data()

    content = message.content.strip()
    if is_mentioned:
        content = message.clean_content.replace(f"@{bot.user.name}", "").strip()

    if is_dm or is_mentioned or content.startswith("!") or content.startswith("/"):
        clean_lower = content.lower().strip()

        # Text accept: !accept [user]
        if clean_lower.startswith("!accept") or clean_lower.startswith("/accept") or clean_lower.startswith("قبول"):
            parts = content.split(maxsplit=1)
            if len(parts) > 1:
                uname = parts[1].strip().lower()
                from update_server import GLOBAL_SUPPORT_REQUESTS
                if uname not in GLOBAL_SUPPORT_REQUESTS:
                    GLOBAL_SUPPORT_REQUESTS[uname] = {}
                GLOBAL_SUPPORT_REQUESTS[uname]["status"] = "ACCEPTED"
                GLOBAL_SUPPORT_REQUESTS[uname]["accepted_by"] = str(message.author)
                GLOBAL_SUPPORT_REQUESTS[uname]["accepted_time"] = time.time()
                await message.channel.send(f"🎉 **تمت الموافقة على محادثة حساب `{parts[1].strip()}` فقط!**\n🎮 اللاعب الآن يرى باللعبة: *تمام تقدر تتحدث معاه!*")
                return

        # Text reject: !reject [user]
        if clean_lower.startswith("!reject") or clean_lower.startswith("/reject") or clean_lower.startswith("رفض"):
            parts = content.split(maxsplit=1)
            if len(parts) > 1:
                uname = parts[1].strip().lower()
                from update_server import GLOBAL_SUPPORT_REQUESTS
                if uname not in GLOBAL_SUPPORT_REQUESTS:
                    GLOBAL_SUPPORT_REQUESTS[uname] = {}
                GLOBAL_SUPPORT_REQUESTS[uname]["status"] = "REJECTED"
                GLOBAL_SUPPORT_REQUESTS[uname]["rejected_by"] = str(message.author)
                await message.channel.send(f"🚫 **تم رفض طلب محادثة اللاعب `{parts[1].strip()}`.**")
                return

        # Status Command
        if clean_lower in ["!status", "/status", "status", "حالة السيرفر", "السيرفر شغال", "السيرفر شغال؟"]:
            embed = build_status_embed()
            await message.channel.send(embed=embed)
            return

        # Rooms Command
        if clean_lower in ["!rooms", "/rooms", "rooms", "الغرف", "الرومات"]:
            from update_server import ROOMS
            if not ROOMS:
                await message.channel.send("🎮 **لا توجد غرف نشطة حالياً بالسيرفر.**\nيمكنك كتابة `!1v1` لإنشاء غرفة مبارزة فوراً!")
            else:
                embed = discord.Embed(title=f"🎮 الغرف النشطة بالسيرفر ({len(ROOMS)})", color=0x5865F2)
                for code, r in list(ROOMS.items())[:10]:
                    players = ", ".join(r.get("players_list", [])) or "لا يوجد"
                    embed.add_field(
                        name=f"غرفة #{code} ({r.get('mode', 'مبارزة')})",
                        value=f"👑 **الهوست:** {r.get('host', 'لاعب')}\n👥 **اللاعبين:** {players}",
                        inline=False
                    )
                await message.channel.send(embed=embed)
            return

        # 1v1 Room
        if clean_lower in ["!1v1", "/1v1", "1v1", "مبارزة", "تحدي"] or "اعمل روم" in clean_lower or "اعمل غرفة" in clean_lower:
            try:
                from update_server import execute_server_action
                ok, msg, _ = execute_server_action("create_ai_room", {"hero": "Spider Hero"}, context_type="admin_dashboard")
                await message.channel.send("⚔️ **سمعاً وطاعة يا قائدنا! تم إنشاء وتجهيز غرفة المبارزة `#AI1V1` فوراً!**\n🎮 تم بث التنبيه لجميع اللاعبين باللعبة!")
            except Exception as e:
                await message.channel.send(f"❌ حدث خطأ: {e}")
            return

        # Alarm Command
        if clean_lower.startswith("!alarm") or clean_lower.startswith("/alarm") or "إنذار" in clean_lower:
            active = not any(k in clean_lower for k in ["off", "stop", "اطفي", "وقف", "0", "إلغاء"])
            try:
                from update_server import execute_server_action
                ok, msg, _ = execute_server_action("emergency_alarm", {"active": active}, context_type="admin_dashboard")
                txt = "🚨 تم **تشغيل** صفارات الإنذار في اللعبة بنجاح يا قائدنا!" if active else "✅ تم **إيقاف** صفارات الإنذار."
                await message.channel.send(txt)
            except Exception as e:
                await message.channel.send(f"❌ خطأ: {e}")
            return

        # Announce Command
        if clean_lower.startswith("!announce") or clean_lower.startswith("/announce"):
            parts = content.split(maxsplit=1)
            if len(parts) < 2 or not parts[1].strip():
                await message.channel.send("⚠️ يرجى كتابة نص الإعلان بعد الأمر، مثال:\n`!announce مرحباً بالجميع!`")
                return
            msg_text = parts[1].strip()
            try:
                from update_server import execute_server_action
                ok, res_msg, _ = execute_server_action("broadcast_message", {"message": msg_text}, context_type="admin_dashboard")
                await message.channel.send(f"📢 **تم إرسال إعلانك في منتصف شاشات جميع اللاعبين فوراً!**\n*{msg_text}*")
            except Exception as e:
                await message.channel.send(f"❌ خطأ: {e}")
            return

        # Greetings
        greetings = ["عامل ايه", "ازيك", "الو", "ألو", "هلا", "مرحبا", "سلام عليكم", "صباح الخير", "مساء الخير", "انت هنا", "فينك"]
        if any(clean_lower == g or clean_lower.startswith(g) for g in greetings):
            reply = (
                f"👑 **الحمد لله يا قائدنا! أنا هنا وشغال معاك ومتابع السيرفر لحظة بلحظة!** ⚡\n\n"
                f"السيرفر شغال وتمام ومستعد لأي استفسار أو أمر تطلبه!\n"
                f"*اطلب أي حاجة وسأنفذها فوراً يا زعيم!*"
            )
            await message.channel.send(reply)
            return

        # Natural Language with Gemini AI
        async with message.channel.typing():
            try:
                from update_server import call_gemini_ai
                status_code, ai_res = call_gemini_ai(content, context_type="admin_dashboard")
                if ai_res.get("success") and ai_res.get("reply"):
                    reply = ai_res["reply"]
                    act_res = ai_res.get("action_result", "")
                    if act_res:
                        reply += f"\n\n⚡ **تم تنفيذ الأمر:** `{act_res}`"
                    await message.channel.send(reply[:1950])
                else:
                    await message.channel.send("أمرك يا قائدنا! السيرفر شغال ومستقر ومستعد لأي أمر تطلبه!")
            except Exception as e:
                await message.channel.send("أمرك يا قائدنا سيف! أنا متصل بالسيرفر وجاهز لأوامرك فوراً!")

@bot.event
async def on_ready():
    global _bot_loop
    _bot_loop = asyncio.get_running_loop()
    print(f"[DiscordBot] 🚀 تم تسجيل الدخول بنجاح كـ {bot.user} (ID: {bot.user.id})")

    for g in bot.guilds:
        print(f"[DiscordBot] 🏰 متصل بسيرفر ديسكورد: {g.name} (ID: {g.id})")
        for ch in g.text_channels:
            if ch.name.lower() in ["general", "عام", "بوت", "bot", "chat", "commands"]:
                _alert_channel_ids.add(ch.id)
    save_discord_data()

    try:
        synced = await bot.tree.sync()
        print(f"[DiscordBot] ✅ تم مزامنة {len(synced)} أوامر Slash بنجاح في Discord!")
    except Exception as e:
        print(f"[DiscordBot] ⚠️ خطأ أثناء مزامنة أوامر Slash: {e}")

    activity = discord.Activity(type=discord.ActivityType.watching, name="Titan Strike 3D | /status")
    await bot.change_presence(status=discord.Status.online, activity=activity)

def broadcast_to_admins(text: str, embed: Optional[discord.Embed] = None) -> None:
    """Broadcasts a notification or alert to all registered Discord channels & admins."""
    if not _bot_loop or not bot.is_ready():
        return

    async def _send_all():
        for ch_id in get_target_channels():
            try:
                ch = bot.get_channel(ch_id)
                if ch:
                    await ch.send(content=text, embed=embed)
            except Exception as ex:
                print(f"[DiscordBot] Error sending to channel {ch_id}: {ex}")

        for u_id in list(_admin_user_ids):
            try:
                user = bot.get_user(u_id)
                if user:
                    await user.send(content=text, embed=embed)
            except Exception:
                pass

    asyncio.run_coroutine_threadsafe(_send_all(), _bot_loop)

def notify_server_error(source: str, error_msg: str) -> None:
    """Sends an instant alert embed to Discord whenever an error occurs on the server."""
    now_str = time.strftime("%H:%M:%S")
    embed = discord.Embed(
        title="🚨 [تنبيه عاجل من السيرفر - خطأ!]",
        description=f"⏰ **الوقت:** `{now_str}`\n📍 **المصدر:** `{source}`",
        color=0xff0033
    )
    embed.add_field(name="⚠️ تفاصيل الخطأ", value=f"```{error_msg[:1000]}```", inline=False)
    embed.set_footer(text="💡 اكتب /status لفحص حالة السيرفر الآن.")
    broadcast_to_admins(text="🚨 **تنبيه عاجل من سيرفر اللعبة:**", embed=embed)

def run_discord_bot():
    """Runs the discord client inside an asyncio event loop."""
    tok = get_discord_token()
    if not tok:
        print("[DiscordBot] ❌ No Discord token provided!")
        return

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    global _bot_loop
    _bot_loop = loop

    try:
        loop.run_until_complete(bot.start(tok))
    except Exception as e:
        print(f"[DiscordBot] ❌ Fatal error running Discord bot: {e}")

def start_discord_bot_thread() -> threading.Thread:
    """Starts the Discord Bot in an independent daemon thread."""
    t = threading.Thread(target=run_discord_bot, daemon=True, name="DiscordBotAgent")
    t.start()
    return t

if __name__ == "__main__":
    print(f"[*] Starting standalone Discord Bot Agent ({CLIENT_ID})...")
    run_discord_bot()
