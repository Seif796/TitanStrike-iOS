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
var revive_station_scene = preload("res://scenes/revive_station.tscn")
var training_dummy_scene = preload("res://scenes/training_dummy.tscn")

var local_player: Player = null

func _ready() -> void:
	_apply_map_theme(GameManager.selected_map_id)
	_spawn_players()
	GameManager.retry_stage_requested.connect(_on_retry_stage_requested)
	
	if GameManager.selected_game_mode == GameManager.GameMode.TRAINING:
		_setup_training_mode()
	elif GameManager.selected_game_mode == GameManager.GameMode.PVP_DUEL:
		_setup_pvp_mode()
	else:
		_setup_coop_mode()

func _apply_map_theme(map_id: int) -> void:
	var floor_mat = StandardMaterial3D.new()
	var pillar_mat = StandardMaterial3D.new()
	var wall_mat = StandardMaterial3D.new()
	
	# Clean metallic wall base
	wall_mat.albedo_color = Color(0.12, 0.14, 0.18)
	wall_mat.metallic = 0.8
	wall_mat.roughness = 0.35
	
	var sky_mat = ProceduralSkyMaterial.new()
	var fog_col = Color(0.15, 0.2, 0.3)
	var fog_dens = 0.003
	
	match map_id:
		0: # Fruit Kingdom Arena (مملكة الفواكه الخضراء)
			floor_mat.albedo_color = Color(0.22, 0.65, 0.24) # Lush grass green
			floor_mat.roughness = 0.75
			pillar_mat.albedo_color = Color(0.95, 0.55, 0.15) # Gold fruit crate
			pillar_mat.metallic = 0.3
			pillar_mat.emission_enabled = true
			pillar_mat.emission = Color(0.4, 0.85, 0.2)
			pillar_mat.emission_energy_multiplier = 1.2
			sky_mat.sky_top_color = Color(0.25, 0.55, 0.95)
			sky_mat.sky_horizon_color = Color(0.7, 0.85, 0.98)
			sky_mat.ground_bottom_color = Color(0.15, 0.35, 0.12)
			fog_col = Color(0.65, 0.82, 0.95)
			fog_dens = 0.002
			if sun_light:
				sun_light.light_color = Color(1.0, 0.96, 0.88)
				sun_light.light_energy = 0.95

		1: # Cyber Stadium 2077 (ساحة السايبر المستقبلية)
			floor_mat.albedo_color = Color(0.06, 0.08, 0.14)
			floor_mat.metallic = 0.85
			floor_mat.roughness = 0.18
			pillar_mat.albedo_color = Color(0.1, 0.25, 0.45)
			pillar_mat.emission_enabled = true
			pillar_mat.emission = Color(0.0, 0.92, 1.0)
			pillar_mat.emission_energy_multiplier = 4.0
			sky_mat.sky_top_color = Color(0.04, 0.05, 0.12)
			sky_mat.sky_horizon_color = Color(0.0, 0.5, 0.8)
			sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.06)
			fog_col = Color(0.0, 0.25, 0.5)
			fog_dens = 0.004
			if sun_light:
				sun_light.light_color = Color(0.4, 0.85, 1.0)
				sun_light.light_energy = 0.85

		2: # Desert Titan Canyon (وادي العمالقة الصحراوي)
			floor_mat.albedo_color = Color(0.86, 0.62, 0.32) # Golden desert dunes
			floor_mat.roughness = 0.88
			pillar_mat.albedo_color = Color(0.75, 0.36, 0.2) # Canyon sandstone
			pillar_mat.emission_enabled = true
			pillar_mat.emission = Color(0.9, 0.45, 0.1)
			pillar_mat.emission_energy_multiplier = 1.5
			sky_mat.sky_top_color = Color(0.4, 0.2, 0.55) # Sunset twilight
			sky_mat.sky_horizon_color = Color(1.0, 0.55, 0.25)
			sky_mat.ground_bottom_color = Color(0.35, 0.18, 0.08)
			fog_col = Color(0.95, 0.6, 0.35)
			fog_dens = 0.003
			if sun_light:
				sun_light.light_color = Color(1.0, 0.68, 0.42)
				sun_light.light_energy = 1.05

		3: # Volcanic Magma Core (قلب البركان المشتعل)
			floor_mat.albedo_color = Color(0.1, 0.07, 0.08) # Obsidian rock
			floor_mat.metallic = 0.6
			floor_mat.roughness = 0.35
			pillar_mat.albedo_color = Color(0.3, 0.05, 0.05)
			pillar_mat.emission_enabled = true
			pillar_mat.emission = Color(1.0, 0.2, 0.0) # Fiery lava glow
			pillar_mat.emission_energy_multiplier = 1.6
			sky_mat.sky_top_color = Color(0.12, 0.02, 0.03)
			sky_mat.sky_horizon_color = Color(0.85, 0.2, 0.05)
			sky_mat.ground_bottom_color = Color(0.2, 0.04, 0.02)
			fog_col = Color(0.7, 0.15, 0.05)
			fog_dens = 0.0045
			if sun_light:
				sun_light.light_color = Color(1.0, 0.35, 0.12)
				sun_light.light_energy = 0.955

		4: # Frozen Ice Glacier (جليد القطب المتجمد)
			floor_mat.albedo_color = Color(0.7, 0.9, 0.98) # Smooth polar ice
			floor_mat.metallic = 0.4
			floor_mat.roughness = 0.12
			pillar_mat.albedo_color = Color(0.25, 0.6, 0.85)
			pillar_mat.emission_enabled = true
			pillar_mat.emission = Color(0.3, 0.92, 1.0) # Aurora cyan crystal
			pillar_mat.emission_energy_multiplier = 3.5
			sky_mat.sky_top_color = Color(0.08, 0.25, 0.45)
			sky_mat.sky_horizon_color = Color(0.4, 0.85, 0.95)
			sky_mat.ground_bottom_color = Color(0.1, 0.25, 0.4)
			fog_col = Color(0.4, 0.8, 0.95)
			fog_dens = 0.003
			if sun_light:
				sun_light.light_color = Color(0.8, 0.94, 1.0)
				sun_light.light_energy = 0.90

		5: # Cosmic Galaxy Station (محطة المجرة الفضائية)
			floor_mat.albedo_color = Color(0.12, 0.06, 0.2) # Deep space deck
			floor_mat.metallic = 0.85
			floor_mat.roughness = 0.22
			pillar_mat.albedo_color = Color(0.22, 0.1, 0.38)
			pillar_mat.emission_enabled = true
			pillar_mat.emission = Color(0.85, 0.2, 1.0) # Starlight violet plasma
			pillar_mat.emission_energy_multiplier = 4.0
			sky_mat.sky_top_color = Color(0.06, 0.02, 0.14)
			sky_mat.sky_horizon_color = Color(0.6, 0.15, 0.85)
			sky_mat.ground_bottom_color = Color(0.05, 0.02, 0.1)
			fog_col = Color(0.5, 0.1, 0.75)
			fog_dens = 0.0038
			if sun_light:
				sun_light.light_color = Color(0.75, 0.55, 1.0)
				sun_light.light_energy = 0.88

		6: # Neon Castle Citadel (قلعة النيون المظلمة)
			floor_mat.albedo_color = Color(0.08, 0.08, 0.1) # Dark synth rock
			floor_mat.metallic = 0.6
			floor_mat.roughness = 0.25
			pillar_mat.albedo_color = Color(0.25, 0.08, 0.22)
			pillar_mat.emission_enabled = true
			pillar_mat.emission = Color(1.0, 0.1, 0.65) # Hot magenta neon
			pillar_mat.emission_energy_multiplier = 1.6
			sky_mat.sky_top_color = Color(0.08, 0.02, 0.1)
			sky_mat.sky_horizon_color = Color(0.85, 0.12, 0.55)
			sky_mat.ground_bottom_color = Color(0.05, 0.02, 0.06)
			fog_col = Color(0.8, 0.1, 0.5)
			fog_dens = 0.004
			if sun_light:
				sun_light.light_color = Color(0.95, 0.45, 0.75)
				sun_light.light_energy = 0.885

	if world_env and world_env.environment:
		var sky_res = Sky.new()
		sky_res.sky_material = sky_mat
		world_env.environment.sky = sky_res
		world_env.environment.fog_light_color = fog_col
		world_env.environment.fog_density = fog_dens
		world_env.environment.ambient_light_color = fog_col
	
	if floor_mesh: floor_mesh.material = floor_mat
	if wall_north: wall_north.material = wall_mat
	if wall_south: wall_south.material = wall_mat
	if wall_east: wall_east.material = wall_mat
	if wall_west: wall_west.material = wall_mat
	if pillar1: pillar1.material = pillar_mat
	if pillar2: pillar2.material = pillar_mat
	if pillar3: pillar3.material = pillar_mat
	if pillar4: pillar4.material = pillar_mat
	
	_add_arena_corner_beacons(pillar_mat.emission)

