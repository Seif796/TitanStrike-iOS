extends Node

# UpdateManager Autoload (res://scripts/update_manager.gd)
# Handles Over-The-Air (OTA) Game Updates, Live Game Configuration Sync,
# and Real-Time Server Heartbeat Monitoring (with Automatic Force-Quit on Server Shutdown):
# Version checking, multi-network auto fallback (WAN / LAN / Localhost),
# background download with progress tracking, live hero configuration syncing,
# periodic quiet refresh, and runtime resource patching via ProjectSettings.load_resource_pack().

signal update_checked(has_update: bool, version_info: Dictionary)
signal update_available(version_info: Dictionary)
signal download_progress(downloaded_bytes: int, total_bytes: int, percent: float)
signal download_completed(file_path: String)
signal download_failed(error_message: String)
signal update_installed()
signal game_config_synced(config: Dictionary)
signal server_status_updated(is_open: bool, status_str: String)
signal device_access_checked(is_allowed: bool, message: String)
signal server_opened_notification()
signal server_closed_notification()
signal ai_duel_invited(message: String, room_code: String)

const CONFIG_PATH: String = "user://update_config.cfg"
const STATE_PATH: String = "user://version_state.json"
const UPDATE_PACKAGE_PATH: String = "user://game_update.zip"

# Fallback server candidate endpoints across Internet (WAN) and Wi-Fi (LAN)
const DEFAULT_FALLBACK_ENDPOINTS: Array[String] = [
	"http://127.0.0.1:8080",
	"http://127.0.0.1:8081",
	"http://192.168.1.17:8080",
	"http://192.168.1.17:8081",
	"http://196.131.243.244:8080",
	"http://196.131.243.244:8081",
	"http://192.168.43.1:8080",
	"http://192.168.43.1:8081"
]

func get_fallback_candidates() -> Array[String]:
	var list: Array[String] = []
	var is_pc = OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"]
	
	if is_pc:
		list.append("http://127.0.0.1:8080")
		list.append("http://127.0.0.1:8081")
		list.append("http://localhost:8080")
		list.append("http://localhost:8081")
	
	list.append("http://192.168.1.17:8080")
	list.append("http://192.168.1.17:8081")
	list.append("http://196.131.243.244:8080")
	list.append("http://196.131.243.244:8081")
	list.append("https://titanstrike-server.onrender.com")
	
	if not is_pc:
		list.append("http://127.0.0.1:8080")
		list.append("http://127.0.0.1:8081")
		
	list.append("http://192.168.43.1:8080")
	list.append("http://192.168.43.1:8081")
	
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_method("get_all_local_ips"):
		for lip in nm.get_all_local_ips():
			if lip != "127.0.0.1":
				var u1 = "http://%s:8080" % lip
				var u2 = "http://%s:8081" % lip
				if not list.has(u1): list.append(u1)
				if not list.has(u2): list.append(u2)
	
	if not server_url.is_empty():
		list.erase(server_url)
		if is_pc:
			if server_url.contains("127.0.0.1") or server_url.contains("localhost"):
				list.insert(0, server_url)
			else:
				list.insert(2, server_url)
		else:
			list.insert(0, server_url)
		
	return list

func get_guest_portal_url() -> String:
	if server_url.contains("127.0.0.1") or server_url.contains("localhost"):
		return "http://localhost:8081"
	elif server_url.contains("192.168.1.17"):
		return "http://192.168.1.17:8081"
	return "http://192.168.1.17:8081"

# Default Baseline Version
var base_version: String = "1.0.0"
var base_build: int = 1

var current_version: String = "1.0.0"
var current_build: int = 1

var server_url: String = "http://127.0.0.1:8080" if OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"] else "http://192.168.1.17:8080"
var latest_server_info: Dictionary = {}

var is_checking: bool = false
var is_downloading: bool = false
var is_server_open: bool = true
var is_device_allowed: bool = true
var _shutdown_in_progress: bool = false
var _heartbeat_ticks: int = 0

var _candidate_index: int = 0
var _candidates_to_try: Array[String] = []

