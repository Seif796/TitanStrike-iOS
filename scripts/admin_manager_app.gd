extends Control

# Titan Strike 3D - Admin Manager Mobile Native Controller
# Connects to update_server.py (port 8080) for instant real-time control

var server_url: String = "http://192.168.1.17:8080"
var http_request: HTTPRequest
var is_server_open: bool = true
var is_alarm_active: bool = false

@onready var status_label: Label = $VBox/StatusCard/StatusLabel
@onready var info_label: Label = $VBox/StatusCard/InfoLabel
@onready var url_input: LineEdit = $VBox/ServerCard/HBox/UrlInput
@onready var server_btn: Button = $VBox/Actions/ServerToggleBtn
@onready var alarm_btn: Button = $VBox/Actions/AlarmToggleBtn
@onready var broadcast_input: LineEdit = $VBox/BroadcastCard/HBox/BroadcastInput
@onready var toast_label: Label = $VBox/ToastLabel
@onready var timer: Timer = $PollerTimer

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_completed)
	
	load_saved_url()
	url_input.text = server_url
	
	show_toast("👑 مرحباً بك في تطبيق Admin Manager!")
	check_server_status()
	
	timer.timeout.connect(check_server_status)
	timer.start(3.0)

func load_saved_url() -> void:
	if FileAccess.file_exists("user://admin_url.txt"):
		var f = FileAccess.open("user://admin_url.txt", FileAccess.READ)
		if f:
			var saved = f.get_as_text().strip_edges()
			if saved != "":
				server_url = saved

func save_url(new_url: String) -> void:
	server_url = new_url.strip_edges()
	var f = FileAccess.open("user://admin_url.txt", FileAccess.WRITE)
	if f:
		f.store_string(server_url)

func show_toast(msg: String) -> void:
	toast_label.text = msg

func check_server_status() -> void:
	var req_url = server_url.strip_edges().trim_suffix("/") + "/api/server_status"
	var err = http_request.request(req_url, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		status_label.text = "🔴 خطأ في إرسال طلب السيرفر"

func _on_http_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var json = JSON.new()
		var parse_err = json.parse(body.get_string_from_utf8())
		if parse_err == OK and json.data is Dictionary:
			var d = json.data
			is_server_open = d.get("is_open", true)
			is_alarm_active = d.get("emergency_alarm", false)
			
			if is_server_open:
				status_label.text = "🟢 السيرفر: شغال ومفتوح (ONLINE)"
				server_btn.text = "🛑 إيقاف السيرفر (قفل اللعبة)"
				server_btn.modulate = Color(1.0, 0.4, 0.4)
			else:
				status_label.text = "🔴 السيرفر: مغلق للصيانة (CLOSED)"
				server_btn.text = "⚡ تشغيل وفتح السيرفر"
				server_btn.modulate = Color(0.2, 1.0, 0.6)
				
			if is_alarm_active:
				alarm_btn.text = "🔕 إيقاف صفارة الإنذار"
				alarm_btn.modulate = Color(1.0, 0.8, 0.2)
			else:
				alarm_btn.text = "🚨 إطلاق صفارة الإنذار"
				alarm_btn.modulate = Color(1.0, 0.3, 0.3)
	else:
		status_label.text = "⚠️ غير متصل بالسيرفر (كود: %d)" % response_code

func _on_connect_btn_pressed() -> void:
	save_url(url_input.text)
	show_toast("🔄 جاري الاتصال بـ: " + server_url)
	check_server_status()

func _on_server_toggle_pressed() -> void:
	var next_status = "CLOSED" if is_server_open else "OPEN"
	show_toast("⏳ جاري تغيير حالة السيرفر إلى: " + next_status)
	send_post("/api/admin/toggle_server", {"status": next_status})

func _on_alarm_toggle_pressed() -> void:
	var next_alarm = not is_alarm_active
	show_toast("⏳ جاري تحديث الإنذار...")
	send_post("/api/admin/emergency_alarm", {"active": next_alarm})

func _on_broadcast_btn_pressed() -> void:
	var msg = broadcast_input.text.strip_edges()
	if msg == "":
		show_toast("⚠️ اكتب رسالة أولاً!")
		return
	show_toast("📢 جاري إرسال الإعلان...")
	send_post("/api/admin/broadcast", {"message": msg})
	broadcast_input.text = ""

func _on_kill_rooms_btn_pressed() -> void:
	show_toast("🛑 جاري طرد اللاعبين وإنهاء كل الرومات...")
	send_post("/api/admin/rooms/clear", {})

func _on_open_dashboard_pressed() -> void:
	var target = server_url.strip_edges().trim_suffix("/") + "/admin"
	show_toast("🚀 فتح لوحة التحكم الشاملة في المتصفح...")
	OS.shell_open(target)

func send_post(endpoint: String, payload: Dictionary) -> void:
	var client = HTTPRequest.new()
	add_child(client)
	var body = JSON.stringify(payload)
	var headers = PackedStringArray(["Content-Type: application/json"])
	var target = server_url.strip_edges().trim_suffix("/") + endpoint
	client.request_completed.connect(func(_res, code, _h, _b):
		if code == 200:
			show_toast("✅ تم تنفيذ الأمر في السيرفر وقتياً!")
		else:
			show_toast("⚠️ استجابة السيرفر: %d" % code)
		check_server_status()
		client.queue_free()
	)
	client.request(target, headers, HTTPClient.METHOD_POST, body)
