extends CharacterBody3D
class_name Boss

# Boss Script (res://scripts/boss.gd)
# Giant Titan Boss with 3 phases, melee shockwaves, ranged fireballs, and minion summoning.

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

@export var max_hp: float = 1200.0
var current_hp: float = 1200.0
var current_phase: int = 1
var state: BossState = BossState.IDLE

var move_speed: float = 3.5
var target_player: Player = null
var attack_cooldown: float = 2.5
var can_attack: bool = true

@onready var mesh_body: MeshInstance3D = $Model/BodyMesh
@onready var eyes_light: OmniLight3D = $Model/Head/EyesLight
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
	
	# Rotate towards player
	var target_rot = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, 4.0 * delta)
	
	if can_attack:
		if dist <= 6.0:
			_perform_melee_slam()
		elif dist > 8.0 and current_phase >= 2:
			_perform_ranged_barrage()
		elif current_phase == 3 and randf() < 0.01:
			_perform_berserk_summon()
	
	# Movement
	if state == BossState.CHASE or state == BossState.IDLE:
		if dist > 4.5:
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

# --- ATTACK ABILITIES ---

func _perform_melee_slam() -> void:
	can_attack = false
	state = BossState.MELEE_SLAM
	rpc("_play_boss_anim", "slam")
	
	# Delay for slam impact
	get_tree().create_timer(0.8).timeout.connect(func():
		_deal_shockwave_damage()
		get_tree().create_timer(1.2).timeout.connect(func():
			state = BossState.CHASE
			can_attack = true
		)
	)

func _deal_shockwave_damage() -> void:
	if not multiplayer.is_server():
		return
	
	for body in shockwave_area.get_overlapping_bodies():
		if body is Player and not body.is_down:
			body.take_damage(45.0)

func _perform_ranged_barrage() -> void:
	can_attack = false
	state = BossState.RANGED_BARRAGE
	rpc("_play_boss_anim", "cast")
	
	var shots = 3 if current_phase == 2 else 5
	for i in range(shots):
		get_tree().create_timer(i * 0.4).timeout.connect(func():
			if state != BossState.DEFEATED and is_instance_valid(target_player):
				_spawn_boss_orb()
		)
	
	get_tree().create_timer(shots * 0.4 + 1.0).timeout.connect(func():
		state = BossState.CHASE
		can_attack = true
	)

func _spawn_boss_orb() -> void:
	if not multiplayer.is_server():
		return
	var orb = boss_projectile_scene.instantiate()
	var spawn_pos = projectile_spawn.global_position if projectile_spawn else global_position + Vector3(0, 3, 0)
	var dir = (target_player.global_position - spawn_pos).normalized()
	orb.setup(spawn_pos, dir, 30.0, target_player)
	get_tree().current_scene.add_child(orb, true)

func _perform_berserk_summon() -> void:
	can_attack = false
	state = BossState.BERSERK_ROAR
	rpc("_play_boss_anim", "roar")
	
	for i in range(3):
		var minion = minion_scene.instantiate()
		var offset = Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		minion.global_position = global_position + offset
		get_tree().current_scene.add_child(minion, true)
	
	get_tree().create_timer(2.0).timeout.connect(func():
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
	var hp_percent = current_hp / max_hp
	if hp_percent <= 0.33 and current_phase < 3:
		current_phase = 3
		move_speed = 5.2
		attack_cooldown = 1.6
		if eyes_light:
			eyes_light.light_color = Color.RED
			eyes_light.light_energy = 5.0
	elif hp_percent <= 0.66 and current_phase < 2:
		current_phase = 2
		move_speed = 4.2
		attack_cooldown = 2.0
		if eyes_light:
			eyes_light.light_color = Color.ORANGE
			eyes_light.light_energy = 3.0

func _die() -> void:
	state = BossState.DEFEATED
	boss_defeated.emit()
	rpc("_play_boss_anim", "defeat")
	
	# Trigger Victory for all players!
	get_tree().create_timer(3.0).timeout.connect(func():
		GameManager.rpc("trigger_game_over", true)
	)

# --- NETWORK SYNC ---

@rpc("unreliable")
func _sync_boss_transform(pos: Vector3, rot_y: float) -> void:
	sync_pos = pos
	sync_rot = rot_y

@rpc("call_local", "reliable")
func _play_boss_anim(anim_name: String) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)

