extends CharacterBody3D
class_name Boss

# Boss Script (res://scripts/boss.gd)
# Colossal Big Boss with 2500 HP, multi-phase rage modes, ground shockwave, and meteor fireballs.

signal health_changed(current: float, max_val: float)
signal boss_defeated()

enum BossState {
	IDLE,
	CHASE,
	MELEE_SLAM,
	RANGED_BARRAGE,
	BERSERK_ROAR,
	DEFEATED
}

@export var max_hp: float = 2500.0
var current_hp: float = 2500.0
var current_phase: int = 1
var state: BossState = BossState.IDLE

var move_speed: float = 4.0
var target_player: Player = null
var attack_cooldown: float = 2.0
var can_attack: bool = true

@onready var mesh_body: MeshInstance3D = $Model/BodyMesh
@onready var eyes_light: OmniLight3D = $Model/Head/EyesLight
@onready var core_mesh: MeshInstance3D = $Model/GlowingCore
@onready var shockwave_area: Area3D = $ShockwaveArea
@onready var projectile_spawn: Marker3D = $ProjectileSpawn
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var boss_projectile_scene = preload("res://scenes/boss_projectile.tscn")
var minion_scene = preload("res://scenes/minion.tscn")

var sync_pos: Vector3 = Vector3.ZERO
var sync_rot: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	current_hp = max_hp
	GameManager.boss_node = self
	health_changed.emit(current_hp, max_hp)
	GameManager.boss_health_updated.emit(current_hp, max_hp)
	
	if shockwave_area:
		shockwave_area.monitoring = false

func _physics_process(delta: float) -> void:
	if state == BossState.DEFEATED:
		return
	
	if multiplayer.is_server():
		_server_ai_process(delta)
		rpc("_sync_boss_transform", global_position, rotation.y)
	else:
		global_position = global_position.lerp(sync_pos, 10.0 * delta)
		rotation.y = lerp_angle(rotation.y, sync_rot, 10.0 * delta)
		move_and_slide()

func _server_ai_process(delta: float) -> void:
	if not is_instance_valid(target_player) or target_player.is_down:
		_find_closest_player()
	
	if not is_instance_valid(target_player):
		state = BossState.IDLE
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		move_and_slide()
		return
	
	var dist = global_position.distance_to(target_player.global_position)
	var dir = (target_player.global_position - global_position).normalized()
	dir.y = 0
	
	var target_rot = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, 4.5 * delta)
	
	if can_attack:
		if dist <= 7.0:
			_perform_melee_slam()
		elif dist > 7.0 and current_phase >= 2:
			_perform_ranged_barrage()
		elif current_phase == 3 and randf() < 0.02:
			_perform_berserk_summon()
	
	if state == BossState.CHASE or state == BossState.IDLE:
		if dist > 5.0:
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.z = 0
	
	move_and_slide()

func _find_closest_player() -> void:
	var players = get_tree().get_nodes_in_group("players")
	var closest_dist = INF
	var closest: Player = null
	for p in players:
		if p is Player and not p.is_down:
			var d = global_position.distance_to(p.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = p
	target_player = closest

# --- ATTACKS ---

func _perform_melee_slam() -> void:
	can_attack = false
	state = BossState.MELEE_SLAM
	rpc("_play_boss_anim", "slam")
	
	get_tree().create_timer(0.7).timeout.connect(func():
		_deal_shockwave_damage()
		get_tree().create_timer(1.0).timeout.connect(func():
			state = BossState.CHASE
			can_attack = true
		)
	)

func _deal_shockwave_damage() -> void:
	if not multiplayer.is_server():
		return
	
	# Massive slam damage to nearby players and structures
	for body in shockwave_area.get_overlapping_bodies():
		if body is Player and not body.is_down:
			body.take_damage(65.0)
		elif body is Structure:
			body.take_damage(120.0)

func _perform_ranged_barrage() -> void:
	can_attack = false
	state = BossState.RANGED_BARRAGE
	rpc("_play_boss_anim", "cast")
	
	var count = 5 if current_phase == 2 else 8
	for i in range(count):
		get_tree().create_timer(i * 0.35).timeout.connect(func():
			if state != BossState.DEFEATED and is_instance_valid(target_player):
				_spawn_boss_orb()
		)
	
	get_tree().create_timer(count * 0.35 + 1.2).timeout.connect(func():
		state = BossState.CHASE
		can_attack = true
	)

func _spawn_boss_orb() -> void:
	if not multiplayer.is_server():
		return
	var orb = boss_projectile_scene.instantiate()
	var spawn_pos = projectile_spawn.global_position if projectile_spawn else global_position + Vector3(0, 3.5, 0)
	var dir = (target_player.global_position + Vector3(0, 1, 0) - spawn_pos).normalized()
	orb.setup(spawn_pos, dir, 45.0, target_player)
	get_tree().current_scene.add_child(orb, true)

func _perform_berserk_summon() -> void:
	can_attack = false
	state = BossState.BERSERK_ROAR
	rpc("_play_boss_anim", "roar")
	
	# Summons 4 ball-throwing minions
	for i in range(4):
		var minion = minion_scene.instantiate()
		var offset = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		minion.global_position = global_position + offset
		get_tree().current_scene.add_child(minion, true)
	
	get_tree().create_timer(2.2).timeout.connect(func():
		state = BossState.CHASE
		can_attack = true
	)

# --- DAMAGE & PHASES ---

func take_damage(amount: float, _shooter_id: int = 1) -> void:
	if state == BossState.DEFEATED:
		return
	
	if multiplayer.is_server():
		_apply_damage(amount)
		rpc("_sync_boss_damage", current_hp)

@rpc("any_peer", "call_local", "reliable")
func _sync_boss_damage(new_hp: float) -> void:
	current_hp = new_hp
	health_changed.emit(current_hp, max_hp)
	GameManager.boss_health_updated.emit(current_hp, max_hp)
	_check_phase()
	
	if current_hp <= 0 and state != BossState.DEFEATED:
		_die()

func _apply_damage(amount: float) -> void:
	current_hp = max(0, current_hp - amount)
	health_changed.emit(current_hp, max_hp)
	GameManager.boss_health_updated.emit(current_hp, max_hp)
	_check_phase()
	
	if current_hp <= 0:
		_die()

func _check_phase() -> void:
	var hp_pct = current_hp / max_hp
	if hp_pct <= 0.35 and current_phase < 3:
		current_phase = 3
		move_speed = 6.2 # Super fast Berserk mode!
		attack_cooldown = 1.2
		if eyes_light:
			eyes_light.light_color = Color(1, 0, 0.4)
			eyes_light.light_energy = 8.0
		if core_mesh and core_mesh.material_override is StandardMaterial3D:
			core_mesh.material_override.albedo_color = Color(1, 0, 0.2)
			core_mesh.material_override.emission = Color(1, 0, 0.2)
	elif hp_pct <= 0.70 and current_phase < 2:
		current_phase = 2
		move_speed = 5.0
		attack_cooldown = 1.6
		if eyes_light:
			eyes_light.light_color = Color.ORANGE
			eyes_light.light_energy = 5.0

func _die() -> void:
	state = BossState.DEFEATED
	boss_defeated.emit()
	rpc("_play_boss_anim", "defeat")
	
	get_tree().create_timer(3.0).timeout.connect(func():
		GameManager.rpc("trigger_game_over", true)
	)

@rpc("unreliable")
func _sync_boss_transform(pos: Vector3, rot_y: float) -> void:
	sync_pos = pos
	sync_rot = rot_y

@rpc("call_local", "reliable")
func _play_boss_anim(anim_name: String) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
