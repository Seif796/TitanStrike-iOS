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

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}
var local_player_name: String = ""
var local_class_id: int = 0
var current_room_code: String = ""

# UDP Room Broadcaster & Listener
var udp_broadcaster: PacketPeerUDP = null
var udp_listener: PacketPeerUDP = null
var broadcast_timer: float = 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

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
		var p3 = int(parts[2])
		var p4 = int(parts[3])
		var num = (p3 * 256) + p4
		# Convert to 4-character hex or base36
		var hex_code = "%04X" % num
		current_room_code = hex_code
		return hex_code
	
	# Fallback 4-digit code
	current_room_code = str(randi_range(1000, 9999))
	return current_room_code

func decode_room_code_to_ip(code: String) -> String:
	code = code.strip_edges().replace("#", "")
	
	# 1. Direct IP address input (e.g. 192.168.44.1 for Bluetooth tethering, 192.168.43.1 for Hotspot)
	if code.find(".") != -1:
		return code
	
	# 2. Bluetooth / Hotspot keywords
	var upper = code.to_upper()
	if upper in ["BT", "BLUETOOTH", "BLUE"]:
		return get_bluetooth_or_hotspot_host_ip()
	if upper in ["HOTSPOT", "WIFI", "AP"]:
		return get_bluetooth_or_hotspot_host_ip()
	
	# 3. Hex code decoding
	code = code.to_upper()
	var local_ip = get_local_ip()
	var parts = local_ip.split(".")
	if parts.size() != 4:
		return "127.0.0.1"
	
	var base_subnet = "%s.%s" % [parts[0], parts[1]]
	if code.length() == 4:
		var num = ("0x" + code).hex_to_int()
		if num > 0:
			var p3 = int(num / 256)
			var p4 = int(num % 256)
			return "%s.%d.%d" % [base_subnet, p3, p4]
	
	return local_ip

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
	local_player_name = player_name
	local_class_id = class_id
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		print("Failed to create room server: ", error)
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
	
	print("Room created with Code: ", current_room_code)
	return OK

# --- JOIN ROOM WITH ROOM CODE ---

func join_room_with_code(code: String, player_name: String, class_id: int, port: int = DEFAULT_PORT) -> Error:
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
	stop_discovery_listener()
	if udp_broadcaster:
		udp_broadcaster.close()
		udp_broadcaster = null
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	peer = null

# --- MULTIPLAYER CALLBACKS ---

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		for p_id in players:
			rpc_id(id, "_register_player", p_id, players[p_id])
		# Sync the currently chosen map and game mode to the new player immediately!
		rpc_id(id, "_sync_initial_lobby_map", GameManager.selected_map_id, int(GameManager.selected_game_mode))
		lobby_updated.emit()

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
	var candidates: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.begins_with("127.") or ip.find(":") != -1:
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
		# Standard Wi-Fi LAN subnets
		if ip.begins_with("192.168."):
			candidates.push_front(ip)
		elif ip.begins_with("10.") or (ip.begins_with("172.") and int(ip.split(".")[1]) >= 16 and int(ip.split(".")[1]) <= 31):
			candidates.push_back(ip)
	
	if not candidates.is_empty():
		return candidates[0]
	return "127.0.0.1"