var _check_http: HTTPRequest = null
var _config_http: HTTPRequest = null
var _download_http: HTTPRequest = null
var _status_http: HTTPRequest = null
var _device_verify_http: HTTPRequest = null
var _heartbeat_timer: Timer = null
var _unauthorized_overlay: CanvasLayer = null
var _server_closed_overlay: CanvasLayer = null
var _alarm_overlay: CanvasLayer = null
var _broadcast_overlay: CanvasLayer = null
var current_session_data: Dictionary = {}
var last_seen_alarm_id: int = 0
var last_seen_broadcast_id: int = 0
var last_seen_ai_duel_id: int = 0
var _is_checking_heartbeat: bool = false
var _heartbeat_candidate_idx: int = 0
var _heartbeat_candidates: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_load_installed_state()
	
	# Load persistent runtime patch pack if available
	if FileAccess.file_exists("user://patch.pck"):
		var pck_real = ProjectSettings.globalize_path("user://patch.pck")
		var pck_ok = ProjectSettings.load_resource_pack(pck_real, true)
		if not pck_ok:
			pck_ok = ProjectSettings.load_resource_pack("user://patch.pck", true)
		if pck_ok:
			print("[UpdateManager] Loaded persistent patch.pck on startup!")
	elif FileAccess.file_exists(UPDATE_PACKAGE_PATH):
		var real_pkg = ProjectSettings.globalize_path(UPDATE_PACKAGE_PATH)
		var pkg_ok = ProjectSettings.load_resource_pack(real_pkg, true)
		if not pkg_ok:
			pkg_ok = ProjectSettings.load_resource_pack(UPDATE_PACKAGE_PATH, true)
		if pkg_ok:
			print("[UpdateManager] Loaded persistent UPDATE_PACKAGE_PATH on startup!")
	
	_check_http = HTTPRequest.new()
	_check_http.timeout = 2.5
	add_child(_check_http)
	_check_http.request_completed.connect(_on_check_request_completed)
	
	_config_http = HTTPRequest.new()
	_config_http.timeout = 2.5
	add_child(_config_http)
	_config_http.request_completed.connect(_on_config_request_completed)
	
	_download_http = HTTPRequest.new()
	_download_http.use_threads = true
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download_request_completed)
	
	_status_http = HTTPRequest.new()
	_status_http.timeout = 1.5
	add_child(_status_http)
	_status_http.request_completed.connect(_on_status_request_completed)
	
	_device_verify_http = HTTPRequest.new()
	_device_verify_http.timeout = 3.0
	add_child(_device_verify_http)
	_device_verify_http.request_completed.connect(_on_device_verify_completed)
	
	# Setup periodic quiet background heartbeat refresh timer (every 1.5 seconds for instant real-time sync)
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = 1.5
	_heartbeat_timer.autostart = true
	_heartbeat_timer.one_shot = false
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(func():
		check_server_heartbeat()
		if not current_session_data.is_empty():
			_send_session_heartbeat()
	)
	
	# Automatically check for updates, sync game config, and check heartbeat on startup
	get_tree().create_timer(1.0).timeout.connect(func():
		check_server_heartbeat()
		check_for_updates()
		sync_game_config()
		verify_device_access()
		var p_name = get_active_player_name()
		report_active_player_session(p_name, "🎮 متصل باللعبة (Online)", "Melon Boy", "ACTIVE")
	)

func _process(_delta: float) -> void:
	if is_downloading and _download_http:
		var downloaded = _download_http.get_downloaded_bytes()
		var total = _download_http.get_body_size()
		if total > 0:
			var pct = clampf(float(downloaded) / float(total), 0.0, 1.0)
			download_progress.emit(downloaded, total, pct)

func _load_config() -> void:
	var is_pc = OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"]
	var default_url = "http://127.0.0.1:8080" if is_pc else "http://192.168.1.17:8080"
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		server_url = cfg.get_value("server", "url", default_url)
	else:
		server_url = default_url

func save_server_url(new_url: String) -> void:
	server_url = new_url.strip_edges()
	if not server_url.begins_with("http://") and not server_url.begins_with("https://"):
		server_url = "http://" + server_url
	var cfg = ConfigFile.new()
	cfg.set_value("server", "url", server_url)
	cfg.save(CONFIG_PATH)

