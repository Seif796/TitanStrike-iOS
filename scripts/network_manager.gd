extends Node

# NetworkManager Autoload (res://scripts/network_manager.gd)
# Handles multiplayer hosting, joining, peer synchronization, and player data.

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal connection_failed()
signal connection_succeeded()
signal lobby_updated()

var peer: ENetMultiplayerPeer = null
var players: Dictionary = {} # peer_id -> { "name": String, "class_id": int, "ready": bool }
var local_player_name: String = "Player"
var local_class_id: int = 0 # 0: Assault, 1: Heavy, 2: Scout

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- HOSTING & JOINING ---

func host_game(player_name: String, class_id: int, port: int = DEFAULT_PORT) -> Error:
	local_player_name = player_name
	local_class_id = class_id
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		print("Failed to host game: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	players[1] = {
		"name": local_player_name,
		"class_id": local_class_id,
		"ready": true
	}
	print("Game hosted on port ", port, " with peer ID 1")
	return OK

func join_game(address: String, player_name: String, class_id: int, port: int = DEFAULT_PORT) -> Error:
	local_player_name = player_name
	local_class_id = class_id
	if address.strip_edges() == "":
		address = "127.0.0.1"
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		print("Failed to connect to host: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Connecting to ", address, ":", port)
	return OK

func leave_game() -> void:
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	peer = null

# --- MULTIPLAYER CALLBACKS ---

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	# When a client connects, register local info with host
	if multiplayer.is_server():
		# Send existing player list to new peer
		for p_id in players:
			rpc_id(id, "_register_player", p_id, players[p_id])

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if players.has(id):
		players.erase(id)
		player_disconnected.emit(id)
		lobby_updated.emit()

func _on_connected_to_server() -> void:
	print("Connected to server!")
	var local_id = multiplayer.get_unique_id()
	# Register myself with server
	rpc("_register_player", local_id, {
		"name": local_player_name,
		"class_id": local_class_id,
		"ready": false
	})
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("Connection to server failed.")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("Server disconnected.")
	leave_game()
	server_disconnected.emit()

# --- RPCs FOR REGISTRATION & LOBBY ---

@rpc("any_peer", "call_local", "reliable")
func _register_player(id: int, info: Dictionary) -> void:
	players[id] = info
	player_connected.emit(id, info)
	lobby_updated.emit()

@rpc("any_peer", "call_local", "reliable")
func set_player_ready(id: int, is_ready: bool) -> void:
	if players.has(id):
		players[id]["ready"] = is_ready
		lobby_updated.emit()

@rpc("any_peer", "call_local", "reliable")
func set_player_class(id: int, class_id: int) -> void:
	if players.has(id):
		players[id]["class_id"] = class_id
		lobby_updated.emit()

func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and int(ip.split(".")[1]) >= 16 and int(ip.split(".")[1]) <= 31):
			return ip
	return "127.0.0.1"
