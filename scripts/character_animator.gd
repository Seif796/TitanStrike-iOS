extends Node
class_name CharacterAnimator

# CharacterAnimator Script (res://scripts/character_animator.gd)
# High-energy procedural animation controller for the 3D Watermelon Boy model and legacy rigs.
# Guarantees highly visible, bouncy movement animations, forward sprint leans, hip waddles,
# jump stretches, and realistic tactical two-handed weapon holding.

@export var player: CharacterBody3D
@export var model_root: Node3D
@export var melon_boy_mesh: Node3D
@export var left_leg: Node3D
@export var right_leg: Node3D
@export var left_arm: Node3D
@export var right_arm: Node3D
@export var head: Node3D
@export var leaf_sprout: Node3D
@export var body_mesh: Node3D

@onready var anim_player: AnimationPlayer = $"../AnimationPlayer"

var walk_cycle: float = 0.0
var is_moving: bool = false
var last_rot_y: float = 0.0
var target_tilt_z: float = 0.0

func _ready() -> void:
	# Stop AnimationPlayer in gameplay so procedural locomotion runs with full priority
	if anim_player:
		anim_player.stop()

func on_jump() -> void:
	if melon_boy_mesh and melon_boy_mesh.visible:
		melon_boy_mesh.position.y = 0.22
		melon_boy_mesh.scale = Vector3(0.9, 1.18, 0.9)
	var admin_m = player.get_node_or_null("Model/AdminModel") if player else null
	if admin_m and admin_m.visible:
		admin_m.position.y = 0.22
		admin_m.scale = Vector3(0.92, 1.15, 0.92)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	
	var horizontal_vel = Vector2(player.velocity.x, player.velocity.z)
	var speed = horizontal_vel.length()
	is_moving = speed > 0.15
	
	# Turning lean / banking (applies dynamically to model root)
	var current_rot_y = player.rotation.y
	var rot_delta = wrapf(current_rot_y - last_rot_y, -PI, PI)
	last_rot_y = current_rot_y
	target_tilt_z = clamp(-rot_delta * 4.0, deg_to_rad(-14), deg_to_rad(14))
	
	if model_root:
		model_root.rotation.z = lerp_angle(model_root.rotation.z, target_tilt_z, 10.0 * delta)
	
	var admin_node = player.get_node_or_null("Model/AdminModel") if player else null
	if admin_node and admin_node.visible:
		_animate_admin_model(delta, speed, admin_node)
	elif melon_boy_mesh and melon_boy_mesh.visible:
		_animate_melon_boy(delta, speed)
	elif melon_boy_mesh and not melon_boy_mesh.visible:
		_animate_legacy_rig(delta, speed)

func _animate_admin_model(delta: float, speed: float, m: Node3D) -> void:
	if m.has_method("play_anim"):
		if is_moving and player.is_on_floor():
			m.play_anim("run")
		elif player.is_firing:
			m.play_anim("shoot")
		else:
			m.play_anim("idle")
	
	if is_moving and player.is_on_floor():
		walk_cycle += delta * speed * 2.8
		var stride_bounce = abs(sin(walk_cycle)) * 0.16
		m.position.y = stride_bounce
		m.rotation.x = lerp_angle(m.rotation.x, deg_to_rad(-12.0), 12.0 * delta)
		var swagger = sin(walk_cycle * 0.5) * deg_to_rad(8.0)
		m.rotation.z = swagger + target_tilt_z
	elif not player.is_on_floor():
		m.position.y = lerp(m.position.y, 0.18, 10.0 * delta)
		m.rotation.x = lerp_angle(m.rotation.x, deg_to_rad(-10.0), 10.0 * delta)
	else:
		m.position.y = lerp(m.position.y, 0.0, 8.0 * delta)
		m.rotation.x = lerp_angle(m.rotation.x, 0.0, 8.0 * delta)
		m.rotation.z = lerp_angle(m.rotation.z, target_tilt_z, 8.0 * delta)

