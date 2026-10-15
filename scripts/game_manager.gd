extends Node

# GameManager Autoload (res://scripts/game_manager.gd)
# Controls match flow, waves, boss activation, revive checks, and game win/lose states.

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

# Class definitions
const CLASSES: Dictionary = {
	0: {
		"name": "Assault (المقتحم)",
		"hp": 120,
		"speed": 6.5,
		"role": "Balanced combat specialist with high sustained DPS.",
		"color": Color(0.2, 0.6, 1.0) # Blue
	},
	1: {
		"name": "Heavy (المدرّع)",
		"hp": 200,
		"speed": 5.0,
		"role": "Armored tank with explosive firepower and high survivability.",
		"color": Color(0.9, 0.4, 0.1) # Orange
	},
	2: {
		"name": "Scout (القناص)",
		"hp": 90,
		"speed": 8.0,
		"role": "Agile sniper with deadly critical shots and evasion.",
		"color": Color(0.2, 0.9, 0.4) # Green
	}
}

func _ready() -> void:
	pass

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

