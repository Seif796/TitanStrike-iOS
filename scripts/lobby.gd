extends Control

# Lobby Script (res://scripts/lobby.gd)
# Features Room Code, Bluetooth/Hotspot Host IP display, in-lobby Map Selection synchronized to all peers,
# in-lobby Hero Switching, squad member status, and manual Host launch.

@onready var room_title: Label = $Panel/VBox/Title
@onready var code_banner: Label = $Panel/VBox/CodeBanner
@onready var mode_option: OptionButton = $Panel/VBox/ModeBox/ModeOption
@onready var map_option: OptionButton = $Panel/VBox/MapBox/MapOption
@onready var map_banner_title: Label = $Panel/VBox/MapBanner/BannerVBox/SelectedMapTitle
@onready var map_banner_notice: Label = $Panel/VBox/MapBanner/BannerVBox/MapNotice
@onready var hero_option: OptionButton = $Panel/VBox/HeroBox/HeroOption
@onready var player_list_container: VBoxContainer = $Panel/VBox/PlayerList
@onready var start_btn: Button = $Panel/VBox/Actions/StartBtn
@onready var leave_btn: Button = $Panel/VBox/Actions/LeaveBtn

func _ready() -> void:
	NetworkManager.lobby_updated.connect(_update_lobby_ui)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	# Setup Game Mode Options
	if mode_option:
		mode_option.clear()
		mode_option.add_item("🤖 Squad Co-op vs Robots (تعاوني ضد الروبوتات)", 0)
		mode_option.add_item("⚔️ 1v1 PvP Duel (مبارزة 1 ضد 1)", 1)
		mode_option.select(int(GameManager.selected_game_mode))
		if multiplayer.is_server():
			mode_option.disabled = false
			mode_option.item_selected.connect(_on_mode_selected)
		else:
			mode_option.disabled = true
	
	# Setup Map Options
	if map_option:
		map_option.clear()
		for m_id in GameManager.MAPS:
			map_option.add_item(GameManager.MAPS[m_id]["name"], m_id)
		map_option.select(GameManager.selected_map_id)
		map_option.item_selected.connect(_on_map_selected)
		if not multiplayer.is_server():
			map_option.disabled = true
	
	_update_map_banner(GameManager.selected_map_id)
	
	# Setup In-Lobby Hero Switcher
	if hero_option:
		hero_option.clear()
		for h_id in GameManager.CLASSES:
			var c = GameManager.CLASSES[h_id]
			if GameManager.is_hero_unlocked(h_id):
				hero_option.add_item(c["name"], h_id)
		
		var my_id = multiplayer.get_unique_id()
		var current_class = NetworkManager.local_class_id
		if NetworkManager.players.has(my_id):
			current_class = NetworkManager.players[my_id].get("class_id", current_class)
		
		for i in range(hero_option.item_count):
			if hero_option.get_item_id(i) == current_class:
				hero_option.select(i)
				break
		
		hero_option.item_selected.connect(func(idx: int):
			var new_class = hero_option.get_item_id(idx)
			NetworkManager.local_class_id = new_class
			NetworkManager.rpc("update_player_class", multiplayer.get_unique_id(), new_class)
		)
	
	if start_btn:
		start_btn.pressed.connect(_on_start_pressed)
	if leave_btn:
		leave_btn.pressed.connect(_on_leave_pressed)
	
	var r_code = NetworkManager.current_room_code
	var host_ip = NetworkManager.get_local_ip()
	if multiplayer.is_server():
		room_title.text = "👑 SQUAD ROOM HOST (أنت صاحب الغرفة)"
		code_banner.text = "🔑 ROOM CODE: #%s   |   📱 Direct IP: %s (يمكن كتابة هذا الرقم مباشرة)" % [r_code, host_ip]
		if start_btn:
			start_btn.visible = true
			start_btn.disabled = false
			start_btn.text = "🚀 START BATTLE (ابدأ المعركة)"
			start_btn.modulate = Color(0.2, 1.0, 0.5)
	else:
		room_title.text = "🎮 SQUAD ROOM - READY (تم الانضمام للغرفة بنجاح)"
		code_banner.text = "🔑 متصل بالغرفة #%s   |   📱 Host IP: %s" % [r_code, host_ip]
		if start_btn:
			start_btn.visible = true
			start_btn.disabled = true
			start_btn.text = "⏳ WAITING FOR HOST (بانتظار الهوست لبدء المعركة)..."
			start_btn.modulate = Color(0.7, 0.75, 0.85)
	
	_update_lobby_ui()

func _on_mode_selected(index: int) -> void:
	GameManager.selected_game_mode = index as GameManager.GameMode
	if multiplayer.is_server():
		rpc("_sync_game_mode", index)

@rpc("call_local", "reliable")
func _sync_game_mode(mode_id: int) -> void:
	GameManager.selected_game_mode = mode_id as GameManager.GameMode
	if mode_option:
		mode_option.selected = mode_id
	_update_lobby_ui()

func _on_map_selected(index: int) -> void:
	GameManager.selected_map_id = index
	_update_map_banner(index)
	if multiplayer.is_server():
		rpc("_sync_map_selection", index)

@rpc("call_local", "reliable")
func _sync_map_selection(map_id: int) -> void:
	GameManager.selected_map_id = map_id
	if map_option:
		map_option.selected = map_id
	_update_map_banner(map_id)

func _update_map_banner(map_id: int) -> void:
	var m_data = GameManager.MAPS.get(map_id, GameManager.MAPS[0])
	if map_banner_title:
		map_banner_title.text = "🗺️ BATTLEFIELD: %s" % m_data["name"]
		map_banner_title.modulate = m_data.get("theme_color", Color(0.2, 1, 0.5))
	
	if map_banner_notice:
		if multiplayer.is_server():
			map_banner_notice.text = "🎯 You are the Host. Choose any battlefield above for your squad!"
			map_banner_notice.modulate = Color(0.9, 0.95, 1.0)
		else:
			map_banner_notice.text = "🎯 Selected by Host! All squad members will enter this map together."
			map_banner_notice.modulate = Color(0.3, 1.0, 0.6)

func _update_lobby_ui() -> void:
	for child in player_list_container.get_children():
		child.queue_free()
	
	var is_pvp = (GameManager.selected_game_mode == GameManager.GameMode.PVP_DUEL)
	for peer_id in NetworkManager.players:
		var p = NetworkManager.players[peer_id]
		var c_data = GameManager.CLASSES.get(p.get("class_id", 0), GameManager.CLASSES[0])
		var label = Label.new()
		var is_host = (peer_id == 1)
		var role_tag = " [👑 ROOM HOST]" if is_host else " [⚡ SQUAD AGENT]"
		if is_pvp:
			role_tag = " [⚔️ DUELIST 1 - HOST]" if is_host else " [⚔️ DUELIST 2 - CHALLENGER]"
		label.text = "• %s - Hero: %s %s" % [p.get("name", "Player"), c_data["name"], role_tag]
		label.add_theme_color_override("font_color", c_data["color"])
		label.add_theme_font_size_override("font_size", 18)
		player_list_container.add_child(label)
	
	if not is_pvp and NetworkManager.players.size() <= 1 and GameManager.bot_enabled:
		var bot_c = GameManager.CLASSES.get(GameManager.bot_class_id, GameManager.CLASSES[1])
		var bot_label = Label.new()
		bot_label.text = "• 🤖 AI Companion [SQUAD BOT] - Hero: %s" % bot_c["name"]
		bot_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
		bot_label.add_theme_font_size_override("font_size", 18)
		player_list_container.add_child(bot_label)

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		GameManager.rpc("start_game_scene")

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
