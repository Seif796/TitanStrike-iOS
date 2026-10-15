extends Control

# Lobby Script (res://scripts/lobby.gd)
# Shows connected squad members, IP info, ready status, and allows host to start campaign.

@onready var ip_info_label: Label = $Panel/VBox/IPInfoLabel
@onready var player_list_container: VBoxContainer = $Panel/VBox/PlayerList
@onready var ready_btn: Button = $Panel/VBox/Actions/ReadyBtn
@onready var start_btn: Button = $Panel/VBox/Actions/StartBtn
@onready var leave_btn: Button = $Panel/VBox/Actions/LeaveBtn

var is_ready: bool = false

func _ready() -> void:
	NetworkManager.lobby_updated.connect(_update_lobby_ui)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	ready_btn.pressed.connect(_on_ready_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)
	
	if multiplayer.is_server():
		ip_info_label.text = "Host IP: %s (Share with friends on same Wi-Fi)" % NetworkManager.get_local_ip()
		ready_btn.visible = false
		start_btn.visible = true
	else:
		ip_info_label.text = "Connected to Squad Host"
		ready_btn.visible = true
		start_btn.visible = false
	
	_update_lobby_ui()

func _update_lobby_ui() -> void:
	for child in player_list_container.get_children():
		child.queue_free()
	
	for peer_id in NetworkManager.players:
		var p = NetworkManager.players[peer_id]
		var c_data = GameManager.CLASSES.get(p.get("class_id", 0), GameManager.CLASSES[0])
		var label = Label.new()
		var is_host = (peer_id == 1)
		var ready_text = " [HOST]" if is_host else (" [READY]" if p.get("ready", false) else " [NOT READY]")
		label.text = "• %s - Class: %s %s" % [p.get("name", "Player"), c_data["name"], ready_text]
		label.add_theme_color_override("font_color", c_data["color"])
		player_list_container.add_child(label)

func _on_ready_pressed() -> void:
	is_ready = !is_ready
	ready_btn.text = "Cancel Ready" if is_ready else "Ready"
	var local_id = multiplayer.get_unique_id()
	NetworkManager.rpc("set_player_ready", local_id, is_ready)

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		GameManager.rpc("start_game_scene")

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
