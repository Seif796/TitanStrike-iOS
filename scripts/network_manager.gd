extends Node

# NetworkManager Autoload (res://scripts/network_manager.gd)
# Handles Room Code generation, UDP LAN room discovery, and direct code decoding.

const DEFAULT_PORT: int = 7777
const DISCOVERY_PORT: int = 7778
const MAX_PLAYERS: int = 4

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal connection_failed()
signal connection_succeeded()
signal lobby_updated()
signal room_launch_countdown(seconds_left: int)
signal room_discovered(room_code: String, host_ip: String, map_id: int)
signal leader_broadcast_received(message: String)
signal connection_status_updated(status_message: String)

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}
var local_player_name: String = ""
var local_class_id: int = 0
var current_room_code: String = ""
var last_received_msg_id: int = 0
var _broadcast_overlay: CanvasLayer = null
var _ejected_overlay: CanvasLayer = null

# Multi-IP Fast Connect Waterfall State
var _joining_candidates: Array[String] = []
var _candidate_idx: int = 0
var _connecting_port: int = DEFAULT_PORT
var _is_connecting: bool = false

# UDP Room Broadcaster & Listener
var udp_broadcaster: PacketPeerUDP = null
var udp_listener: PacketPeerUDP = null
var broadcast_timer: float = 0.0

var _room_api_http: HTTPRequest = null
var _room_watchdog_timer: Timer = null

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	_room_api_http = HTTPRequest.new()
	_room_api_http.timeout = 2.0
	add_child(_room_api_http)
	_room_api_http.request_completed.connect(_on_room_api_completed)
	
	_room_watchdog_timer = Timer.new()
	_room_watchdog_timer.wait_time = 2.0
	_room_watchdog_timer.autostart = false
	_room_watchdog_timer.one_shot = false
	add_child(_room_watchdog_timer)
	_room_watchdog_timer.timeout.connect(_check_room_status_with_server)

func _process(delta: float) -> void:
	# Broadcast Room Code and Host IP on local network / Bluetooth if hosting
	if udp_broadcaster and multiplayer.is_server():
		broadcast_timer += delta
		if broadcast_timer >= 1.0:
			broadcast_timer = 0.0
			var host_ip = get_local_ip()
			var msg = "TITANSTRIKE:%s:%s:%d:%d:%d" % [current_room_code, host_ip, DEFAULT_PORT, GameManager.selected_map_id, int(GameManager.selected_game_mode)]
			var buf = msg.to_utf8_buffer()
			udp_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			udp_broadcaster.put_packet(buf)
			var parts = host_ip.split(".")
			if parts.size() == 4:
				var subnet_bc = "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
				udp_broadcaster.set_dest_address(subnet_bc, DISCOVERY_PORT)
				udp_broadcaster.put_packet(buf)
	
	# Listen for rooms if discovery listener is active
	if udp_listener and udp_listener.get_available_packet_count() > 0:
		var pkt = udp_listener.get_packet().get_string_from_utf8()
		if pkt.begins_with("TITANSTRIKE:"):
			var parts = pkt.split(":")
			if parts.size() >= 4:
				var r_code = parts[1]
				var r_ip = parts[2]
				var r_map = int(parts[4]) if parts.size() >= 5 else 0
				room_discovered.emit(r_code, r_ip, r_map)

# --- ROOM CODE ENCODING / DECODING ---

func generate_room_code() -> String:
	# Clean, easy-to-share 4-digit Room Code for instant joining without IP
	current_room_code = "%04d" % randi_range(1000, 9999)
	return current_room_code

func is_ai_duel_room_code(code: String) -> bool:
	var clean = code.strip_edges().to_upper().replace("#", "")
	return clean in ["AI1V1", "CYBERAI", "BOT1V1", "AI-1V1", "BOT", "AI"]