func _add_arena_corner_beacons(beacon_col: Color) -> void:
	if has_node("CornerBeacons"):
		get_node("CornerBeacons").queue_free()
	
	var container = Node3D.new()
	container.name = "CornerBeacons"
	add_child(container)
	
	var corners = [
		Vector3(-42, 0, -42),
		Vector3(42, 0, -42),
		Vector3(-42, 0, 42),
		Vector3(42, 0, 42)
	]
	
	var beacon_mat = StandardMaterial3D.new()
	beacon_mat.albedo_color = beacon_col
	beacon_mat.emission_enabled = true
	beacon_mat.emission = beacon_col
	beacon_mat.emission_energy_multiplier = 4.0
	
	for pos in corners:
		var beacon_pylon = CSGCylinder3D.new()
		beacon_pylon.radius = 0.8
		beacon_pylon.height = 10.0
		beacon_pylon.position = pos + Vector3(0, 5, 0)
		beacon_pylon.material = beacon_mat
		container.add_child(beacon_pylon)
		
		var omni = OmniLight3D.new()
		omni.light_color = beacon_col
		omni.light_energy = 1.1
		omni.omni_range = 16.0
		omni.position = pos + Vector3(0, 9.5, 0)
		container.add_child(omni)

func _setup_coop_mode() -> void:
	# Spawn Revive Station terminal in the central tactical zone
	var station = revive_station_scene.instantiate()
	station.name = "ReviveStation"
	station.position = Vector3(0, 0, 10)
	add_child(station)
	
	if multiplayer.is_server():
		get_tree().create_timer(2.0).timeout.connect(_start_next_wave)

