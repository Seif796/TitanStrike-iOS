extends Node

# GameManager Autoload (res://scripts/game_manager.gd)
# Controls match flow, waves, map selection, fruit hero classes + unlockable Admin class,
# progression saving, 1-chance retry system, and forces landscape orientation.

enum GameState {
	MENU,
	LOBBY,
	WAVE_COMBAT,
	BOSS_FIGHT,
	VICTORY,
	DEFEAT
}

enum GameMode {
	COOP_WAVES, # 0: Squad Co-op vs Robots & Titans
	PVP_DUEL,   # 1: 1v1 PvP Duel (Player vs Player)
	TRAINING    # 2: Solo Training Grounds
}

const GAME_MODES: Dictionary = {
	GameMode.COOP_WAVES: {
		"name": "🤖 Squad Co-op (تعاوني ضد الروبوتات)",
		"desc": "Team up with your squad to battle 5 waves of robots and eliminate the Titans! Features Revive Station and Bot companion."
	},
	GameMode.PVP_DUEL: {
		"name": "⚔️ 1v1 PvP Duel (مبارزة 1 ضد 1)",
		"desc": "Duel against your friend! No robots, pure combat skills. First to eliminate the other wins!"
	},
	GameMode.TRAINING: {
		"name": "🎯 Training Grounds (طور التدريب والتمارين)",
		"desc": "Solo practice with a Training Dummy, infinite ammo, and damage meters to master all heroes!"
	}
}

var selected_game_mode: GameMode = GameMode.COOP_WAVES
@warning_ignore("unused_signal")
signal game_mode_changed(new_mode: GameMode)

signal state_changed(new_state: GameState)
@warning_ignore("unused_signal")
signal boss_health_updated(current_hp: float, max_hp: float, boss_name: String)
@warning_ignore("unused_signal")
signal wave_updated(current_wave: int, max_waves: int, enemies_left: int)
signal game_over_triggered(is_victory: bool)
signal retry_stage_requested()
signal admin_newly_unlocked()

var current_state: GameState = GameState.MENU
var current_wave: int = 1
var max_waves: int = 3
var enemies_remaining: int = 0
var boss_node: Node = null

# Map selection: 0: Fruit Kingdom Arena, 1: Cyber Stadium, 2: Desert Canyon
var selected_map_id: int = 0

# AI Bot Companion configuration for Solo Play
var bot_enabled: bool = false  # Default OFF — player must choose to enable bot
var bot_class_id: int = 1 # Default: Berry Striker 🍓

# Progression & Retry system (Melon -> Berry -> Citrus -> Admin)
const SAVE_PATH = "user://game_save.cfg"
var berry_unlocked: bool = false
var citrus_unlocked: bool = false
var admin_unlocked: bool = false
var berry_just_unlocked: bool = false
var citrus_just_unlocked: bool = false
var admin_just_unlocked: bool = false
var has_used_retry: bool = false

const MAPS: Dictionary = {
	0: { "name": "🍉 Fruit Kingdom Arena (مملكة الفواكه الخضراء)", "theme_color": Color(0.2, 0.8, 0.3) },
	1: { "name": "⚡ Cyber Stadium (ساحة السايبر المستقبلية)", "theme_color": Color(0.1, 0.6, 1.0) },
	2: { "name": "🏜️ Desert Titan Canyon (وادي العمالقة الصحراوي)", "theme_color": Color(0.9, 0.6, 0.2) },
	3: { "name": "🌋 Volcanic Magma Core (قلب البركان المشتعل)", "theme_color": Color(1.0, 0.2, 0.05) },
	4: { "name": "❄️ Frozen Ice Glacier (جليد القطب المتجمد)", "theme_color": Color(0.3, 0.85, 1.0) },
	5: { "name": "🌌 Cosmic Galaxy Station (محطة المجرة الفضائية)", "theme_color": Color(0.65, 0.2, 0.95) },
	6: { "name": "🏰 Neon Castle Citadel (قلعة النيون المظلمة)", "theme_color": Color(0.85, 0.15, 0.55) }
}