func decode_room_code_to_ip(code: String) -> String:
	code = code.strip_edges().replace("#", "")
	
	# 1. Direct IPv4 address input (e.g. 192.168.43.1 or 192.168.1.15)
	if code.find(".") != -1:
		var dots = code.split(".")
		if dots.size() == 4:
			return code
		elif dots.size() == 2:
			var local_ip = get_local_ip()
			var l_parts = local_ip.split(".")
			if l_parts.size() == 4:
				return "%s.%s.%s.%s" % [l_parts[0], l_parts[1], dots[0], dots[1]]
			return "192.168.%s.%s" % [dots[0], dots[1]]
	
	# 2. Bluetooth / Hotspot keywords
	var upper = code.to_upper()
	if upper in ["BT", "BLUETOOTH", "BLUE", "HOTSPOT", "WIFI", "AP"]:
		return get_bluetooth_or_hotspot_host_ip()
	
	# 3. 8-character Full IP Hex (100% subnet-independent, e.g. C0A82B01 -> 192.168.43.1)
	if upper.length() == 8:
		var b1 = ("0x" + upper.substr(0, 2)).hex_to_int()
		var b2 = ("0x" + upper.substr(2, 2)).hex_to_int()
		var b3 = ("0x" + upper.substr(4, 2)).hex_to_int()
		var b4 = ("0x" + upper.substr(6, 2)).hex_to_int()
		if b1 > 0:
			return "%d.%d.%d.%d" % [b1, b2, b3, b4]
	
	# 4. 4-character legacy hex code (e.g. 2B01)
	if upper.length() <= 4 and upper.length() >= 2:
		var padded = upper.pad_zeros(4)
		var num = ("0x" + padded).hex_to_int()
		if num > 0:
			var p3 = int(num / 256)
			var p4 = int(num % 256)
			var local_ip = get_local_ip()
			var parts = local_ip.split(".")
			if parts.size() == 4 and parts[0] == "192":
				return "%s.%s.%d.%d" % [parts[0], parts[1], p3, p4]
			return "192.168.%d.%d" % [p3, p4]
	
	return get_bluetooth_or_hotspot_host_ip()

func get_bluetooth_or_hotspot_host_ip() -> String:
	var my_ip = get_local_ip()
	if my_ip.begins_with("192.168.44."):
		return "192.168.44.1" # Android Bluetooth Tethering Host Gateway
	if my_ip.begins_with("192.168.43."):
		return "192.168.43.1" # Android Mobile Hotspot Host Gateway
	if my_ip.begins_with("172.20.10."):
		return "172.20.10.1" # iOS Personal Hotspot / Bluetooth Host Gateway
	# Standard default fallback for Bluetooth PAN
	return "192.168.44.1"

# --- CREATE ROOM ---

func create_room(player_name: String, class_id: int, port: int = DEFAULT_PORT) -> Error:
	leave_game()
	local_player_name = player_name
	local_class_id = class_id
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		print("Failed to create room server on port %d: %d, trying backup port %d..." % [port, error, port + 2])
		error = peer.create_server(port + 2, MAX_PLAYERS)
		if error != OK:
			return error
	
	multiplayer.multiplayer_peer = peer
	players[1] = {
		"name": local_player_name,
		"class_id": local_class_id,
		"ready": true
	}
	
	# Setup UDP Broadcaster
	udp_broadcaster = PacketPeerUDP.new()
	udp_broadcaster.set_broadcast_enabled(true)
	udp_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	
	print("Room created with Code: ", current_room_code, " | Host IP: ", get_local_ip())
	_report_room_created(current_room_code, local_player_name)
	var um = get_node_or_null("/root/UpdateManager")
	if um:
		var hero_n = GameManager.CLASSES.get(local_class_id, {}).get("name", "Hero")
		um.report_active_player_session(local_player_name, "👑 Squad Room #%s (Host)" % current_room_code, hero_n, "HOSTING")
	if _room_watchdog_timer:
		_room_watchdog_timer.start()
	return OK

# --- JOIN ROOM WITH ROOM CODE (Multi-IP Fast Waterfall) ---