func _setup_pvp_mode() -> void:
	GameManager.wave_updated.emit(1, 1, 0)
	get_tree().create_timer(1.2).timeout.connect(func():
		rpc("_broadcast_hud_alert", "⚔️ 1v1 PVP DUEL: FIGHT! ⚔️\n(المبارزة بدأت! اهزم خصمك للفوز!)", Color(1.0, 0.4, 0.2))
	)

func _setup_training_mode() -> void:
	GameManager.wave_updated.emit(1, 1, 0)
	
	# 1. Target 1: Standard Dummy with DPS counter
	var dummy1 = training_dummy_scene.instantiate()
	dummy1.name = "TrainingDummy"
	dummy1.position = Vector3(0, 0, 0)
	dummy1.dummy_title = "🎯 روبوت التدريب المباشر (Standard Target)"
	add_child(dummy1)
	
	# 2. Target 2: Heavy Armored Dummy (Sustained Firepower Practice)
	var dummy2 = training_dummy_scene.instantiate()
	dummy2.name = "ArmoredDummy"
	dummy2.position = Vector3(0, 0, -18)
	dummy2.start_hp = 3500.0
	dummy2.dummy_title = "🛡️ درع الوحش الثقيل (Heavy Armored Dummy - 3500 HP)"
	add_child(dummy2)
	
	# 3. Target 3: Moving Agility Drone (Aim & Leading Shots Practice)
	var dummy3 = training_dummy_scene.instantiate()
	dummy3.name = "MovingDrone"
	dummy3.position = Vector3(0, 0.4, -9)
	dummy3.is_moving = true
	dummy3.move_speed = 5.5
	dummy3.move_distance = 11.0
	dummy3.dummy_title = "⚡ مجسم مناورة متحرك (Moving Drone Target)"
	add_child(dummy3)
	
	# 4. Interactive Health & Ammo Recharge Pad
	_setup_training_recharge_pad(Vector3(0, 0.05, 12))
	
	get_tree().create_timer(1.0).timeout.connect(func():
		rpc("_broadcast_hud_alert", "🎯 ساحة التدريب المتطورة (Advanced Training Grounds) 🎯\n• أهداف ثابتة ومتحركة مع حساب DPS\n• منصة استعادة الطاقة والذخيرة بالخلف", Color(0.1, 0.95, 0.6))
	)