func _load_installed_state() -> void:
	current_version = base_version
	current_build = base_build
	
	if FileAccess.file_exists(STATE_PATH):
		var file = FileAccess.open(STATE_PATH, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			var json = JSON.new()
			if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
				current_version = json.data.get("version", base_version)
				current_build = int(json.data.get("version_code", base_build))
			file.close()

func _save_installed_state(v_info: Dictionary) -> void:
	current_version = v_info.get("version", current_version)
	current_build = int(v_info.get("version_code", current_build))
	
	var file = FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"version": current_version,
			"version_code": current_build,
			"installed_at": Time.get_datetime_string_from_system()
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

# ==============================================================================
# HEARTBEAT & SERVER STATUS MONITORING (Continuous 24/7 Live Monitoring)
# ==============================================================================
func check_server_heartbeat(force: bool = false) -> void:
	if is_downloading:
		return
	
	if force and _status_http != null:
		_status_http.cancel_request()
		_is_checking_heartbeat = false
		
	if _is_checking_heartbeat:
		return
	
	_is_checking_heartbeat = true
	_heartbeat_ticks += 1
	
	_heartbeat_candidates = get_fallback_candidates()
	_heartbeat_candidate_idx = 0
	_try_heartbeat_candidate()

func _try_heartbeat_candidate() -> void:
	if _heartbeat_candidate_idx >= _heartbeat_candidates.size():
		_is_checking_heartbeat = false
		return
	
	if _status_http == null:
		_is_checking_heartbeat = false
		return
		
	if _status_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_status_http.cancel_request()
	
	var candidate_url = _heartbeat_candidates[_heartbeat_candidate_idx]
	var endpoint = candidate_url.trim_suffix("/") + "/api/server_status"
	var err = _status_http.request(endpoint)
	if err != OK:
		_heartbeat_candidate_idx += 1
		_try_heartbeat_candidate()

func _on_status_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_heartbeat_candidate_idx += 1
		if _heartbeat_candidate_idx < _heartbeat_candidates.size():
			_try_heartbeat_candidate()
			return
		
		_is_checking_heartbeat = false
		# Candidates could not connect momentarily; keep last state and retry quietly on next tick
		return
	
	_is_checking_heartbeat = false
	
	# Save working candidate URL if it changed
	if _heartbeat_candidate_idx < _heartbeat_candidates.size():
		var working_url = _heartbeat_candidates[_heartbeat_candidate_idx]
		if working_url != server_url:
			save_server_url(working_url)
	
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		var st = str(json.data.get("status", "OPEN")).to_upper()
		var is_open_flag = (st == "OPEN" or st == "ONLINE" or json.data.get("is_open") == true)
		
		var was_closed = not is_server_open
		var was_open = is_server_open
		
		is_server_open = is_open_flag
		
		if is_open_flag:
			server_status_updated.emit(true, "Open")
			if was_closed:
				server_opened_notification.emit()
		else:
			server_status_updated.emit(false, "close")
			if was_open:
				server_closed_notification.emit()
		
		# Check for emergency alarm from leader
		var alarm = json.data.get("emergency_alarm", {})
		if typeof(alarm) == TYPE_DICTIONARY and alarm.get("active", false) == true:
			var a_id = int(alarm.get("id", 0))
			if a_id > last_seen_alarm_id:
				last_seen_alarm_id = a_id
				trigger_emergency_alarm_ui(str(alarm.get("message", "🚨 إنذار طارئ من قائد السيرفر!")))
		
		# Check for leader broadcast message in the center-top of the screen
		var b_msg = str(json.data.get("broadcast_message", "")).strip_edges()
		var b_id = int(json.data.get("broadcast_id", 0))
		if not b_msg.is_empty() and b_id > last_seen_broadcast_id:
			last_seen_broadcast_id = b_id
			show_leader_broadcast_banner(b_msg)
		
		# Check for live 1v1 duel invite from CyberAI (triggered from Web Control Center)
		var duel = json.data.get("ai_duel_trigger", {})
		if typeof(duel) == TYPE_DICTIONARY and duel.get("active", false) == true:
			var d_id = int(duel.get("id", 0))
			if d_id > last_seen_ai_duel_id:
				last_seen_ai_duel_id = d_id
				var d_msg = str(duel.get("message", "⚔️ دعاك CyberAI لمبارزة 1v1!"))
				var d_code = str(duel.get("room_code", "AI1V1"))
				ai_duel_invited.emit(d_msg, d_code)
	
	# Verify device access authorization
	verify_device_access()
	
	# Instant real-time game configuration refresh (every 1.5 seconds)
	sync_game_config()
	if not current_session_data.is_empty():
		_send_session_heartbeat()

func log_game_event(event_message: String, level: String = "INFO", source: String = "GAME") -> void:
	if server_url.is_empty():
		return
	var endpoint = server_url.trim_suffix("/") + "/api/console_log"
	var payload = {
		"message": event_message,
		"level": level,
		"source": source
	}
	var http = HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b):
		http.queue_free()
	)
	var headers = PackedStringArray(["Content-Type: application/json"])
	http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