func join_room_with_code(code: String, player_name: String, class_id: int, port: int = DEFAULT_PORT) -> Error:
	leave_game()
	local_player_name = player_name
	local_class_id = class_id
	current_room_code = code.strip_edges().to_upper().replace("#", "")
	
	# 1. AI 1v1 Duel Special Code (#AI1V1, CYBERAI, etc.)
	if is_ai_duel_room_code(current_room_code):
		print("🤖 AI Duel code detected (#%s)! Starting 1v1 Duel with CyberAI immediately..." % current_room_code)
		var cur_scene = get_tree().current_scene
		if cur_scene and cur_scene.has_method("start_duel_against_cyber_ai"):
			cur_scene.start_duel_against_cyber_ai()
			return OK
		else:
			GameManager.selected_game_mode = GameManager.GameMode.PVP_DUEL
			GameManager.bot_enabled = true
			GameManager.bot_class_id = 4
			GameManager.start_game_scene()
			return OK
	
	_joining_candidates.clear()
	_candidate_idx = 0
	_connecting_port = port

	# 2. If code is directly an IP with dots (e.g. 192.168.1.15), connect to it directly
	if current_room_code.find(".") != -1 and current_room_code.split(".").size() == 4:
		_joining_candidates.append(current_room_code)
		_start_next_candidate_connection()
		return OK

	# 3. Query Central Server FIRST for Host Candidate IPs (Ultra-Fast < 0.2s lookup!)
	var um = get_node_or_null("/root/UpdateManager")
	if um and not um.server_url.is_empty():
		var status_msg = "⚡ جاري البحث عن الغرفة #%s في السيرفر..." % current_room_code
		connection_status_updated.emit(status_msg)
		var cur_scene = get_tree().current_scene
		if cur_scene and "status_label" in cur_scene and cur_scene.status_label:
			cur_scene.status_label.text = status_msg
			cur_scene.status_label.modulate = Color(0.2, 0.9, 1.0)
			
		var http = HTTPRequest.new()
		http.timeout = 1.0
		add_child(http)
		http.request_completed.connect(func(res: int, code_resp: int, _h: PackedStringArray, body: PackedByteArray):
			http.queue_free()
			if res == HTTPRequest.RESULT_SUCCESS and code_resp == 200:
				var j = JSON.new()
				if j.parse(body.get_string_from_utf8()) == OK and typeof(j.data) == TYPE_DICTIONARY:
					if j.data.get("active", false):
						var h_ip = str(j.data.get("host_ip", "")).strip_edges()
						var c_ips = j.data.get("candidate_ips", [])
						var r_port = int(j.data.get("port", port))
						_connecting_port = r_port
						
						if not h_ip.is_empty() and not _joining_candidates.has(h_ip):
							_joining_candidates.append(h_ip)
						if typeof(c_ips) == TYPE_ARRAY:
							for cip in c_ips:
								var s_ip = str(cip).strip_edges()
								if not s_ip.is_empty() and not _joining_candidates.has(s_ip):
									_joining_candidates.append(s_ip)
									
						print("⚡ Found active room #%s on server! Connecting immediately to: " % current_room_code, _joining_candidates)
						_start_next_candidate_connection()
						return
			_populate_fallback_candidates_and_start()
		)
		var endpoint = um.server_url.trim_suffix("/") + "/api/rooms/check?code=" + current_room_code
		var err = http.request(endpoint)
		if err != OK:
			http.queue_free()
			_populate_fallback_candidates_and_start()
	else:
		_populate_fallback_candidates_and_start()
		
	return OK

func _populate_fallback_candidates_and_start() -> void:
	var decoded_ip = decode_room_code_to_ip(current_room_code)
	if not decoded_ip.is_empty() and not _joining_candidates.has(decoded_ip):
		_joining_candidates.append(decoded_ip)
	
	var gw_ip = get_bluetooth_or_hotspot_host_ip()
	if not _joining_candidates.has(gw_ip):
		_joining_candidates.append(gw_ip)
	
	for ip in get_all_local_ips():
		if not _joining_candidates.has(ip):
			_joining_candidates.append(ip)
	
	if not _joining_candidates.has("127.0.0.1"):
		_joining_candidates.append("127.0.0.1")
		
	_start_next_candidate_connection()

func _query_server_for_room_candidates(code: String) -> void:
	var um = get_node_or_null("/root/UpdateManager")
	if um == null or um.server_url.is_empty():
		return
	var http = HTTPRequest.new()
	http.timeout = 1.2
	add_child(http)
	http.request_completed.connect(func(res: int, code_resp: int, _h: PackedStringArray, body: PackedByteArray):
		if res == HTTPRequest.RESULT_SUCCESS and code_resp == 200:
			var j = JSON.new()
			if j.parse(body.get_string_from_utf8()) == OK and typeof(j.data) == TYPE_DICTIONARY:
				var c_ips = j.data.get("candidate_ips", [])
				if typeof(c_ips) == TYPE_ARRAY:
					for cip in c_ips:
						var s_ip = str(cip).strip_edges()
						if not s_ip.is_empty() and not _joining_candidates.has(s_ip):
							_joining_candidates.insert(_candidate_idx + 1, s_ip)
		http.queue_free()
	)
	var endpoint = um.server_url.trim_suffix("/") + "/api/rooms/check?code=" + code
	http.request(endpoint)