signal classes_updated()
signal server_announcement_received(message: String)

# Hero Classes (including unlockable 500 HP Admin)
var CLASSES: Dictionary = {
	0: {
		"name": "🍉 Melon Knight (فارس البطيخ الجديد)",
		"hp": 130,
		"speed": 7.5,
		"role": "The newly upgraded hero! Fully animated emerald watermelon warrior with ruby cyber-core, fires rapid seeds and builds sturdy walls.",
		"color": Color(0.25, 0.8, 0.2), # Melon Green
		"enabled": true
	},
	1: {
		"name": "🍓 Berry Striker (بطلة الفراولة)",
		"hp": 100,
		"speed": 8.5,
		"role": "Super fast berry ranger with high critical seed shots and tactical speed ramps.",
		"color": Color(0.9, 0.15, 0.25), # Strawberry Red
		"enabled": true
	},
	2: {
		"name": "🍊 Citrus Tank (البرتقال المدرّع)",
		"hp": 240,
		"speed": 5.6,
		"role": "Heavy armored citrus juggernaut with explosive melon cannons and auto-turrets.",
		"color": Color(1.0, 0.5, 0.05), # Citrus Orange
		"enabled": true
	},
	3: {
		"name": "👑 Admin (الأدمن الخارق)",
		"hp": 500,
		"speed": 15,
		"role": "Legendary secret hero! Unlocked by beating all 3 waves and both Big Bosses. Has 500 HP and golden armor.",
		"color": Color(1.0, 0.85, 0.1), # Golden Cyber Admin
		"enabled": true
	},
	4: {
		"name": "🕷️ Spider Hero (سبايدر هودي الخارق)",
		"hp": 220,
		"speed": 9.2,
		"role": "The newly added 3D Chibi Spider-Hero! Wearing an oversized hoodie, denim cutoffs, and retro high-top sneakers. Highly agile with web attacks!",
		"color": Color(0.95, 0.2, 0.25), # Spider Red
		"enabled": true
	}
}

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	load_save_data()

func load_save_data() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		berry_unlocked = config.get_value("progression", "berry_unlocked", false)
		citrus_unlocked = config.get_value("progression", "citrus_unlocked", false)
		admin_unlocked = config.get_value("progression", "admin_unlocked", false)
	else:
		berry_unlocked = false
		citrus_unlocked = false
		admin_unlocked = false

func is_hero_enabled(hero_id: int) -> bool:
	if not CLASSES.has(hero_id):
		return false
	return CLASSES[hero_id].get("enabled", true)

func apply_server_config(cfg: Dictionary) -> void:
	if cfg.has("heroes") and typeof(cfg["heroes"]) == TYPE_DICTIONARY:
		for id_str in cfg["heroes"]:
			var id = int(id_str)
			if CLASSES.has(id):
				var h = cfg["heroes"][id_str]
				if h.has("name"): CLASSES[id]["name"] = h["name"]
				if h.has("hp"): CLASSES[id]["hp"] = int(h["hp"])
				if h.has("speed"): CLASSES[id]["speed"] = float(h["speed"])
				if h.has("role"): CLASSES[id]["role"] = h["role"]
				if h.has("enabled"): CLASSES[id]["enabled"] = bool(h["enabled"])
		classes_updated.emit()
	
	if cfg.has("server_announcement") and not str(cfg["server_announcement"]).is_empty():
		server_announcement_received.emit(str(cfg["server_announcement"]))

func is_hero_unlocked(hero_id: int) -> bool:
	match hero_id:
		0: return true # Melon Boy is unlocked from the beginning
		1: return berry_unlocked
		2: return citrus_unlocked
		3: return admin_unlocked
		4: return true # Spider Hero unlocked & ready to play!
		_: return false

