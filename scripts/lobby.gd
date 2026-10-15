extends Control

# Lobby Script (res://scripts/lobby.gd)
# Room Lobby displaying members, Room IP, and automatic launch countdown when squad connects.

@onready var room_title: Label = $Panel/VBox/Title
@onready var ip_info_label: Label = $Panel/VBox/IPInfoLabel
@onready var player_list_container: VBoxContainer = $Panel/VBox/PlayerList
@onready var countdown_label: Label = $Panel/VBox/CountdownLabel
@onready var start_btn: Button = $Panel/VBox/Actions/StartBtn
@onready var leave_btn: Button = $Panel/VBox/Actions/LeaveBtn

func _ready() -> void:
	NetworkManager.lobby_updated.connect(_update_lobby_ui)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.room_launch_countdown.connect(_on_launch_countdown)
	
	if start_btn:
		start_btn.pressed.connect(_on_start_pressed)
	if leave_btn:
		leave_btn.pressed.connect(_on_leave_pressed)
	
	if countdown_label:
		countdown_label.visible = false
	
	if multiplayer.is_server():
		room_title.text = "ROOM CREATED - WAITING FOR SQUAD (في انتظار اللاعبين)"
		ip_info_label.text = "Room Host IP: %s (Share with friends to Join)" % NetworkManager.get_local_ip()
		if start_btn:
			start_btn.visible = true
			start_btn.text = "🚀 Start Solo / Now"
	else:
		room_title.text = "JOINED SQUAD ROOM - READY"
		ip_info_label.text = "Connected to Room Host"
		if start_btn:
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
		var role_tag = " [ROOM HOST]" if is_host else " [SQUAD AGENT]"
		label.text = "• %s - Class: %s %s" % [p.get("name", "Player"), c_data["name"], role_tag]
		label.add_theme_color_override("font_color", c_data["color"])
		label.add_theme_font_size_override("font_size", 17)
		player_list_container.add_child(label)

func _on_launch_countdown(sec: int) -> void:
	if countdown_label:
		countdown_label.visible = true
		countdown_label.text = "⚡ SQUAD READY! LAUNCHING MISSION IN %d..." % sec
		countdown_label.modulate = Color.GREEN

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		GameManager.rpc("start_game_scene")

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