func _start_next_candidate_connection() -> void:
	if _candidate_idx >= _joining_candidates.size():
		print("❌ All candidate IPs failed for room #%s!" % current_room_code)
		leave_game()
		connection_failed.emit()
		return
	
	var target_ip = _joining_candidates[_candidate_idx]
	print("⚡ [Fast Connect] Trying candidate IP (%d/%d): %s:%d" % [_candidate_idx + 1, _joining_candidates.size(), target_ip, _connecting_port])
	
	var status_msg = "⚡ جاري الاتصال السريع عبر %s (%d/%d)..." % [target_ip, _candidate_idx + 1, _joining_candidates.size()]
	connection_status_updated.emit(status_msg)
	
	var cur_scene = get_tree().current_scene
	if cur_scene and "status_label" in cur_scene and cur_scene.status_label:
		cur_scene.status_label.text = status_msg
		cur_scene.status_label.modulate = Color.CYAN
	
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, _connecting_port)
	if error != OK:
		print("Direct create_client failed for %s: %d. Advancing immediately..." % [target_ip, error])
		_candidate_idx += 1
		_start_next_candidate_connection()
		return
	
	multiplayer.multiplayer_peer = peer
	_is_connecting = true
	
	# Fast Watchdog: 1.4 seconds timeout per candidate
	get_tree().create_timer(1.4).timeout.connect(func():
		if _is_connecting and peer != null and multiplayer.multiplayer_peer == peer and multiplayer.get_unique_id() == 0:
			print("⏱️ Watchdog: IP %s timed out after 1.4s. Advancing to next candidate..." % target_ip)
			_candidate_idx += 1
			_start_next_candidate_connection()
	)

func start_discovery_listener() -> void:
	if not udp_listener:
		udp_listener = PacketPeerUDP.new()
		var err = udp_listener.bind(DISCOVERY_PORT)
		if err != OK:
			print("Discovery listener bind status: ", err)

func stop_discovery_listener() -> void:
	if udp_listener:
		udp_listener.close()
		udp_listener = null

func leave_game() -> void:
	_is_connecting = false
	_joining_candidates.clear()
	_candidate_idx = 0
	if _room_watchdog_timer:
		_room_watchdog_timer.stop()
	if multiplayer and multiplayer.is_server() and not current_room_code.is_empty():
		_report_room_closed(current_room_code)
	stop_discovery_listener()
	if udp_broadcaster:
		udp_broadcaster.close()
		udp_broadcaster = null
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	peer = null
	current_room_code = ""

func _report_room_created(code: String, host_name: String) -> void:
	var um = get_node_or_null("/root/UpdateManager")
	if um == null or um.server_url.is_empty():
		return
	var endpoint = um.server_url.trim_suffix("/") + "/api/rooms/create"
	var p_names: Array[String] = [host_name]
	for p_id in players:
		var n = players[p_id].get("name", "")
		if not n.is_empty() and not p_names.has(n):
			p_names.append(n)
	var payload = {
		"room_code": code,
		"host_name": host_name,
		"mode": "Multiplayer",
		"players": max(1, players.size()),
		"players_list": p_names,
		"host_ip": get_local_ip(),
		"candidate_ips": get_all_local_ips(),
		"port": DEFAULT_PORT
	}
	var http = HTTPRequest.new()
	http.timeout = 2.5
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	var headers = PackedStringArray(["Content-Type: application/json"])
	http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _report_room_closed(code: String) -> void:
	var um = get_node_or_null("/root/UpdateManager")
	if um == null or um.server_url.is_empty():
		return
	var endpoint = um.server_url.trim_suffix("/") + "/api/rooms/close"
	var payload = {
		"room_code": code
	}
	var http = HTTPRequest.new()
	http.timeout = 2.5
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	var headers = PackedStringArray(["Content-Type: application/json"])
	http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func update_room_details(mode_name: String = "", player_count: int = -1, status_str: String = "") -> void:
	if current_room_code.is_empty() or not multiplayer or not multiplayer.is_server():
		return
	var um = get_node_or_null("/root/UpdateManager")
	if um == null or um.server_url.is_empty():
		return
	var endpoint = um.server_url.trim_suffix("/") + "/api/rooms/update"
	var payload = {
		"room_code": current_room_code
	}
	if not mode_name.is_empty():
		payload["mode"] = mode_name
	if player_count >= 0:
		payload["players"] = player_count
	else:
		payload["players"] = players.size()
	if not status_str.is_empty():
		payload["status"] = status_str
	
	var p_names: Array[String] = []
	for p_id in players:
		p_names.append(players[p_id].get("name", "Player"))
	payload["players_list"] = p_names

	var http = HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	var headers = PackedStringArray(["Content-Type: application/json"])
	http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _check_room_status_with_server() -> void:
	if current_room_code.is_empty() or peer == null:
		if _room_watchdog_timer:
			_room_watchdog_timer.stop()
		return
	
	var um = get_node_or_null("/root/UpdateManager")
	if um and not um.server_url.is_empty():
		# Host keeps room status actively synced
		if multiplayer and multiplayer.is_server():
			update_room_details()
		var endpoint = um.server_url.trim_suffix("/") + "/api/rooms/check?code=" + current_room_code
		if _room_api_http and _room_api_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			_room_api_http.request(endpoint)

