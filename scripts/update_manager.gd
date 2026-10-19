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

const CONFIG_PATH: String = "user://update_config.cfg"
const STATE_PATH: String = "user://version_state.json"
const UPDATE_PACKAGE_PATH: String = "user://game_update.zip"

# Fallback server candidate endpoints across Internet (WAN) and Wi-Fi (LAN)
const DEFAULT_FALLBACK_ENDPOINTS: Array[String] = [
	"http://192.168.1.17:8080",      # Home Wi-Fi LAN
	"http://105.197.151.212:8080",   # Public Internet WAN (4G/5G mobile data)
	"http://127.0.0.1:8080",          # Localhost (PC testing)
	"http://192.168.43.1:8080"        # Mobile Hotspot Gateway
]

# Default Baseline Version
var base_version: String = "1.0.0"
var base_build: int = 1

var current_version: String = "1.0.0"
var current_build: int = 1

var server_url: String = "http://192.168.1.17:8080"
var latest_server_info: Dictionary = {}

var is_checking: bool = false
var is_downloading: bool = false
var is_server_open: bool = true
var _shutdown_in_progress: bool = false
var _heartbeat_ticks: int = 0

var _candidate_index: int = 0
var _candidates_to_try: Array[String] = []

var _check_http: HTTPRequest = null
var _config_http: HTTPRequest = null
var _download_http: HTTPRequest = null
var _status_http: HTTPRequest = null
var _heartbeat_timer: Timer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_load_installed_state()
	
	_check_http = HTTPRequest.new()
	_check_http.timeout = 4.0
	add_child(_check_http)
	_check_http.request_completed.connect(_on_check_request_completed)
	
	_config_http = HTTPRequest.new()
	_config_http.timeout = 4.0
	add_child(_config_http)
	_config_http.request_completed.connect(_on_config_request_completed)
	
	_download_http = HTTPRequest.new()
	_download_http.use_threads = true
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download_request_completed)
	
	_status_http = HTTPRequest.new()
	_status_http.timeout = 2.5
	add_child(_status_http)
	_status_http.request_completed.connect(_on_status_request_completed)
	
	# Setup periodic quiet background heartbeat refresh timer (every 3 seconds)
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = 3.0
	_heartbeat_timer.autostart = true
	_heartbeat_timer.one_shot = false
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(check_server_heartbeat)
	
	# Automatically check for updates, sync game config, and check heartbeat on startup
	get_tree().create_timer(1.0).timeout.connect(func():
		check_server_heartbeat()
		check_for_updates()
		sync_game_config()
	)

func _process(_delta: float) -> void:
	if is_downloading and _download_http:
		var downloaded = _download_http.get_downloaded_bytes()
		var total = _download_http.get_body_size()
		if total > 0:
			var pct = clampf(float(downloaded) / float(total), 0.0, 1.0)
			download_progress.emit(downloaded, total, pct)

func _load_config() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		server_url = cfg.get_value("server", "url", "http://192.168.1.17:8080")
	else:
		server_url = "http://192.168.1.17:8080"

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
# HEARTBEAT & SERVER STATUS MONITORING (Periodic Refresh)
# ==============================================================================
func check_server_heartbeat() -> void:
	if _shutdown_in_progress or is_downloading:
		return
	
	_heartbeat_ticks += 1
	var endpoint = server_url.trim_suffix("/") + "/api/server_status"
	_status_http.request(endpoint)
	
	# Quietly refresh game configuration every 9 seconds without disrupting user
	if _heartbeat_ticks % 3 == 0:
		sync_game_config()

func _on_status_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _shutdown_in_progress:
		return
		
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		is_server_open = false
		server_status_updated.emit(false, "close")
		return
	
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		var st = str(json.data.get("status", "OPEN")).to_upper()
		if st == "CLOSED" or st == "CLOSE":
			is_server_open = false
			server_status_updated.emit(false, "close")
			_trigger_server_closed_shutdown()
		else:
			is_server_open = true
			server_status_updated.emit(true, "Open")
	else:
		is_server_open = false
		server_status_updated.emit(false, "close")

func _trigger_server_closed_shutdown() -> void:
	if _shutdown_in_progress:
		return
	_shutdown_in_progress = true
	
	# Stop heartbeat
	if _heartbeat_timer:
		_heartbeat_timer.stop()
		
	# Create high-priority fullscreen shutdown notice overlay
	var canvas = CanvasLayer.new()
	canvas.layer = 128
	
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.1, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	
	var alert_box = VBoxContainer.new()
	alert_box.set_anchors_preset(Control.PRESET_CENTER)
	alert_box.alignment = BoxContainer.ALIGNMENT_CENTER
	alert_box.custom_minimum_size = Vector2(700, 300)
	alert_box.position = Vector2(-350, -150)
	
	var icon = Label.new()
	icon.text = "🚨"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 44)
	alert_box.add_child(icon)
	
	var title = Label.new()
	title.text = "تم إيقاف وإغلاق السيرفر من قِبل المدير!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	alert_box.add_child(title)
	
	var sub = Label.new()
	sub.text = "\nServer has been CLOSED by admin.\nClosing game for all players..."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	alert_box.add_child(sub)
	
	canvas.add_child(alert_box)
	get_tree().root.add_child(canvas)
	
	# Wait 1.4s so players see the alert, then quit cleanly
	get_tree().create_timer(1.4).timeout.connect(func():
		get_tree().quit()
	)

# ==============================================================================
# VERSION & CONFIG SYNC
# ==============================================================================
func check_for_updates() -> void:
	if is_checking or _shutdown_in_progress:
		return
	is_checking = true
	
	# Prepare candidate list starting with the currently configured server_url
	_candidates_to_try.clear()
	_candidates_to_try.append(server_url)
	for ep in DEFAULT_FALLBACK_ENDPOINTS:
		if ep != server_url and not _candidates_to_try.has(ep):
			_candidates_to_try.append(ep)
	
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
	var has_new = server_build > current_build
	
	update_checked.emit(has_new, info)
	if has_new:
		update_available.emit(info)
	
	sync_game_config()

func sync_game_config() -> void:
	if _shutdown_in_progress:
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
	
	if FileAccess.file_exists(UPDATE_PACKAGE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UPDATE_PACKAGE_PATH))
	
	_download_http.download_file = UPDATE_PACKAGE_PATH
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
	if not FileAccess.file_exists(UPDATE_PACKAGE_PATH):
		download_failed.emit("ملف التحديث غير موجود في مسار اللعبة.")
		return false
	
	var real_path = ProjectSettings.globalize_path(UPDATE_PACKAGE_PATH)
	var loaded = ProjectSettings.load_resource_pack(real_path, true)
	if loaded:
		_save_installed_state(latest_server_info)
		update_installed.emit()
		return true
	else:
		var loaded_alt = ProjectSettings.load_resource_pack(UPDATE_PACKAGE_PATH, true)
		if loaded_alt:
			_save_installed_state(latest_server_info)
			update_installed.emit()
			return true
		download_failed.emit("تعذر تطبيق وتثبيت حزمة التحديث في محرك اللعبة.")
		return false