func _setup_training_recharge_pad(pos: Vector3) -> void:
	var pad_area = Area3D.new()
	pad_area.name = "RechargePad"
	pad_area.position = pos
	
	var col = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = 2.5
	shape.height = 1.0
	col.shape = shape
	pad_area.add_child(col)
	
	var pad_mesh = CSGCylinder3D.new()
	pad_mesh.radius = 2.5
	pad_mesh.height = 0.1
	var pad_mat = StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.1, 0.85, 0.35)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.15, 0.95, 0.4)
	pad_mat.emission_energy_multiplier = 3.0
	pad_mesh.material = pad_mat
	pad_area.add_child(pad_mesh)
	
	var pad_light = OmniLight3D.new()
	pad_light.light_color = Color(0.2, 1.0, 0.5)
	pad_light.light_energy = 0.9
	pad_light.omni_range = 6.0
	pad_light.position = Vector3(0, 1.0, 0)
	pad_area.add_child(pad_light)
	
	var pad_lbl = Label3D.new()
	pad_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pad_lbl.text = "⚡ منصة شحن الصحة والذخيرة فوراً (RECHARGE PAD) ⚡"
	pad_lbl.position = Vector3(0, 2.2, 0)
	pad_lbl.modulate = Color(0.3, 1.0, 0.6)
	pad_lbl.font_size = 28
	pad_area.add_child(pad_lbl)
	
	pad_area.body_entered.connect(func(body):
		if body.is_in_group("players") and body.has_method("heal"):
			body.heal(999.0)
			AudioManager.play_sfx("redeem")
			if hud:
				hud.show_announcement("✨ تم شحن دمك وطاقتك بالكامل (100% HEALTH & AMMO)! ✨")
	)
	
	add_child(pad_area)

func _spawn_players() -> void:
	var spawn_nodes = spawn_points.get_children()
	var spawn_index = 0
	var is_pvp = (GameManager.selected_game_mode == GameManager.GameMode.PVP_DUEL)
	var is_training = (GameManager.selected_game_mode == GameManager.GameMode.TRAINING)
	
	if NetworkManager.players.is_empty():
		var p = player_scene.instantiate()
		p.name = "1"
		p.peer_id = 1
		p.class_id = NetworkManager.local_class_id
		players_container.add_child(p)
		p.global_position = Vector3(0, 0, 18) if is_training else spawn_nodes[0].global_position
		_setup_local_player(p)
		
		# Solo player: deploy AI Bot companion or PvP opponent
		if not is_training and not is_pvp and GameManager.bot_enabled:
			var bot_pos = spawn_nodes[1].global_position if spawn_nodes.size() > 1 else spawn_nodes[0].global_position + Vector3(3, 0, 0)
			_spawn_bot_companion(bot_pos)
		elif is_pvp and GameManager.bot_enabled:
			_spawn_pvp_bot_opponent(Vector3(0, 0, -22))
		return
	
	for peer_id in NetworkManager.players:
		var p_info = NetworkManager.players[peer_id]
		var p = player_scene.instantiate()
		p.name = str(peer_id)
		p.peer_id = peer_id
		p.class_id = p_info.get("class_id", 0)
		
		var spawn_pos = Vector3.ZERO
		if is_pvp:
			# Opposite sides in 1v1 PvP
			spawn_pos = Vector3(0, 0, 22) if spawn_index == 0 else Vector3(0, 0, -22)
			spawn_index += 1
		else:
			if spawn_index < spawn_nodes.size():
				spawn_pos = spawn_nodes[spawn_index].global_position
				spawn_index += 1
		
		players_container.add_child(p)
		p.global_position = spawn_pos
		if is_pvp and spawn_pos.z < 0:
			p.rotation.y = PI # Face south towards opponent
		
		if peer_id == multiplayer.get_unique_id():
			_setup_local_player(p)
	
	# In co-op or PvP, spawn Bot if 1 player and bot enabled
	if not is_pvp and not is_training and NetworkManager.players.size() == 1 and GameManager.bot_enabled:
		var bot_pos = spawn_nodes[1].global_position if spawn_nodes.size() > 1 else spawn_nodes[0].global_position + Vector3(3, 0, 0)
		_spawn_bot_companion(bot_pos)
	elif is_pvp and NetworkManager.players.size() == 1 and GameManager.bot_enabled:
		_spawn_pvp_bot_opponent(Vector3(0, 0, -22))

func _spawn_pvp_bot_opponent(pos: Vector3) -> void:
	var bot = player_scene.instantiate()
	bot.name = "CyberAI_Bot"
	bot.peer_id = 999
	bot.is_bot = true
	bot.class_id = GameManager.bot_class_id

	var bot_ai = PlayerBotAI.new()
	bot_ai.name = "BotAI"
	bot.add_child(bot_ai)

	players_container.add_child(bot)
	bot.global_position = pos
	bot.rotation.y = PI

	var c_data = GameManager.CLASSES.get(GameManager.bot_class_id, GameManager.CLASSES[4])
	get_tree().create_timer(1.0).timeout.connect(func():
		rpc("_broadcast_hud_alert", "⚔️ 1v1 DUEL VS CYBERAI: FIGHT! ⚔️\n(خصمك: CyberAI [BOT] - بطل: %s)" % c_data["name"], Color(1.0, 0.3, 0.5))
	)

