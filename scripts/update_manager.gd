extends Node

# UpdateManager Autoload (res://scripts/update_manager.gd)
# Handles Over-The-Air (OTA) Game Updates:
# Version checking, background download with progress tracking,
# and runtime resource patching via ProjectSettings.load_resource_pack().

signal update_checked(has_update: bool, version_info: Dictionary)
signal update_available(version_info: Dictionary)
signal download_progress(downloaded_bytes: int, total_bytes: int, percent: float)
signal download_completed(file_path: String)
signal download_failed(error_message: String)
signal update_installed()

const CONFIG_PATH: String = "user://update_config.cfg"
const STATE_PATH: String = "user://version_state.json"
const UPDATE_PACKAGE_PATH: String = "user://game_update.zip"

# Default Baseline Version
var base_version: String = "1.0.0"
var base_build: int = 1

var current_version: String = "1.0.0"
var current_build: int = 1

var server_url: String = "http://127.0.0.1:8080"
var latest_server_info: Dictionary = {}

var is_checking: bool = false
var is_downloading: bool = false

var _check_http: HTTPRequest = null
var _download_http: HTTPRequest = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_load_installed_state()
	
	_check_http = HTTPRequest.new()
	_check_http.timeout = 5.0
	add_child(_check_http)
	_check_http.request_completed.connect(_on_check_request_completed)
	
	_download_http = HTTPRequest.new()
	_download_http.use_threads = true
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download_request_completed)
	
	# Automatically check for updates on startup after 1 second
	get_tree().create_timer(1.2).timeout.connect(func():
		check_for_updates()
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
		server_url = cfg.get_value("server", "url", "http://127.0.0.1:8080")
	else:
		# If on mobile/LAN, try bluetooth/hotspot host IP as fallback default
		var host_ip = NetworkManager.get_bluetooth_or_hotspot_host_ip()
		if host_ip != "127.0.0.1" and host_ip != "192.168.43.1":
			server_url = "http://%s:8080" % host_ip
		else:
			server_url = "http://127.0.0.1:8080"

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

func check_for_updates() -> void:
	if is_checking:
		return
	is_checking = true
	var endpoint = server_url.trim_suffix("/") + "/api/version"
	var err = _check_http.request(endpoint)
	if err != OK:
		is_checking = false
		update_checked.emit(false, {"error": "Failed to create HTTP request"})

func _on_check_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_checking = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		update_checked.emit(false, {"error": "Server unreachable (%d)" % response_code})
		return
	
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

func start_download_update() -> void:
	if is_downloading:
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
	
	# Delete previous update zip if exists
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
	# Load resource pack with replace_files = true
	var loaded = ProjectSettings.load_resource_pack(real_path, true)
	if loaded:
		_save_installed_state(latest_server_info)
		update_installed.emit()
		return true
	else:
		# Fallback attempt with user:// protocol URI
		var loaded_alt = ProjectSettings.load_resource_pack(UPDATE_PACKAGE_PATH, true)
		if loaded_alt:
			_save_installed_state(latest_server_info)
			update_installed.emit()
			return true
		download_failed.emit("تعذر تطبيق وتثبيت حزمة التحديث في محرك اللعبة.")
		return false

