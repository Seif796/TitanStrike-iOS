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
	NetworkManager.player_connected.connect(_on_player_connected_to_room)
	
	var um = get_node_or_null("/root/UpdateManager")
	if um:
		um.game_config_synced.connect(_on_game_config_synced)
	
	# Setup Game Mode Options
	if mode_option:
		mode_option.clear()
		mode_option.add_item("🤖 Squad Co-op vs Robots (تعاوني ضد الروبوتات)", 0)
		mode_option.add_item("⚔️ 1v1 PvP Duel (مبارزة 1 ضد 1)", 1)
		mode_option.select(int(GameManager.selected_game_mode))
		if multiplayer.is_server():
			mode_option.disabled = false
			mode_option.item_selected.connect(_on_mode_selected)
			var initial_mode = "⚔️ 1v1 PvP Duel" if GameManager.selected_game_mode == GameManager.GameMode.PVP_DUEL else "🤖 Squad Co-op vs Robots"
			NetworkManager.update_room_details(initial_mode, 1, "IN_LOBBY")
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
	_setup_hero_options_lobby()
	
	if start_btn:
		start_btn.pressed.connect(_on_start_pressed)
	if leave_btn:
		leave_btn.pressed.connect(_on_leave_pressed)
	
	var r_code = NetworkManager.current_room_code
	var all_ips = NetworkManager.get_all_local_ips()
	var visible_ips: Array[String] = []
	for ip in all_ips:
		if ip != "127.0.0.1" and not visible_ips.has(ip):
			visible_ips.append(ip)
	var ips_str = " / ".join(visible_ips) if not visible_ips.is_empty() else NetworkManager.get_local_ip()
	
	if multiplayer.is_server():
		room_title.text = "👑 SQUAD ROOM HOST (أنت صاحب الغرفة)"
		code_banner.text = "🔑 كود الغرفة: #%s (أعطِ هذا الكود لأصدقائك للانضمام فوراً!)" % r_code
		if start_btn:
			start_btn.visible = true
			start_btn.disabled = false
			start_btn.text = "🚀 START BATTLE (ابدأ المعركة)"
			start_btn.modulate = Color(0.2, 1.0, 0.5)
	else:
		room_title.text = "🎮 SQUAD ROOM - READY (تم الانضمام للغرفة بنجاح)"
		code_banner.text = "🔑 متصل بالغرفة #%s   |   📱 السيرفر: %s" % [r_code, ips_str]
		if start_btn:
			start_btn.visible = true
			start_btn.disabled = true
			start_btn.text = "⏳ WAITING FOR HOST (بانتظار الهوست لبدء المعركة)..."
			start_btn.modulate = Color(0.7, 0.75, 0.85)
	
	_update_lobby_ui()

func _setup_hero_options_lobby() -> void:
	if not hero_option:
		return
	hero_option.clear()
	for h_id in GameManager.CLASSES:
		var c = GameManager.CLASSES[h_id]
		if not GameManager.is_hero_enabled(h_id):
			hero_option.add_item("⛔ %s (معطل)" % c["name"], h_id)
		elif GameManager.is_hero_unlocked(h_id):
			hero_option.add_item(c["name"], h_id)
	
	var my_id = multiplayer.get_unique_id()
	var current_class = NetworkManager.local_class_id
	if NetworkManager.players.has(my_id):
		current_class = NetworkManager.players[my_id].get("class_id", current_class)
	
	# If currently selected class is disabled by admin, auto-switch to first enabled!
	if not GameManager.is_hero_enabled(current_class):
		var fallback_id = 0
		for id in GameManager.CLASSES:
			if GameManager.is_hero_enabled(id):
				fallback_id = id
				break
		current_class = fallback_id
		NetworkManager.local_class_id = fallback_id
		NetworkManager.rpc("update_player_class", my_id, fallback_id)
	
	for i in range(hero_option.item_count):
		if hero_option.get_item_id(i) == current_class:
			hero_option.select(i)
			break
	
	if not hero_option.item_selected.is_connected(_on_hero_item_selected):
		hero_option.item_selected.connect(_on_hero_item_selected)

func _on_hero_item_selected(idx: int) -> void:
	var new_class = hero_option.get_item_id(idx)
	if not GameManager.is_hero_enabled(new_class):
		AudioManager.play_sfx("error")
		_setup_hero_options_lobby()
		return
	NetworkManager.local_class_id = new_class
	NetworkManager.rpc("update_player_class", multiplayer.get_unique_id(), new_class)