func _spawn_bot_companion(pos: Vector3) -> void:
	var bot = player_scene.instantiate()
	bot.name = "Bot_Companion"
	bot.peer_id = 999
	bot.is_bot = true
	bot.class_id = GameManager.bot_class_id
	
	# Attach AI brain
	var bot_ai = PlayerBotAI.new()
	bot_ai.name = "BotAI"
	bot.add_child(bot_ai)
	
	players_container.add_child(bot)
	bot.global_position = pos
	
	var c_data = GameManager.CLASSES.get(GameManager.bot_class_id, GameManager.CLASSES[1])
	get_tree().create_timer(1.2).timeout.connect(func():
		rpc("_broadcast_hud_alert", "🤖 SQUAD BOT COMPANION JOINED! 🤖\n(انضم البوت المساعد للفريق: %s)" % c_data["name"], Color(0.2, 0.9, 1.0))
	)

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
		_start_current_wave()
	else:
		_start_boss_battle()

func _start_current_wave() -> void:
	if not multiplayer.is_server():
		return
	
	var base_count = 6 + (GameManager.current_wave * 4)
	var enemy_count = base_count * (2 if current_stage == 2 else 1)
	GameManager.enemies_remaining = enemy_count
	GameManager.wave_updated.emit(GameManager.current_wave, GameManager.max_waves, enemy_count)
	rpc("_sync_wave_info", GameManager.current_wave, GameManager.max_waves, enemy_count)
	
	var spawn_delay = 1.3 if current_stage == 1 else 0.7  # Faster spawns in stage 2
	for i in range(enemy_count):
		get_tree().create_timer(i * spawn_delay).timeout.connect(func():
			_spawn_minion()
		)
	
	_monitor_wave_clear()

func _on_retry_stage_requested() -> void:
	if hud and hud.end_screen:
		hud.end_screen.visible = false
	
	# Clear existing enemies and active bosses
	for child in enemies_container.get_children():
		child.queue_free()
	for b in get_tree().get_nodes_in_group("boss"):
		b.queue_free()
	
	# Full restore and reposition players
	var spawn_nodes = spawn_points.get_children()
	var spawn_idx = 0
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player:
			p.rpc("full_restore")
			if spawn_idx < spawn_nodes.size():
				p.global_position = spawn_nodes[spawn_idx].global_position
				spawn_idx += 1
	
	rpc("_broadcast_hud_alert", "🔄 SECOND CHANCE ACTIVATED! RETRYING STAGE! 🔄\n(أعدت المحاولة - استبسلوا للفوز!)", Color(0.2, 0.9, 1.0))
	
	if multiplayer.is_server():
		get_tree().create_timer(2.0).timeout.connect(func():
			if current_boss_phase == 0:
				_start_current_wave()
			elif current_boss_phase == 1:
				_spawn_boss(1)
			elif current_boss_phase == 2:
				_spawn_boss(2)
		)

func _monitor_wave_clear() -> void:
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if GameManager.enemies_remaining <= 0:
			_reward_materials_all(75)
			_full_heal_all_players() # Fully restore all players and bot health!
			
			var just_unlocked_berry = false
			var just_unlocked_citrus = false
			if current_stage == 1:
				if GameManager.current_wave == 1:
					just_unlocked_berry = GameManager.unlock_hero(1)
				elif GameManager.current_wave == 2:
					just_unlocked_citrus = GameManager.unlock_hero(2)
			
			if just_unlocked_berry:
				rpc("_broadcast_hud_alert", "🍓 ROUND 1 CLEARED! UNLOCKED HERO: BERRY STRIKER! 🍓\n(أحسنت! فزت بالجولة الأولى وتم فتح بطلة الفراولة السريعة!)", Color(1.0, 0.25, 0.4))
			elif just_unlocked_citrus:
				rpc("_broadcast_hud_alert", "🍊 ROUND 2 CLEARED! UNLOCKED HERO: CITRUS TANK! 🍊\n(رائع! فزت بالجولة الثانية وتم فتح البرتقال المدرّع العملاق!)", Color(1.0, 0.6, 0.1))
			else:
				rpc("_broadcast_hud_alert", "💚 STAGE CLEARED! HEALTH FULLY RESTORED! 💚\n(اكتملت المرحلة واستعاد الأبطال كامل طاقتهم!)", Color(0.2, 1.0, 0.4))
			
			GameManager.current_wave += 1
			get_tree().create_timer(3.5).timeout.connect(_start_next_wave)
		else:
			_monitor_wave_clear()
	)

