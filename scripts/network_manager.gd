extends Node

# NetworkManager Autoload (res://scripts/network_manager.gd)
# Handles Room Creation, Room Joining, peer sync, and automatic match launch when a player joins.

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal connection_failed()
signal connection_succeeded()
signal lobby_updated()
signal room_launch_countdown(seconds_left: int)

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {} # peer_id -> { "name": String, "class_id": int, "ready": bool }
var local_player_name: String = "Player"
var local_class_id: int = 0
var room_code: String = "ROOM-1"

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- CREATE ROOM ---

func create_room(player_name: String, class_id: int, port: int = DEFAULT_PORT) -> Error:
	local_player_name = player_name
	local_class_id = class_id
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		print("Failed to create room: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	players[1] = {
		"name": local_player_name,
		"class_id": local_class_id,
		"ready": true
	}
	print("Room created on port ", port, " with Host peer ID 1")
	return OK

# --- JOIN ROOM ---

func join_room(address: String, player_name: String, class_id: int, port: int = DEFAULT_PORT) -> Error:
	local_player_name = player_name
	local_class_id = class_id
	if address.strip_edges() == "":
		address = "127.0.0.1"
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		print("Failed to join room: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Connecting to Room at ", address, ":", port)
	return OK

func leave_game() -> void:
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	peer = null

# --- MULTIPLAYER CALLBACKS ---

func _on_peer_connected(id: int) -> void:
	print("Player joined room: ", id)
	if multiplayer.is_server():
		# Send existing player info to new peer
		for p_id in players:
			rpc_id(id, "_register_player", p_id, players[p_id])
		
		# Auto-launch match as soon as someone joins! ("اول ما حد يخش يبدا العبه")
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

# --- REGISTRATION RPC ---

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