var current_session_id: String = ""

func get_active_player_name() -> String:
	var am = get_node_or_null("/root/AccountManager")
	if am and am.has_method("get_current_user"):
		var u = am.get_current_user()
		if not u.is_empty():
			return u
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and not nm.local_player_name.is_empty():
		return nm.local_player_name
	return "القائد"

func report_active_player_session(p_name: String, mode_name: String, hero_name: String, status_str: String = "PLAYING") -> void:
	if current_session_id.is_empty():
		current_session_id = "sess_" + str(randi())
	var clean_name = p_name.strip_edges()
	if clean_name.is_empty():
		clean_name = get_active_player_name()
	current_session_data = {
		"session_id": current_session_id,
		"player_name": clean_name,
		"mode": mode_name,
		"hero": hero_name,
		"status": status_str,
		"action": "start"
	}
	_send_session_payload(current_session_data)

func _send_session_heartbeat() -> void:
	if server_url.is_empty():
		return
	if current_session_data.is_empty():
		var default_name = get_active_player_name()
		report_active_player_session(default_name, "🎮 متصل باللعبة (Online)", "Melon Boy", "ACTIVE")
		return
	var payload = current_session_data.duplicate()
	payload["action"] = "heartbeat"
	_send_session_payload(payload)

func clear_active_player_session() -> void:
	var default_name = get_active_player_name()
	report_active_player_session(default_name, "القائمة الرئيسية (Main Menu)", "Melon Boy", "IN_MENU")

func _send_session_payload(payload: Dictionary) -> void:
	if server_url.is_empty():
		return
	var endpoint = server_url.trim_suffix("/") + "/api/sessions/update"
	var http = HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	var headers = PackedStringArray(["Content-Type: application/json"])
	http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func trigger_emergency_alarm_ui(msg: String) -> void:
	if _alarm_overlay != null:
		_alarm_overlay.queue_free()
		_alarm_overlay = null
	
	AudioManager.play_sfx("error")
	_alarm_overlay = CanvasLayer.new()
	_alarm_overlay.layer = 140
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 20)
	_alarm_overlay.add_child(margin)
	
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.02, 0.04, 0.98)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(1.0, 0.1, 0.1, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	card.add_theme_stylebox_override("panel", style)
	margin.add_child(card)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	card.add_child(hbox)
	
	var icon = Label.new()
	icon.text = "🚨"
	icon.add_theme_font_size_override("font_size", 34)
	hbox.add_child(icon)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	var title = Label.new()
	title.text = "🚨 إنذار طارئ من قائد السيرفر! (EMERGENCY ALARM)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = msg
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9))
	vbox.add_child(desc)
	
	var close_btn = Button.new()
	close_btn.text = " ✕ إغلاق "
	close_btn.pressed.connect(func():
		if _alarm_overlay:
			_alarm_overlay.queue_free()
			_alarm_overlay = null
	)
	hbox.add_child(close_btn)
	
	get_tree().root.add_child(_alarm_overlay)
	get_tree().create_timer(10.0).timeout.connect(func():
		if _alarm_overlay:
			_alarm_overlay.queue_free()
			_alarm_overlay = null
	)