func _full_heal_all_players() -> void:
	rpc("_sync_full_heal_all")

@rpc("call_local", "reliable")
func _sync_full_heal_all() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player:
			p.current_hp = p.max_hp
			p.is_down = false
			p.health_changed.emit(p.current_hp, p.max_hp)
			p.downed_state_changed.emit(false)
			if p.active_weapon:
				p.active_weapon.current_ammo = p.active_weapon.max_ammo
				p.active_weapon.is_reloading = false
				p.active_weapon.ammo_changed.emit(p.active_weapon.current_ammo, p.active_weapon.max_ammo, false)

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
	enemies_container.add_child(minion, true)
	minion.global_position = rand_spawn.global_position + offset
	# Hardcore Mission Difficulty Scaling (Nightmare waves & Elite Berserkers)
	var is_elite = (randf() < 0.28)
	minion.wave_level = GameManager.current_wave + (4 if current_stage == 2 else 0)
	var elite_mult = 1.65 if is_elite else 1.0
	minion.max_hp = (110.0 + (GameManager.current_wave * 25.0) + (80.0 if current_stage == 2 else 0.0)) * elite_mult
	minion.current_hp = minion.max_hp
	minion.move_speed = (6.0 + (GameManager.current_wave * 0.45) + (2.0 if current_stage == 2 else 0.0)) * (1.15 if is_elite else 1.0)
	if is_elite:
		minion.scale = Vector3(1.3, 1.3, 1.3)
	minion.rpc("_sync_minion_hp", minion.current_hp, minion.max_hp)

var current_boss_phase: int = 0
var current_stage: int = 1

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
		_reward_materials_all(150)
		_full_heal_all_players()
		rpc("_broadcast_hud_alert", "💥 BOSS 1 DESTROYED! HEALTH RESTORED! 💥\n⚠️ AN ANCIENT MEGA TITAN AWAKENS! (البيج بوس الثاني قادم - استعدوا!) ⚠️", Color(1.0, 0.85, 0.1))
		get_tree().create_timer(4.5).timeout.connect(func():
			if multiplayer.is_server():
				current_boss_phase = 2
				_spawn_boss(2)
		)
	elif cleared_boss_id == 2:
		_reward_materials_all(300)
		_full_heal_all_players()
		var newly_unlocked_admin = GameManager.unlock_hero(3)
		if newly_unlocked_admin:
			rpc("_broadcast_hud_alert", "👑 BOSS DEFEATED! UNLOCKED SECRET HERO: ADMIN (500 HP)! 👑\n(تم فتح شخصية الأدمن الخارق بـ 500 دم والدروع الذهبية!)", Color(1.0, 0.85, 0.1))
		
		if current_stage == 1:
			# Move to Stage 2 — 5 waves, much harder!
			current_stage = 2
			current_boss_phase = 0
			GameManager.current_wave = 1
			GameManager.max_waves = 5
			GameManager.current_state = GameManager.GameState.WAVE_COMBAT
			var next_msg = "🔥 STAGE 2 BEGINS! 5 WAVES OF TITAN CHAOS! 🔥\n(المرحلة الثانية بدأت - 5 موجات أشرس بكتير، استعد!)"
			get_tree().create_timer(3.0 if newly_unlocked_admin else 0.5).timeout.connect(func():
				rpc("_broadcast_hud_alert", next_msg, Color(1.0, 0.3, 0.05))
			)
			get_tree().create_timer(6.0).timeout.connect(func():
				if multiplayer.is_server():
					_start_next_wave()
			)
		else:
			# Stage 2 complete — TRUE victory!
			rpc("_broadcast_hud_alert", "🏆 ALL STAGES CLEARED! YOU ARE LEGEND! 🏆\n(أنهيت اللعبة كاملة - أنت أسطورة!)", Color(0.15, 1.0, 0.3))
			get_tree().create_timer(2.5).timeout.connect(func():
				if multiplayer.is_server():
					GameManager.rpc("trigger_game_over", true)
			)

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
