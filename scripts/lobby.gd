extends Control

# Lobby Script (res://scripts/lobby.gd)
# Features Room Code, Map Selection, squad list, and auto-launch countdown.

@onready var room_title: Label = $Panel/VBox/Title
@onready var code_banner: Label = $Panel/VBox/CodeBanner
@onready var map_option: OptionButton = $Panel/VBox/MapBox/MapOption
@onready var player_list_container: VBoxContainer = $Panel/VBox/PlayerList
@onready var countdown_label: Label = $Panel/VBox/CountdownLabel
@onready var start_btn: Button = $Panel/VBox/Actions/StartBtn
@onready var leave_btn: Button = $Panel/VBox/Actions/LeaveBtn

func _ready() -> void:
	NetworkManager.lobby_updated.connect(_update_lobby_ui)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.room_launch_countdown.connect(_on_launch_countdown)
	
	# Setup Map Options
	if map_option:
		map_option.clear()
		for m_id in GameManager.MAPS:
			map_option.add_item(GameManager.MAPS[m_id]["name"], m_id)
		map_option.select(GameManager.selected_map_id)
		map_option.item_selected.connect(_on_map_selected)
		if not multiplayer.is_server():
			map_option.disabled = true
	
	if start_btn:
		start_btn.pressed.connect(_on_start_pressed)
	if leave_btn:
		leave_btn.pressed.connect(_on_leave_pressed)
	
	if countdown_label:
		countdown_label.visible = false
	
	var r_code = NetworkManager.current_room_code
	if multiplayer.is_server():
		room_title.text = "ROOM CREATED - WAITING FOR SQUAD"
		code_banner.text = "🔑 ROOM CODE: #%s\n(Share this code with your friend to join!)" % r_code
		if start_btn:
			start_btn.visible = true
			start_btn.text = "🚀 Start Solo / Force"
	else:
		room_title.text = "JOINED SQUAD ROOM - READY"
		code_banner.text = "CONNECTED TO ROOM #%s" % r_code
		if start_btn:
			start_btn.visible = false
	
	_update_lobby_ui()

func _on_map_selected(index: int) -> void:
	GameManager.selected_map_id = index
	if multiplayer.is_server():
		rpc("_sync_map_selection", index)

@rpc("call_local", "reliable")
func _sync_map_selection(map_id: int) -> void:
	GameManager.selected_map_id = map_id
	if map_option:
		map_option.selected = map_id

func _update_lobby_ui() -> void:
	for child in player_list_container.get_children():
		child.queue_free()
	
	for peer_id in NetworkManager.players:
		var p = NetworkManager.players[peer_id]
		var c_data = GameManager.CLASSES.get(p.get("class_id", 0), GameManager.CLASSES[0])
		var label = Label.new()
		var is_host = (peer_id == 1)
		var role_tag = " [ROOM HOST]" if is_host else " [SQUAD AGENT]"
		label.text = "• %s - Hero: %s %s" % [p.get("name", "Player"), c_data["name"], role_tag]
		label.add_theme_color_override("font_color", c_data["color"])
		label.add_theme_font_size_override("font_size", 18)
		player_list_container.add_child(label)
	
	if NetworkManager.players.size() <= 1 and GameManager.bot_enabled:
		var bot_c = GameManager.CLASSES.get(GameManager.bot_class_id, GameManager.CLASSES[1])
		var bot_label = Label.new()
		bot_label.text = "• 🤖 AI Companion [SQUAD BOT] - Hero: %s" % bot_c["name"]
		bot_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
		bot_label.add_theme_font_size_override("font_size", 18)
		player_list_container.add_child(bot_label)

func _on_launch_countdown(sec: int) -> void:
	if countdown_label:
		countdown_label.visible = true
		countdown_label.text = "⚡ PLAYER JOINED! LAUNCHING IN %d..." % sec
		countdown_label.modulate = Color.GREEN

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		GameManager.rpc("start_game_scene")

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