func _on_game_config_synced(_cfg: Dictionary) -> void:
	_setup_hero_options_lobby()
	_update_lobby_ui()

func _on_mode_selected(index: int) -> void:
	GameManager.selected_game_mode = index as GameManager.GameMode
	if multiplayer.is_server():
		var m_title = "⚔️ 1v1 PvP Duel" if index == 1 else "🤖 Squad Co-op vs Robots"
		NetworkManager.update_room_details(m_title, NetworkManager.players.size(), "IN_LOBBY")
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
		var is_pvp = (GameManager.selected_game_mode == GameManager.GameMode.PVP_DUEL)
		var m_title = "⚔️ 1v1 PvP Duel (IN MATCH)" if is_pvp else "🤖 Squad Co-op (IN MATCH)"
		NetworkManager.update_room_details(m_title, NetworkManager.players.size(), "IN_BATTLE")
		GameManager.rpc("start_game_scene")

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_player_connected_to_room(peer_id: int, player_info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == 1:
		return
	
	var player_name = player_info.get("name", "لاعب جديد")
	_show_host_start_prompt(player_name)

func _show_host_start_prompt(player_name: String) -> void:
	AudioManager.play_sfx("redeem")
	
	var old_modal = get_node_or_null("HostStartPromptLayer")
	if old_modal:
		old_modal.queue_free()
		
	var canvas = CanvasLayer.new()
	canvas.name = "HostStartPromptLayer"
	canvas.layer = 150
	add_child(canvas)
	
	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.75)
	canvas.add_child(overlay)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(540, 260)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.18, 0.98)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.0, 0.9, 1.0)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_color = Color(0.0, 0.8, 1.0, 0.4)
	style.shadow_size = 25
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)
	
	var header_lbl = Label.new()
	header_lbl.text = "🎮 انضمام لاعب جديد إلى الروم!"
	header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_lbl.add_theme_font_size_override("font_size", 20)
	header_lbl.add_theme_color_override("font_color", Color(0.0, 0.95, 1.0))
	vbox.add_child(header_lbl)
	
	var desc_lbl = Label.new()
	desc_lbl.text = "اللاعب [%s] انضم إلى البارتي الآن!\nعايز تخش اللعبة دلوقتي ولا لسه مستني؟" % player_name
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 16)
	desc_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	vbox.add_child(desc_lbl)
	
	var btns_hbox = HBoxContainer.new()
	btns_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btns_hbox)
	
	# Button 1: ماشي (Start game)
	var ok_btn = Button.new()
	ok_btn.text = "✅ ماشي (ادخل اللعبة الآن)"
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_btn.custom_minimum_size = Vector2(0, 52)
	ok_btn.add_theme_font_size_override("font_size", 16)
	var ok_style = StyleBoxFlat.new()
	ok_style.bg_color = Color(0.12, 0.55, 0.3, 0.95)
	ok_style.border_width_left = 2
	ok_style.border_width_top = 2
	ok_style.border_width_right = 2
	ok_style.border_width_bottom = 2
	ok_style.border_color = Color(0.2, 1.0, 0.5)
	ok_style.corner_radius_top_left = 10
	ok_style.corner_radius_top_right = 10
	ok_style.corner_radius_bottom_left = 10
	ok_style.corner_radius_bottom_right = 10
	ok_btn.add_theme_stylebox_override("normal", ok_style)
	
	ok_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		canvas.queue_free()
		_on_start_pressed()
	)
	btns_hbox.add_child(ok_btn)
	
	# Button 2: لسه (Wait)
	var wait_btn = Button.new()
	wait_btn.text = "⏳ لسه (انتظار باقي اللاعبين)"
	wait_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wait_btn.custom_minimum_size = Vector2(0, 52)
	wait_btn.add_theme_font_size_override("font_size", 16)
	var wait_style = StyleBoxFlat.new()
	wait_style.bg_color = Color(0.18, 0.22, 0.32, 0.95)
	wait_style.border_width_left = 2
	wait_style.border_width_top = 2
	wait_style.border_width_right = 2
	wait_style.border_width_bottom = 2
	wait_style.border_color = Color(0.5, 0.7, 0.9)
	wait_style.corner_radius_top_left = 10
	wait_style.corner_radius_top_right = 10
	wait_style.corner_radius_bottom_left = 10
	wait_style.corner_radius_bottom_right = 10
	wait_btn.add_theme_stylebox_override("normal", wait_style)
	
	wait_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		canvas.queue_free()
	)
	btns_hbox.add_child(wait_btn)