func show_leader_broadcast_banner(msg: String) -> void:
	if _broadcast_overlay != null:
		_broadcast_overlay.queue_free()
		_broadcast_overlay = null
	
	AudioManager.play_sfx("redeem")
	_broadcast_overlay = CanvasLayer.new()
	_broadcast_overlay.layer = 138
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_broadcast_overlay.add_child(center)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 20)
	center.add_child(margin)
	
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.18, 0.96)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.0, 0.95, 1.0, 1.0) # Cyber neon cyan
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_color = Color(0.0, 0.9, 1.0, 0.45)
	style.shadow_size = 18
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(480, 0)
	margin.add_child(card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)
	
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)
	
	var icon = Label.new()
	icon.text = "📢"
	icon.add_theme_font_size_override("font_size", 22)
	header.add_child(icon)
	
	var title = Label.new()
	title.text = "كلمة ورسالة عاجلة من القائد (Leader Broadcast)"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var close_btn = Button.new()
	close_btn.text = " ✕ "
	close_btn.pressed.connect(func():
		if _broadcast_overlay:
			_broadcast_overlay.queue_free()
			_broadcast_overlay = null
	)
	header.add_child(close_btn)
	
	# The floating message in the center of the screen
	var content = Label.new()
	content.text = msg
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_theme_font_size_override("font_size", 22)
	content.add_theme_color_override("font_color", Color(1.0, 0.92, 0.25))
	vbox.add_child(content)
	
	get_tree().root.add_child(_broadcast_overlay)
	
	get_tree().create_timer(8.5).timeout.connect(func():
		if _broadcast_overlay:
			_broadcast_overlay.queue_free()
			_broadcast_overlay = null
	)



func _show_server_closed_overlay() -> void:
	if _server_closed_overlay != null:
		return
	
	_server_closed_overlay = CanvasLayer.new()
	_server_closed_overlay.layer = 125
	
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.12, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_server_closed_overlay.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_server_closed_overlay.add_child(center)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(650, 320)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.18, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.25, 0.25, 0.8)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	card.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)
	
	var icon = Label.new()
	icon.text = "🚨"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 42)
	vbox.add_child(icon)
	
	var title = Label.new()
	title.text = "معلش اللعبة دلوقتي مش متاحة"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = "يقوم القائد بصيانة وتجهيز السيرفر حالياً...\n📡 السيرفر واللعبة شغالين في الخلفية وستفتح اللعبة تلقائياً فور إعادة فتح السيرفر!"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98))
	vbox.add_child(desc)
	
	var pulse_lbl = Label.new()
	pulse_lbl.text = "🟢 مراقبة حية نشطة 24/7 (Live Monitoring Active)..."
	pulse_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pulse_lbl.add_theme_font_size_override("font_size", 13)
	pulse_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	vbox.add_child(pulse_lbl)
	
	center.add_child(card)
	get_tree().root.add_child(_server_closed_overlay)

func _hide_server_closed_overlay() -> void:
	if _server_closed_overlay != null:
		_server_closed_overlay.queue_free()
		_server_closed_overlay = null

# ==============================================================================
# DEVICE ACCESS VERIFICATION & WHITELIST ENFORCEMENT
# ==============================================================================
func verify_device_access() -> void:
	if _shutdown_in_progress or is_downloading or _device_verify_http == null:
		return
	if _device_verify_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	
	var endpoint = server_url.trim_suffix("/") + "/api/verify_device"
	var current_user = ""
	var am = get_node_or_null("/root/AccountManager")
	if am != null and am.is_logged_in():
		current_user = am.get_current_user()
	
	var payload = {
		"device_id": OS.get_unique_id(),
		"device_name": OS.get_model_name(),
		"os": OS.get_name(),
		"username": current_user
	}
	var headers = PackedStringArray(["Content-Type: application/json"])
	_device_verify_http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _on_device_verify_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		var allowed = bool(json.data.get("allowed", true))
		is_device_allowed = allowed
		var msg = str(json.data.get("message", ""))
		device_access_checked.emit(allowed, msg)
		
		if not allowed:
			_show_unauthorized_device_screen(json.data)
		else:
			_hide_unauthorized_device_screen()

