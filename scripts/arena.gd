extends Node3D

# Arena Script (res://scripts/arena.gd)
# Manages player spawning, building system hooks, wave progression, and boss battle.

@onready var players_container: Node3D = $Players
@onready var enemies_container: Node3D = $Enemies
@onready var spawn_points: Node3D = $SpawnPoints
@onready var boss_spawn_marker: Marker3D = $BossSpawn
@onready var hud: HUD = $HUD
@onready var touch_controls: TouchControls = $TouchControls

var player_scene = preload("res://scenes/player.tscn")
var minion_scene = preload("res://scenes/minion.tscn")
var boss_scene = preload("res://scenes/boss.tscn")

var local_player: Player = null

func _ready() -> void:
	_spawn_players()
	
	if multiplayer.is_server():
		get_tree().create_timer(2.0).timeout.connect(_start_next_wave)

func _spawn_players() -> void:
	var spawn_nodes = spawn_points.get_children()
	var spawn_index = 0
	
	if NetworkManager.players.is_empty():
		var p = player_scene.instantiate()
		p.name = "1"
		p.peer_id = 1
		p.class_id = NetworkManager.local_class_id
		p.global_position = spawn_nodes[0].global_position
		players_container.add_child(p)
		_setup_local_player(p)
		return
	
	for peer_id in NetworkManager.players:
		var p_info = NetworkManager.players[peer_id]
		var p = player_scene.instantiate()
		p.name = str(peer_id)
		p.peer_id = peer_id
		p.class_id = p_info.get("class_id", 0)
		
		var spawn_pos = Vector3.ZERO
		if spawn_index < spawn_nodes.size():
			spawn_pos = spawn_nodes[spawn_index].global_position
			spawn_index += 1
		
		p.global_position = spawn_pos
		players_container.add_child(p)
		
		if peer_id == multiplayer.get_unique_id():
			_setup_local_player(p)

func _setup_local_player(p: Player) -> void:
	local_player = p
	if touch_controls:
		touch_controls.bind_player(p)
	
	if hud:
		p.health_changed.connect(hud.update_health)
		p.downed_state_changed.connect(hud.show_downed_alert)
		
		if p.building_system:
			p.building_system.materials_changed.connect(hud.update_materials)
			hud.update_materials(p.building_system.materials)
		
		p.weapon_switched.connect(func(w: Weapon):
			hud.update_weapon_info(w.weapon_name)
			w.ammo_changed.connect(hud.update_ammo)
			hud.update_ammo(w.current_ammo, w.max_ammo, w.is_reloading)
		)
		if p.active_weapon:
			hud.update_weapon_info(p.active_weapon.weapon_name)
			p.active_weapon.ammo_changed.connect(hud.update_ammo)
			hud.update_ammo(p.active_weapon.current_ammo, p.active_weapon.max_ammo, p.active_weapon.is_reloading)
		
		hud.update_health(p.current_hp, p.max_hp)

# --- WAVE SYSTEM ---

func _start_next_wave() -> void:
	if not multiplayer.is_server():
		return
	
	if GameManager.current_wave <= GameManager.max_waves:
		var enemy_count = 6 + (GameManager.current_wave * 4)
		GameManager.enemies_remaining = enemy_count
		GameManager.wave_updated.emit(GameManager.current_wave, GameManager.max_waves, enemy_count)
		rpc("_sync_wave_info", GameManager.current_wave, GameManager.max_waves, enemy_count)
		
		for i in range(enemy_count):
			get_tree().create_timer(i * 1.4).timeout.connect(func():
				_spawn_minion()
			)
		
		_monitor_wave_clear()
	else:
		_start_boss_battle()

func _monitor_wave_clear() -> void:
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if GameManager.enemies_remaining <= 0:
			# Reward surviving squad with nano-materials for building!
			_reward_materials_all(60)
			GameManager.current_wave += 1
			get_tree().create_timer(3.0).timeout.connect(_start_next_wave)
		else:
			_monitor_wave_clear()
	)

func _reward_materials_all(amount: int) -> void:
	rpc("_sync_reward_materials", amount)

@rpc("call_local", "reliable")
func _sync_reward_materials(amount: int) -> void:
	if local_player and local_player.building_system:
		local_player.building_system.materials += amount
		local_player.building_system.materials_changed.emit(local_player.building_system.materials)

func _spawn_minion() -> void:
	if not multiplayer.is_server():
		return
	var minion = minion_scene.instantiate()
	var spawn_nodes = spawn_points.get_children()
	var rand_spawn = spawn_nodes.pick_random()
	var offset = Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	minion.global_position = rand_spawn.global_position + offset
	enemies_container.add_child(minion, true)

func _start_boss_battle() -> void:
	GameManager.current_state = GameManager.GameState.BOSS_FIGHT
	GameManager.wave_updated.emit(GameManager.max_waves + 1, GameManager.max_waves, 1)
	rpc("_sync_wave_info", GameManager.max_waves + 1, GameManager.max_waves, 1)
	
	var boss = boss_scene.instantiate()
	boss.global_position = boss_spawn_marker.global_position if boss_spawn_marker else Vector3(0, 0, -22)
	enemies_container.add_child(boss, true)

@rpc("call_local", "reliable")
func _sync_wave_info(w: int, max_w: int, left: int) -> void:
	GameManager.wave_updated.emit(w, max_w, left)
