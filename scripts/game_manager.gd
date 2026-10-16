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

signal state_changed(new_state: GameState)
signal boss_health_updated(current_hp: float, max_hp: float, boss_name: String)
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

# Progression & Retry system
const SAVE_PATH = "user://game_save.cfg"
var admin_unlocked: bool = true
var admin_just_unlocked: bool = false
var has_used_retry: bool = false

const MAPS: Dictionary = {
	0: { "name": "🍉 Fruit Kingdom Arena (مملكة الفواكه)", "theme_color": Color(0.2, 0.8, 0.3) },
	1: { "name": "⚡ Cyber Stadium (ساحة السايبر)", "theme_color": Color(0.1, 0.6, 1.0) },
	2: { "name": "🏜️ Desert Titan Canyon (وادي العمالقة)", "theme_color": Color(0.9, 0.6, 0.2) }
}

# Hero Classes (including unlockable 500 HP Admin)
const CLASSES: Dictionary = {
	0: {
		"name": "🍉 Melon Boy (ولد البطيخ)",
		"hp": 130,
		"speed": 7.5,
		"role": "The main hero! Agile, fires rapid watermelon seeds, and builds sturdy fruit defense walls.",
		"color": Color(0.25, 0.8, 0.2) # Melon Green
	},
	1: {
		"name": "🍓 Berry Striker (بطلة الفراولة)",
		"hp": 100,
		"speed": 8.5,
		"role": "Super fast berry ranger with high critical seed shots and tactical speed ramps.",
		"color": Color(0.9, 0.15, 0.25) # Strawberry Red
	},
	2: {
		"name": "🍊 Citrus Tank (البرتقال المدرّع)",
		"hp": 240,
		"speed": 5.6,
		"role": "Heavy armored citrus juggernaut with explosive melon cannons and auto-turrets.",
		"color": Color(1.0, 0.5, 0.05) # Citrus Orange
	},
	3: {
		"name": "👑 Admin (الأدمن الخارق)",
		"hp": 500,
		"speed": 15,
		"role": "Legendary secret hero! Unlocked by beating all 3 waves and both Big Bosses. Has 500 HP and golden armor.",
		"color": Color(1.0, 0.85, 0.1) # Golden Cyber Admin
	}
}

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	load_save_data()

func load_save_data() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		admin_unlocked = config.get_value("progression", "admin_unlocked", true)
	else:
		admin_unlocked = true

func save_admin_unlocked() -> void:
	admin_unlocked = true
	var config = ConfigFile.new()
	config.set_value("progression", "admin_unlocked", true)
	config.save(SAVE_PATH)

@rpc("call_local", "reliable")
func start_game_scene() -> void:
	current_state = GameState.WAVE_COMBAT
	current_wave = 1
	max_waves = 3
	has_used_retry = false # Reset retry chance for the new match
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

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
	if not multiplayer.is_server():
		return
	
	var players = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	
	var any_alive = false
	for p in players:
		if p.has_method("is_downed") and not p.is_downed():
			any_alive = true
			break
	
	if not any_alive:
		rpc("trigger_game_over", false)