func _show_unauthorized_device_screen(data: Dictionary) -> void:
	if _unauthorized_overlay != null:
		return
	
	_unauthorized_overlay = CanvasLayer.new()
	_unauthorized_overlay.layer = 120
	
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.12, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_unauthorized_overlay.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_unauthorized_overlay.add_child(center)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(620, 380)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.18, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.25, 0.3, 0.9)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_right = 16
	style.corner_radius_bottom_left = 16
	style.shadow_color = Color(1.0, 0.2, 0.25, 0.3)
	style.shadow_size = 14
	card.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	
	var pad = MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_bottom", 24)
	pad.add_child(vbox)
	card.add_child(pad)
	
	var title = Label.new()
	title.text = "⛔ هذا الجهاز غير مصرح له بالدخول إلى السيرفر!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.35))
	vbox.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Unauthorized Device Access (Protected Private Server)"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	vbox.add_child(subtitle)
	
	var dev_box = VBoxContainer.new()
	dev_box.add_theme_constant_override("separation", 6)
	
	var id_lbl = Label.new()
	id_lbl.text = "كود تعريف هذا الجهاز (Device ID):"
	id_lbl.add_theme_font_size_override("font_size", 13)
	id_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	dev_box.add_child(id_lbl)
	
	var dev_id_str = OS.get_unique_id()
	var code_edit = LineEdit.new()
	code_edit.text = dev_id_str
	code_edit.editable = false
	code_edit.custom_minimum_size = Vector2(0, 40)
	dev_box.add_child(code_edit)
	
	var copy_btn = Button.new()
	copy_btn.text = "📋 نسخ كود هذا الجهاز (Copy Device ID)"
	copy_btn.custom_minimum_size = Vector2(0, 38)
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(dev_id_str)
		copy_btn.text = "✅ تم نسخ الكود بنجاح!"
	)
	dev_box.add_child(copy_btn)
	vbox.add_child(dev_box)
	
	var tip = Label.new()
	tip.text = "💡 إذا كان هذا موبايلك: افتح لوحة التحكم من اللاب توب واضغط \"✅ تصريح وموافقة\" على هذا الجهاز، وسيتم فتح اللعبة لك فوراً!"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.2, 0.95, 0.6))
	vbox.add_child(tip)
	
	var status_lbl = Label.new()
	status_lbl.text = "⏳ جاري فحص التصريح تلقائياً في الخلفية كل بضع ثوانٍ..."
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	vbox.add_child(status_lbl)
	
	center.add_child(card)
	get_tree().root.add_child(_unauthorized_overlay)

func _hide_unauthorized_device_screen() -> void:
	if _unauthorized_overlay != null:
		_unauthorized_overlay.queue_free()
		_unauthorized_overlay = null

# ==============================================================================
# VERSION & CONFIG SYNC
# ==============================================================================
func check_for_updates() -> void:
	if is_checking or _shutdown_in_progress:
		return
	is_checking = true
	
	_candidates_to_try = get_fallback_candidates()
	_candidate_index = 0
	_try_check_candidate()

func _try_check_candidate() -> void:
	if _candidate_index >= _candidates_to_try.size():
		is_checking = false
		update_checked.emit(false, {"error": "All server candidates unreachable"})
		return
	
	var candidate_url = _candidates_to_try[_candidate_index]
	var endpoint = candidate_url.trim_suffix("/") + "/api/version"
	var err = _check_http.request(endpoint)
	if err != OK:
		_candidate_index += 1
		_try_check_candidate()

func _on_check_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_candidate_index += 1
		if _candidate_index < _candidates_to_try.size():
			_try_check_candidate()
			return
		
		is_checking = false
		update_checked.emit(false, {"error": "Server unreachable (%d)" % response_code})
		return
	
	is_checking = false
	
	if _candidate_index < _candidates_to_try.size():
		var working_url = _candidates_to_try[_candidate_index]
		if working_url != server_url:
			save_server_url(working_url)
	
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK or typeof(json.data) != TYPE_DICTIONARY:
		update_checked.emit(false, {"error": "Invalid server JSON response"})
		return
	
	var info: Dictionary = json.data
	latest_server_info = info
	var server_build = int(info.get("version_code", 0))
	var has_new = (server_build > current_build) or (info.get("has_new_ipa", false) == true) or (info.get("requires_ipa", false) == true)
	
	update_checked.emit(has_new, info)
	if has_new:
		update_available.emit(info)
	
	sync_game_config()

func sync_game_config() -> void:
	if _shutdown_in_progress or _config_http == null:
		return
	if _config_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var endpoint = server_url.trim_suffix("/") + "/api/game_config"
	_config_http.request(endpoint)

func _on_config_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		# Quietly apply server configuration without changing user interface selections
		GameManager.apply_server_config(json.data)
		game_config_synced.emit(json.data)