func _on_room_api_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		if json.data.get("terminated", false) == true:
			_handle_room_force_closed_by_leader()
			return
		
		# Check for leader broadcast message to room players
		var msg = str(json.data.get("message", "")).strip_edges()
		var msg_id = int(json.data.get("message_id", 0))
		if not msg.is_empty() and msg_id > last_received_msg_id:
			last_received_msg_id = msg_id
			leader_broadcast_received.emit(msg)
			show_leader_broadcast(msg)

func _handle_room_force_closed_by_leader() -> void:
	if current_room_code.is_empty() and peer == null:
		return
	var old_code = current_room_code
	print("🛑 Room #%s was terminated forcefully by Leader!" % old_code)
	leave_game()
	
	show_ejected_by_leader_notification(old_code)
	
	var tree = get_tree()
	if tree:
		var scene = tree.current_scene
		if scene and scene.has_method("_show_room_terminated_notification"):
			scene._show_room_terminated_notification(old_code)
		else:
			tree.change_scene_to_file("res://scenes/main_menu.tscn")

func show_ejected_by_leader_notification(old_code: String) -> void:
	if _ejected_overlay != null:
		_ejected_overlay.queue_free()
		_ejected_overlay = null
	
	AudioManager.play_sfx("error")
	_ejected_overlay = CanvasLayer.new()
	_ejected_overlay.layer = 130
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	_ejected_overlay.add_child(margin)
	
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.04, 0.06, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.2, 0.25, 0.95)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	card.add_theme_stylebox_override("panel", style)
	margin.add_child(card)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	card.add_child(hbox)
	
	var icon = Label.new()
	icon.text = "🛑"
	icon.add_theme_font_size_override("font_size", 28)
	hbox.add_child(icon)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	var title = Label.new()
	title.text = "تم إخراجك وإنهاء الغرفة بأمر من القائد!"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.35))
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = "قام مدير السيرفر بطرد جميع اللاعبين من الغرفة #%s وإعادتكم للقائمة الرئيسية." % old_code
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	vbox.add_child(desc)
	
	var close_btn = Button.new()
	close_btn.text = " ✕ "
	close_btn.pressed.connect(func():
		if _ejected_overlay:
			_ejected_overlay.queue_free()
			_ejected_overlay = null
	)
	hbox.add_child(close_btn)
	
	get_tree().root.add_child(_ejected_overlay)
	
	get_tree().create_timer(6.0).timeout.connect(func():
		if _ejected_overlay:
			_ejected_overlay.queue_free()
			_ejected_overlay = null
	)

func show_leader_broadcast(msg: String) -> void:
	var um = get_node_or_null("/root/UpdateManager")
	if um:
		um.show_leader_broadcast_banner(msg)

# --- MULTIPLAYER CALLBACKS ---

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		for p_id in players:
			rpc_id(id, "_register_player", p_id, players[p_id])
		# Sync the currently chosen map and game mode to the new player immediately!
		rpc_id(id, "_sync_initial_lobby_map", GameManager.selected_map_id, int(GameManager.selected_game_mode))
		lobby_updated.emit()
		update_room_details("", players.size() + 1)

@rpc("any_peer", "call_local", "reliable")
func _sync_initial_lobby_map(map_id: int, mode_id: int = 0) -> void:
	GameManager.selected_map_id = map_id
	GameManager.selected_game_mode = mode_id as GameManager.GameMode
	var cur_scene = get_tree().current_scene
	if cur_scene and cur_scene.has_method("_sync_map_selection"):
		cur_scene._sync_map_selection(map_id)
	if cur_scene and cur_scene.has_method("_sync_game_mode"):
		cur_scene._sync_game_mode(mode_id)

@rpc("any_peer", "call_local", "reliable")
func update_player_class(p_id: int, new_c_id: int) -> void:
	if players.has(p_id):
		players[p_id]["class_id"] = new_c_id
		lobby_updated.emit()

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_disconnected.emit(id)
		lobby_updated.emit()
		if multiplayer.is_server():
			update_room_details("", players.size())

