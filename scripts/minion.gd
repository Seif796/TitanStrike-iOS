extends CharacterBody3D
class_name Minion

# Minion Script (res://scripts/minion.gd)
# Features articulated mech spider body, dynamic crawl animation, and projectile ball throwing.

@export var max_hp: float = 85.0
var current_hp: float = 85.0
var move_speed: float = 5.2
var melee_damage: float = 16.0
var ranged_damage: float = 20.0

var attack_cooldown: float = 2.0
var can_attack: bool = true

var target_player: Player = null
var sync_pos: Vector3 = Vector3.ZERO
var sync_rot_y: float = 0.0
var crawl_cycle: float = 0.0
var retarget_timer: float = 0.0
var wave_level: int = 1  # Set by arena — higher = more dangerous volley fire

@onready var model: Node3D = $Model
@onready var launcher: Node3D = $Model/Launcher
@onready var leg_fl: Node3D = $Model/LegFL
@onready var leg_fr: Node3D = $Model/LegFR
@onready var leg_bl: Node3D = $Model/LegBL
@onready var leg_br: Node3D = $Model/LegBR
@onready var overhead_health_bar: Node3D = get_node_or_null("OverheadHealthBar")

var projectile_scene = preload("res://scenes/minion_projectile.tscn")

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("minions")
	current_hp = max_hp
	if overhead_health_bar:
		overhead_health_bar.set_entity_name("MECH SPIDER", Color(1.0, 0.35, 0.35))
		overhead_health_bar.update_health(current_hp, max_hp)

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_process(delta)
		rpc("_sync_minion_transform", global_position, rotation.y)
	else:
		global_position = global_position.lerp(sync_pos, 12.0 * delta)
		rotation.y = lerp_angle(rotation.y, sync_rot_y, 12.0 * delta)
		move_and_slide()
	
	_animate_legs(delta)

func _animate_legs(delta: float) -> void:
	var speed = velocity.length()
	if speed > 0.2:
		crawl_cycle += delta * speed * 4.0
		var angle_a = sin(crawl_cycle) * deg_to_rad(28)
		var angle_b = -sin(crawl_cycle) * deg_to_rad(28)
		
		# Alternate diagonal leg pairs (spider scuttle animation)
		if leg_fl: leg_fl.rotation.x = angle_a
		if leg_br: leg_br.rotation.x = angle_a
		if leg_fr: leg_fr.rotation.x = angle_b
		if leg_bl: leg_bl.rotation.x = angle_b
	else:
		if leg_fl: leg_fl.rotation.x = lerp_angle(leg_fl.rotation.x, 0, 8.0 * delta)
		if leg_fr: leg_fr.rotation.x = lerp_angle(leg_fr.rotation.x, 0, 8.0 * delta)
		if leg_bl: leg_bl.rotation.x = lerp_angle(leg_bl.rotation.x, 0, 8.0 * delta)
		if leg_br: leg_br.rotation.x = lerp_angle(leg_br.rotation.x, 0, 8.0 * delta)

func _server_process(delta: float) -> void:
	retarget_timer += delta
	if retarget_timer >= 1.5 or not is_instance_valid(target_player) or target_player.is_down:
		retarget_timer = 0.0
		_find_target()
	
	if not is_instance_valid(target_player):
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	
	var dist = global_position.distance_to(target_player.global_position)
	var dir = (target_player.global_position - global_position).normalized()
	dir.y = 0
	
	look_at_safe(global_position + dir)
	
	# Throw ball attack at long range (3.5m to 30m)
	if dist > 3.0 and dist <= 30.0 and can_attack:
		_throw_ball(target_player.global_position)
	elif dist <= 2.8 and can_attack:
		_melee_attack()
	
	if dist > 3.0:
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
	
	move_and_slide()

func _find_target() -> void:
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

func _throw_ball(target_pos: Vector3) -> void:
	can_attack = false
	var volley_count = clamp(1 + (wave_level / 2), 1, 5)  # 1–5 balls based on wave_level
	for i in range(volley_count):
		get_tree().create_timer(i * 0.28).timeout.connect(func():
			if is_instance_valid(self) and not is_queued_for_deletion():
				var spread = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
				rpc("_spawn_throw_visuals", target_pos + spread)
		)
	
	get_tree().create_timer(attack_cooldown).timeout.connect(func():
		can_attack = true
	)

@rpc("call_local", "reliable")
func _spawn_throw_visuals(target_pos: Vector3) -> void:
	# Launcher recoil
	if launcher:
		launcher.rotation.x = deg_to_rad(-45)
		get_tree().create_timer(0.2).timeout.connect(func():
			if launcher: launcher.rotation.x = deg_to_rad(-15)
		)
	
	if projectile_scene:
		var proj = projectile_scene.instantiate()
		var spawn_pos = global_position + Vector3(0, 0.9, 0)
		var dir = (target_pos + Vector3(0, 0.8, 0) - spawn_pos).normalized()
		proj.setup(spawn_pos, dir, ranged_damage)
		get_tree().current_scene.add_child(proj)

func _melee_attack() -> void:
	can_attack = false
	if is_instance_valid(target_player):
		target_player.take_damage(melee_damage)
	
	get_tree().create_timer(1.2).timeout.connect(func():
		can_attack = true
	)

func take_damage(amount: float, shooter_id: int = 1) -> void:
	if not multiplayer.is_server():
		rpc_id(1, "_request_damage", amount, shooter_id)
		return
	_apply_damage(amount, shooter_id)

@rpc("any_peer", "reliable")
func _request_damage(amount: float, shooter_id: int) -> void:
	if multiplayer.is_server():
		_apply_damage(amount, shooter_id)

func _apply_damage(amount: float, shooter_id: int) -> void:
	current_hp = max(0.0, current_hp - amount)
	rpc("_sync_minion_hp", current_hp, max_hp)
	
	# Dynamic aggro: 50% chance to immediately switch target to the attacker if alive
	if randf() < 0.5:
		var players = get_tree().get_nodes_in_group("players")
		for p in players:
			if p is Player and p.peer_id == shooter_id and not p.is_down:
				target_player = p
				break
	if current_hp <= 0:
		_die()

@rpc("call_local", "reliable")
func _sync_minion_hp(hp: float, m_hp: float) -> void:
	current_hp = hp
	max_hp = m_hp
	if overhead_health_bar:
		overhead_health_bar.update_health(current_hp, max_hp)

func _die() -> void:
	if GameManager.enemies_remaining > 0:
		GameManager.enemies_remaining -= 1
		GameManager.wave_updated.emit(GameManager.current_wave, GameManager.max_waves, GameManager.enemies_remaining)
	queue_free()

func look_at_safe(target: Vector3) -> void:
	if global_position.is_equal_approx(target):
		return
	look_at(target, Vector3.UP)

@rpc("unreliable")
func _sync_minion_transform(pos: Vector3, rot_y: float) -> void:
	sync_pos = pos
	sync_rot_y = rot_y