func unlock_hero(hero_id: int) -> bool:
	var newly_unlocked = false
	match hero_id:
		1:
			if not berry_unlocked:
				berry_unlocked = true
				berry_just_unlocked = true
				newly_unlocked = true
		2:
			if not citrus_unlocked:
				citrus_unlocked = true
				citrus_just_unlocked = true
				newly_unlocked = true
		3:
			if not admin_unlocked:
				admin_unlocked = true
				admin_just_unlocked = true
				newly_unlocked = true
				admin_newly_unlocked.emit()
	if newly_unlocked:
		save_progression()
	return newly_unlocked

func save_progression() -> void:
	var config = ConfigFile.new()
	config.set_value("progression", "berry_unlocked", berry_unlocked)
	config.set_value("progression", "citrus_unlocked", citrus_unlocked)
	config.set_value("progression", "admin_unlocked", admin_unlocked)
	config.save(SAVE_PATH)

func save_admin_unlocked() -> void:
	unlock_hero(3)

@rpc("call_local", "reliable")
func start_game_scene() -> void:
	current_state = GameState.WAVE_COMBAT
	current_wave = 1
	max_waves = 5
	has_used_retry = false # Reset retry chance for the new match
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

func start_training_mode(hero_id: int = 0) -> void:
	selected_game_mode = GameMode.TRAINING
	NetworkManager.leave_game()
	NetworkManager.local_player_name = "Trainee"
	NetworkManager.local_class_id = hero_id
	current_state = GameState.WAVE_COMBAT
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

@rpc("call_local", "reliable")
func return_to_lobby_together() -> void:
	current_state = GameState.LOBBY
	current_wave = 1
	has_used_retry = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

@rpc("any_peer", "reliable")
func request_return_to_lobby() -> void:
	if multiplayer.is_server():
		rpc("return_to_lobby_together")

@rpc("call_local", "reliable")
func set_state(new_state: int) -> void:
	current_state = new_state as GameState
	state_changed.emit(current_state)

@rpc("call_local", "reliable")
func trigger_game_over(is_victory: bool) -> void:
	if current_state == GameState.VICTORY or current_state == GameState.DEFEAT:
		return
	
	current_state = GameState.VICTORY if is_victory else GameState.DEFEAT
	if is_victory:
		var was_already_unlocked = admin_unlocked
		admin_just_unlocked = not was_already_unlocked
		save_admin_unlocked()
		if not was_already_unlocked:
			admin_newly_unlocked.emit()
	game_over_triggered.emit(is_victory)

@rpc("any_peer", "call_local", "reliable")
func request_retry_stage() -> void:
	if has_used_retry:
		return
	has_used_retry = true
	current_state = GameState.WAVE_COMBAT if current_wave <= max_waves else GameState.BOSS_FIGHT
	retry_stage_requested.emit()

func check_all_players_down() -> void:
	if selected_game_mode == GameMode.TRAINING:
		return
	
	if not multiplayer.is_server():
		return
	
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	
	if selected_game_mode == GameMode.PVP_DUEL:
		# In 1v1 PvP, if any player is downed, the other player wins!
		var alive_players = []
		var dead_players = []
		for p in players:
			if p.has_method("is_downed") and p.is_downed():
				dead_players.append(p)
			else:
				alive_players.append(p)
		
		if not dead_players.is_empty():
			# Duel ended! Alive player gets Victory, Dead player gets Defeat
			for dp in dead_players:
				dp.rpc("notify_pvp_result", false)
			for ap in alive_players:
				ap.rpc("notify_pvp_result", true)
		return
	
	var any_alive = false
	for p in players:
	if players.is_empty():
		return
	
	var any_alive = false
	for p in players:
		if p.has_method("is_downed") and not p.is_downed():
			any_alive = true
			break
	
	if not any_alive:
		rpc("trigger_game_over", false)