func _animate_melon_boy(delta: float, speed: float) -> void:
	if not melon_boy_mesh:
		return
	
	if is_moving and player.is_on_floor():
		walk_cycle += delta * speed * 2.8
		
		# 1. Pronounced footstep vertical bounce (0.16m per step!)
		var stride_bounce = abs(sin(walk_cycle)) * 0.16
		melon_boy_mesh.position.y = stride_bounce
		
		# 2. Dynamic forward sprint lean (-14 degrees forward!)
		melon_boy_mesh.rotation.x = lerp_angle(melon_boy_mesh.rotation.x, deg_to_rad(-14.0), 12.0 * delta)
		
		# 3. Dynamic hip waddle / swagger (±9 degrees side-to-side!)
		var swagger = sin(walk_cycle * 0.5) * deg_to_rad(9.0)
		melon_boy_mesh.rotation.z = swagger + target_tilt_z
		
		# 4. Athletic squash & stretch impact on foot landing!
		var squash = 1.0 - abs(sin(walk_cycle)) * 0.08
		melon_boy_mesh.scale = Vector3(1.0 + (1.0 - squash) * 0.5, squash, 1.0 + (1.0 - squash) * 0.5)
	elif not player.is_on_floor():
		# Airborne jump suspension
		melon_boy_mesh.position.y = lerp(melon_boy_mesh.position.y, 0.18, 10.0 * delta)
		melon_boy_mesh.rotation.x = lerp_angle(melon_boy_mesh.rotation.x, deg_to_rad(-10.0), 10.0 * delta)
		melon_boy_mesh.scale = melon_boy_mesh.scale.lerp(Vector3(0.92, 1.15, 0.92), 10.0 * delta)
	else:
		# Standing idle: gentle breathing squash & stretch
		walk_cycle += delta * 2.2
		var idle_breath = sin(walk_cycle) * 0.035
		melon_boy_mesh.position.y = lerp(melon_boy_mesh.position.y, idle_breath, 8.0 * delta)
		melon_boy_mesh.rotation.x = lerp_angle(melon_boy_mesh.rotation.x, 0.0, 8.0 * delta)
		melon_boy_mesh.rotation.z = lerp_angle(melon_boy_mesh.rotation.z, 0.0, 8.0 * delta)
		melon_boy_mesh.scale = melon_boy_mesh.scale.lerp(Vector3(1.0, 1.0 + sin(walk_cycle) * 0.025, 1.0), 8.0 * delta)

func _animate_legacy_rig(delta: float, speed: float) -> void:
	if leaf_sprout:
		var leaf_wiggle = sin(walk_cycle * 2.5) * deg_to_rad(15) if is_moving else sin(walk_cycle) * deg_to_rad(5)
		leaf_sprout.rotation.z = leaf_wiggle
		leaf_sprout.rotation.x = cos(walk_cycle * 2.0) * deg_to_rad(8)
	
	if is_moving and player.is_on_floor():
		walk_cycle += delta * speed * 2.5
		var leg_angle = sin(walk_cycle) * deg_to_rad(38)
		
		if left_leg: left_leg.rotation.x = leg_angle
		if right_leg: right_leg.rotation.x = -leg_angle
		
		# Tactical 2-handed weapon holding while running:
		if right_arm:
			var fire_kick = randf_range(-0.04, 0.04) if player.is_firing else 0.0
			right_arm.rotation.x = deg_to_rad(-60) + sin(walk_cycle) * 0.04 + fire_kick
			right_arm.rotation.y = deg_to_rad(-12)
		if left_arm:
			left_arm.rotation.x = deg_to_rad(-45) + sin(walk_cycle) * 0.03
			left_arm.rotation.y = deg_to_rad(28)
		if body_mesh:
			body_mesh.position.y = 0.75 + abs(sin(walk_cycle)) * 0.07
	else:
		walk_cycle += delta * 2.2
		if left_leg: left_leg.rotation.x = lerp_angle(left_leg.rotation.x, 0, 10.0 * delta)
		if right_leg: right_leg.rotation.x = lerp_angle(right_leg.rotation.x, 0, 10.0 * delta)
		
		# Firm tactical weapon grip while standing idle:
		if right_arm:
			var fire_kick = randf_range(-0.04, 0.04) if player.is_firing else 0.0
			right_arm.rotation.x = lerp_angle(right_arm.rotation.x, deg_to_rad(-60) + fire_kick, 10.0 * delta)
			right_arm.rotation.y = lerp_angle(right_arm.rotation.y, deg_to_rad(-12), 10.0 * delta)
		if left_arm:
			left_arm.rotation.x = lerp_angle(left_arm.rotation.x, deg_to_rad(-45), 10.0 * delta)
			left_arm.rotation.y = lerp_angle(left_arm.rotation.y, deg_to_rad(28), 10.0 * delta)
		if body_mesh:
			body_mesh.position.y = lerp(body_mesh.position.y, 0.75 + sin(walk_cycle) * 0.02, 10.0 * delta)
	
	if not player.is_on_floor():
		if left_leg: left_leg.rotation.x = deg_to_rad(-26)
		if right_leg: right_leg.rotation.x = deg_to_rad(22)
		if body_mesh: body_mesh.position.y = 0.88
