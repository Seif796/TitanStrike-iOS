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

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}
var local_player_name: String = ""
var local_class_id: int = 0
var current_room_code: String = ""
var last_received_msg_id: int = 0
var _broadcast_overlay: CanvasLayer = null
var _ejected_overlay: CanvasLayer = null

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
	var ip = get_local_ip()
	var parts = ip.split(".")
	if parts.size() == 4:
		var b1 = int(parts[0])
		var b2 = int(parts[1])
		var b3 = int(parts[2])
		var b4 = int(parts[3])
		current_room_code = "%02X%02X%02X%02X" % [b1, b2, b3, b4]
		return current_room_code
	
	current_room_code = "7777"
	return current_room_code

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
	if _room_watchdog_timer:
		_room_watchdog_timer.start()
	return OK

# --- JOIN ROOM WITH ROOM CODE ---

func join_room_with_code(code: String, player_name: String, class_id: int, port: int = DEFAULT_PORT) -> Error:
	leave_game()
	local_player_name = player_name
	local_class_id = class_id
	current_room_code = code.strip_edges().to_upper().replace("#", "")
	
	var target_ip = decode_room_code_to_ip(current_room_code)
	print("Joining Room Code: ", current_room_code, " -> Resolved IP: ", target_ip)
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, port)
	if error != OK:
		print("Failed to join room: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	if _room_watchdog_timer:
		_room_watchdog_timer.start()
	
	# Connection watchdog: 6 seconds timeout
	get_tree().create_timer(6.0).timeout.connect(func():
		if peer and multiplayer.multiplayer_peer == peer and multiplayer.get_unique_id() == 0:
			print("Connection watchdog timed out to: %s:%d" % [target_ip, port])
			leave_game()
			connection_failed.emit()
	)
	
	return OK

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
	var payload = {
		"room_code": code,
		"host_name": host_name,
		"mode": "Multiplayer",
		"players": players.size()
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
	if _broadcast_overlay != null:
		_broadcast_overlay.queue_free()
		_broadcast_overlay = null
	
	AudioManager.play_sfx("redeem")
	_broadcast_overlay = CanvasLayer.new()
	_broadcast_overlay.layer = 128
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	_broadcast_overlay.add_child(margin)
	
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.18, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.65, 0.35, 1.0, 0.95)
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
	icon.text = "📢"
	icon.add_theme_font_size_override("font_size", 28)
	hbox.add_child(icon)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	var title = Label.new()
	title.text = "كلمة ورسالة عاجلة من القائد (Message from Leader)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.75, 0.5, 1.0))
	vbox.add_child(title)
	
	var content = Label.new()
	content.text = msg
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_theme_font_size_override("font_size", 14)
	content.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(content)
	
	var close_btn = Button.new()
	close_btn.text = " ✕ "
	close_btn.pressed.connect(func():
		if _broadcast_overlay:
			_broadcast_overlay.queue_free()
			_broadcast_overlay = null
	)
	hbox.add_child(close_btn)
	
	get_tree().root.add_child(_broadcast_overlay)
	
	get_tree().create_timer(7.5).timeout.connect(func():
		if _broadcast_overlay:
			_broadcast_overlay.queue_free()
			_broadcast_overlay = null
	)

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
	var local_id = multiplayer.get_unique_id()
	rpc("_register_player", local_id, {
		"name": local_player_name,
		"class_id": local_class_id,
		"ready": true
	})
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	leave_game()
	server_disconnected.emit()

@rpc("any_peer", "call_local", "reliable")
func _register_player(id: int, info: Dictionary) -> void:
	players[id] = info
	player_connected.emit(id, info)
	lobby_updated.emit()

func get_local_ip() -> String:
	var all_ips: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.begins_with("127.") or ip.find(":") != -1 or ip.begins_with("169.254."):
			continue
		# Prioritize Bluetooth PAN (192.168.44.x)
		if ip.begins_with("192.168.44."):
			return ip
		# Prioritize Android Hotspot (192.168.43.x)
		if ip.begins_with("192.168.43."):
			return ip
		# Prioritize iOS Personal Hotspot / Bluetooth (172.20.10.x)
		if ip.begins_with("172.20.10."):
			return ip
		all_ips.append(ip)

	# If UpdateManager has an active server URL, pick the matching subnet!
	var um = get_node_or_null("/root/UpdateManager")
	if um and not um.server_url.is_empty():
		for ip in all_ips:
			var parts = ip.split(".")
			if parts.size() == 4:
				var prefix = parts[0] + "." + parts[1] + "." + parts[2] + "."
				if um.server_url.find(prefix) != -1:
					return ip

	# Priority 1: Real Wi-Fi subnets (192.168.x) not ending with .1 and not Hyper-V virtual switch
	for ip in all_ips:
		if ip.begins_with("192.168.") and not ip.ends_with(".1") and not ip.begins_with("192.168.128.") and not ip.begins_with("192.168.176."):
			return ip

	# Priority 2: Any 192.168.x not ending with .1
	for ip in all_ips:
		if ip.begins_with("192.168.") and not ip.ends_with(".1"):
			return ip

	# Priority 3: 172.x private subnets not ending with .1
	for ip in all_ips:
		if ip.begins_with("172.") and not ip.ends_with(".1"):
			return ip

	# Priority 4: 10.x private subnets not ending with .1
	for ip in all_ips:
		if ip.begins_with("10.") and not ip.ends_with(".1"):
			return ip

	if not all_ips.is_empty():
		return all_ips[0]
	return "127.0.0.1"
