extends Node3D

# Arena Script (res://scripts/arena.gd)
# Features 3 Selectable Maps (Fruit Kingdom, Cyber Stadium, Desert Canyon),
# dynamic environment styling, wave progression, and boss battle.

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var floor_mesh: CSGBox3D = $Map/Floor
@onready var wall_north: CSGBox3D = $Map/WallNorth
@onready var wall_south: CSGBox3D = $Map/WallSouth
@onready var wall_east: CSGBox3D = $Map/WallEast
@onready var wall_west: CSGBox3D = $Map/WallWest

@onready var pillar1: CSGBox3D = $Map/CoverPillar1
@onready var pillar2: CSGBox3D = $Map/CoverPillar2
@onready var pillar3: CSGBox3D = $Map/CoverPillar3
@onready var pillar4: CSGBox3D = $Map/CoverPillar4

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
	_apply_map_theme(GameManager.selected_map_id)
	_spawn_players()
	
	if multiplayer.is_server():
		get_tree().create_timer(2.0).timeout.connect(_start_next_wave)

func _apply_map_theme(map_id: int) -> void:
	var floor_mat = StandardMaterial3D.new()
	var pillar_mat = StandardMaterial3D.new()
	
	match map_id:
		0: # Fruit Kingdom Arena (مملكة الفواكه)
			floor_mat.albedo_color = Color(0.25, 0.65, 0.2) # Lush green lawn
			floor_mat.roughness = 0.8
			pillar_mat.albedo_color = Color(0.85, 0.35, 0.15) # Fruit crates
			if sun_light:
				sun_light.light_color = Color(1.0, 0.95, 0.85)
				sun_light.light_energy = 1.3
		1: # Cyber Stadium (ساحة السايبر)
			floor_mat.albedo_color = Color(0.1, 0.12, 0.18)
			floor_mat.metallic = 0.6
			floor_mat.roughness = 0.3
			pillar_mat.albedo_color = Color(0.15, 0.25, 0.4)
			pillar_mat.emission_enabled = true
			pillar_mat.emission = Color(0, 0.8, 1)
			pillar_mat.emission_energy_multiplier = 1.5
			if sun_light:
				sun_light.light_color = Color(0.6, 0.8, 1.0)
				sun_light.light_energy = 0.9
		2: # Desert Titan Canyon (وادي العمالقة)
			floor_mat.albedo_color = Color(0.85, 0.65, 0.35) # Golden desert sand
			floor_mat.roughness = 0.9
			pillar_mat.albedo_color = Color(0.65, 0.45, 0.25) # Canyon sandstone
			if sun_light:
				sun_light.light_color = Color(1.0, 0.75, 0.5) # Sunset orange
				sun_light.light_energy = 1.5
	
	if floor_mesh: floor_mesh.material = floor_mat
	if pillar1: pillar1.material = pillar_mat
	if pillar2: pillar2.material = pillar_mat
	if pillar3: pillar3.material = pillar_mat
	if pillar4: pillar4.material = pillar_mat

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
			get_tree().create_timer(i * 1.3).timeout.connect(func():
				_spawn_minion()
			)
		
		_monitor_wave_clear()
	else:
		_start_boss_battle()

func _monitor_wave_clear() -> void:
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if GameManager.enemies_remaining <= 0:
			_reward_materials_all(75)
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

var current_boss_phase: int = 0

func _start_boss_battle() -> void:
	current_boss_phase = 1
	GameManager.current_state = GameManager.GameState.BOSS_FIGHT
	GameManager.wave_updated.emit(GameManager.max_waves + 1, GameManager.max_waves, 1)
	rpc("_sync_wave_info", GameManager.max_waves + 1, GameManager.max_waves, 1)
	
	_spawn_boss(1)

func _spawn_boss(boss_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var boss = boss_scene.instantiate()
	boss.global_position = boss_spawn_marker.global_position if boss_spawn_marker else Vector3(0, 0, -22)
	enemies_container.add_child(boss, true)
	
	# Apply preset across all peers
	boss.rpc("apply_boss_preset", boss_id)
	
	if boss_id == 1:
		rpc("_broadcast_hud_alert", "⚠️ WARNING: TITAN DESTROYER APPROACHES! ⚠️\n(البيج بوس الأول يقترب - استعدوا للمعركة!)", Color(1.0, 0.7, 0.2))
	else:
		rpc("_broadcast_hud_alert", "💀 ALERT: APOCALYPSE MEGA TITAN HAS RISEN! 💀\n(البيج بوس الثاني الخارق يظهر الآن - احذروا الكور المدمرة!)", Color(1.0, 0.15, 0.15))
	
	boss.boss_defeated.connect(func():
		_on_boss_stage_cleared(boss_id)
	)

func _on_boss_stage_cleared(cleared_boss_id: int) -> void:
	if cleared_boss_id == 1:
		rpc("_broadcast_hud_alert", "💥 BOSS 1 DESTROYED! 💥\n⚠️ AN ANCIENT MEGA TITAN AWAKENS! (البيج بوس الثاني قادم!) ⚠️", Color(1.0, 0.85, 0.1))
		_reward_materials_all(150)
		
		get_tree().create_timer(4.5).timeout.connect(func():
			if multiplayer.is_server():
				current_boss_phase = 2
				_spawn_boss(2)
		)
	elif cleared_boss_id == 2:
		rpc("_broadcast_hud_alert", "🏆 ALL TITANS OBLITERATED! YOU SAVED CYBERFORT! 🏆", Color(0.2, 1.0, 0.3))

@rpc("call_local", "reliable")
func _broadcast_hud_alert(msg: String, col: Color) -> void:
	if hud and hud.alert_label:
		hud.alert_label.text = msg
		hud.alert_label.modulate = col
		hud.alert_label.visible = true
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(hud) and hud.alert_label and hud.alert_label.text == msg:
				hud.alert_label.visible = false
		)

@rpc("call_local", "reliable")
func _sync_wave_info(w: int, max_w: int, left: int) -> void:
	GameManager.wave_updated.emit(w, max_w, left)