func _on_connected_to_server() -> void:
	_is_connecting = false
	_joining_candidates.clear()
	_candidate_idx = 0
	if _room_watchdog_timer:
		_room_watchdog_timer.start()
	var local_id = multiplayer.get_unique_id()
	rpc("_register_player", local_id, {
		"name": local_player_name,
		"class_id": local_class_id,
		"ready": true
	})
	var um = get_node_or_null("/root/UpdateManager")
	if um:
		var hero_n = GameManager.CLASSES.get(local_class_id, {}).get("name", "Hero")
		um.report_active_player_session(local_player_name, "👥 Squad Room #%s" % current_room_code, hero_n, "IN_ROOM")
		um.log_game_event("دخل اللاعب '%s' الغرفة #%s بنجاح!" % [local_player_name, current_room_code], "SUCCESS", "ROOM")
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	if _is_connecting and _candidate_idx + 1 < _joining_candidates.size():
		print("Peer connection failed for current candidate IP. Advancing immediately...")
		_candidate_idx += 1
		_start_next_candidate_connection()
		return
	_is_connecting = false
	connection_failed.emit()

func _on_server_disconnected() -> void:
	leave_game()
	server_disconnected.emit()

@rpc("any_peer", "call_local", "reliable")
func _register_player(id: int, info: Dictionary) -> void:
	players[id] = info
	player_connected.emit(id, info)
	lobby_updated.emit()
	if multiplayer and multiplayer.is_server():
		update_room_details("", players.size())
		var p_name = info.get("name", "لاعب")
		var um = get_node_or_null("/root/UpdateManager")
		if um and id != 1:
			um.log_game_event("انضم اللاعب '%s' إلى الغرفة #%s بنجاح!" % [p_name, current_room_code], "SUCCESS", "ROOM")

func get_all_local_ips() -> Array[String]:
	var raw_ips = IP.get_local_addresses()
	var wifi_lan: Array[String] = []
	var hotspot: Array[String] = []
	var other_private: Array[String] = []
	var virtual_adapters: Array[String] = []
	
	for ip in raw_ips:
		if ip.find(":") != -1 or ip.begins_with("169.254."):
			continue
		if ip == "127.0.0.1":
			continue
		
		# Mobile Hotspots & Bluetooth Tethering
		if ip.begins_with("192.168.43.") or ip.begins_with("172.20.10.") or ip.begins_with("192.168.44."):
			if not hotspot.has(ip):
				hotspot.append(ip)
			continue
		
		# Real Wi-Fi / LAN: 192.168.x (not ending in .1 unless that's all there is)
		if ip.begins_with("192.168."):
			if not ip.ends_with(".1"):
				if not wifi_lan.has(ip):
					wifi_lan.append(ip)
			else:
				if not other_private.has(ip):
					other_private.append(ip)
			continue
		
		# Virtual Switches (Hyper-V, WSL, Docker: typically 172.16-31.x.1)
		var is_v_switch = false
		if ip.begins_with("172.") and ip.ends_with(".1"):
			is_v_switch = true
		
		if is_v_switch:
			if not virtual_adapters.has(ip):
				virtual_adapters.append(ip)
		else:
			if not other_private.has(ip):
				other_private.append(ip)

	var ordered: Array[String] = []
	
	# If UpdateManager has an active server URL, put matching subnet IP first!
	var um = get_node_or_null("/root/UpdateManager")
	if um and not um.server_url.is_empty():
		for group in [hotspot, wifi_lan, other_private, virtual_adapters]:
			for ip in group:
				var parts = ip.split(".")
				if parts.size() == 4:
					var prefix = parts[0] + "." + parts[1] + "." + parts[2] + "."
					if um.server_url.find(prefix) != -1 and not ordered.has(ip):
						ordered.append(ip)

	for ip in wifi_lan:
		if not ordered.has(ip): ordered.append(ip)
	for ip in hotspot:
		if not ordered.has(ip): ordered.append(ip)
	for ip in other_private:
		if not ordered.has(ip): ordered.append(ip)
	for ip in virtual_adapters:
		if not ordered.has(ip): ordered.append(ip)
	
	if not ordered.has("127.0.0.1"):
		ordered.append("127.0.0.1")
	
	return ordered

func get_local_ip() -> String:
	var list = get_all_local_ips()
	if not list.is_empty():
		for ip in list:
			if ip != "127.0.0.1":
				return ip
		return list[0]
	return "127.0.0.1"
