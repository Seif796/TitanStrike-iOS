extends Node

# GameManager Autoload (res://scripts/game_manager.gd)
# Controls match flow, waves, map selection, fruit hero classes, and forces landscape orientation.

enum GameState {
	MENU,
	LOBBY,
	WAVE_COMBAT,
	BOSS_FIGHT,
	VICTORY,
	DEFEAT
}

signal state_changed(new_state: GameState)
signal boss_health_updated(current_hp: float, max_hp: float)
signal wave_updated(current_wave: int, max_waves: int, enemies_left: int)
signal game_over_triggered(is_victory: bool)

var current_state: GameState = GameState.MENU
var current_wave: int = 1
var max_waves: int = 3
var enemies_remaining: int = 0
var boss_node: Node = null

# Map selection: 0: Fruit Kingdom Arena, 1: Cyber Stadium, 2: Desert Canyon
var selected_map_id: int = 0

const MAPS: Dictionary = {
	0: { "name": "🍉 Fruit Kingdom Arena (مملكة الفواكه)", "theme_color": Color(0.2, 0.8, 0.3) },
	1: { "name": "⚡ Cyber Stadium (ساحة السايبر)", "theme_color": Color(0.1, 0.6, 1.0) },
	2: { "name": "🏜️ Desert Titan Canyon (وادي العمالقة)", "theme_color": Color(0.9, 0.6, 0.2) }
}

# Fruit Heroes Class definitions
const CLASSES: Dictionary = {
	0: {
		"name": "🍉 Melon Boy (ولد البطيخ)",
		"hp": 130,
		"speed": 7.2,
		"role": "The main hero! Agile, fires rapid watermelon seeds, and builds sturdy fruit defense walls.",
		"color": Color(0.25, 0.8, 0.2) # Melon Green
	},
	1: {
		"name": "🍓 Berry Striker (بطلة الفراولة)",
		"hp": 100,
		"speed": 8.2,
		"role": "Super fast berry ranger with high critical seed shots and tactical speed ramps.",
		"color": Color(0.9, 0.15, 0.25) # Strawberry Red
	},
	2: {
		"name": "🍊 Citrus Tank (البرتقال المدرّع)",
		"hp": 240,
		"speed": 5.4,
		"role": "Heavy armored citrus juggernaut with explosive melon cannons and auto-turrets.",
		"color": Color(1.0, 0.5, 0.05) # Citrus Orange
	}
}

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)

@rpc("call_local", "reliable")
func start_game_scene() -> void:
	current_state = GameState.WAVE_COMBAT
	current_wave = 1
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
	game_over_triggered.emit(is_victory)

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