func start_download_update() -> void:
	if is_downloading or _shutdown_in_progress:
		return
	if latest_server_info.is_empty():
		download_failed.emit("لا توجد معلومات تحديث متوفرة حالياً.")
		return
	
	var dl_path = latest_server_info.get("download_url", "/downloads/update.zip")
	var full_url = ""
	if dl_path.begins_with("http://") or dl_path.begins_with("https://"):
		full_url = dl_path
	else:
		full_url = server_url.trim_suffix("/") + "/" + dl_path.trim_prefix("/")
	
	var target_path = "user://patch.pck" if dl_path.ends_with(".pck") else UPDATE_PACKAGE_PATH
	if FileAccess.file_exists(target_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target_path))
	
	_download_http.download_file = target_path
	is_downloading = true
	var err = _download_http.request(full_url)
	if err != OK:
		is_downloading = false
		download_failed.emit("فشل بدء تحميل التحديث: %d" % err)

func _on_download_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	is_downloading = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		download_failed.emit("فشل التحميل من السيرفر (كود الخطأ: %d)" % response_code)
		return
	
	download_completed.emit(UPDATE_PACKAGE_PATH)
	apply_update()

func apply_update() -> bool:
	var dl_path = latest_server_info.get("download_url", "")
	if dl_path.ends_with(".pck") or FileAccess.file_exists("user://patch.pck"):
		var pck_real = ProjectSettings.globalize_path("user://patch.pck")
		var pck_loaded = ProjectSettings.load_resource_pack(pck_real, true)
		if not pck_loaded:
			pck_loaded = ProjectSettings.load_resource_pack("user://patch.pck", true)
		if pck_loaded:
			print("[UpdateManager] Successfully applied PCK update directly!")
			_save_installed_state(latest_server_info)
			update_installed.emit()
			return true

	if not FileAccess.file_exists(UPDATE_PACKAGE_PATH):
		download_failed.emit("ملف التحديث غير موجود في مسار اللعبة.")
		return false
	
	var real_path = ProjectSettings.globalize_path(UPDATE_PACKAGE_PATH)
	
	# 1. Physical extraction using ZIPReader: extracts and writes new files into res:// and user://
	var reader = ZIPReader.new()
	var err = reader.open(real_path)
	if err != OK:
		err = reader.open(UPDATE_PACKAGE_PATH)
	
	var extracted_count = 0
	if err == OK:
		var files = reader.get_files()
		for f_path in files:
			if f_path.ends_with("/"):
				DirAccess.make_dir_recursive_absolute("res://" + f_path)
				DirAccess.make_dir_recursive_absolute("user://patch/" + f_path)
				continue
			var data = reader.read_file(f_path)
			
			if f_path.ends_with(".pck"):
				var f_patch = FileAccess.open("user://patch.pck", FileAccess.WRITE)
				if f_patch:
					f_patch.store_buffer(data)
					f_patch.close()
					extracted_count += 1
			
			# Overwrite in res:// (direct file update)
			var res_target = "res://" + f_path
			DirAccess.make_dir_recursive_absolute(res_target.get_base_dir())
			var f_res = FileAccess.open(res_target, FileAccess.WRITE)
			if f_res:
				f_res.store_buffer(data)
				f_res.close()
				extracted_count += 1
			
			# Also write to user://patch/
			var user_target = "user://patch/" + f_path
			DirAccess.make_dir_recursive_absolute(user_target.get_base_dir())
			var f_u = FileAccess.open(user_target, FileAccess.WRITE)
			if f_u:
				f_u.store_buffer(data)
				f_u.close()
		reader.close()
		print("[UpdateManager] Successfully extracted and updated %d files!" % extracted_count)
	
	# 2. Virtual resource pack mounting (for exported builds / APK)
	var loaded = false
	if FileAccess.file_exists("user://patch.pck"):
		loaded = ProjectSettings.load_resource_pack(ProjectSettings.globalize_path("user://patch.pck"), true)
		if not loaded:
			loaded = ProjectSettings.load_resource_pack("user://patch.pck", true)
	if not loaded:
		loaded = ProjectSettings.load_resource_pack(real_path, true)
	if not loaded:
		loaded = ProjectSettings.load_resource_pack(UPDATE_PACKAGE_PATH, true)
	
	if loaded or extracted_count > 0:
		_save_installed_state(latest_server_info)
		update_installed.emit()
		return true
	
	download_failed.emit("تعذر تطبيق وتثبيت حزمة التحديث في محرك اللعبة.")
	return false
