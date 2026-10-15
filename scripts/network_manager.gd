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
	# Broadcast Room Code on local network if hosting
	if udp_broadcaster and multiplayer.is_server():
		broadcast_timer += delta
		if broadcast_timer >= 1.0:
			broadcast_timer = 0.0
			var msg = "CYBERFORT:%s:%d" % [current_room_code, DEFAULT_PORT]
			udp_broadcaster.put_packet(msg.to_utf8_buffer())

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
	code = code.strip_edges().to_upper().replace("#", "")
	var local_ip = get_local_ip()
	var parts = local_ip.split(".")
	if parts.size() != 4:
		return "127.0.0.1"
	
	var base_subnet = "%s.%s" % [parts[0], parts[1]]
	
	# Try decoding 4-character hex
	if code.length() == 4:
		var num = ("0x" + code).hex_to_int()
		if num > 0:
			var p3 = int(num / 256)
			var p4 = int(num % 256)
			return "%s.%d.%d" % [base_subnet, p3, p4]
	
	return local_ip

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

func leave_game() -> void:
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
		
		# Auto launch match when someone joins
		_start_auto_launch_countdown()

func _start_auto_launch_countdown() -> void:
	rpc("_sync_launch_countdown", 3)
	get_tree().create_timer(1.0).timeout.connect(func():
		rpc("_sync_launch_countdown", 2)
		get_tree().create_timer(1.0).timeout.connect(func():
			rpc("_sync_launch_countdown", 1)
			get_tree().create_timer(1.0).timeout.connect(func():
				GameManager.rpc("start_game_scene")
			)
		)
	)

@rpc("call_local", "reliable")
func _sync_launch_countdown(sec: int) -> void:
	room_launch_countdown.emit(sec)

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
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and int(ip.split(".")[1]) >= 16 and int(ip.split(".")[1]) <= 31):
			return ip
	return "127.0.0.1"
