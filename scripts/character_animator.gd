extends Node
class_name CharacterAnimator

# CharacterAnimator Script (res://scripts/character_animator.gd)
# Supports full Run & Gun (moving and shooting simultaneously),
# procedural locomotion, breathing, jumping, weapon recoil, and full animation support
# for the 3D Watermelon Boy model.

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

var walk_cycle: float = 0.0
var is_moving: bool = false
var last_rot_y: float = 0.0
var target_tilt_z: float = 0.0
var recoil_punch: float = 0.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	
	var horizontal_vel = Vector2(player.velocity.x, player.velocity.z)
	var speed = horizontal_vel.length()
	is_moving = speed > 0.15
	
	# Turning lean / banking
	var current_rot_y = player.rotation.y
	var rot_delta = wrapf(current_rot_y - last_rot_y, -PI, PI)
	last_rot_y = current_rot_y
	target_tilt_z = clamp(-rot_delta * 4.0, deg_to_rad(-14), deg_to_rad(14))
	
	if model_root:
		model_root.rotation.z = lerp_angle(model_root.rotation.z, target_tilt_z, 10.0 * delta)
	
	# Firing recoil recovery
	recoil_punch = lerp(recoil_punch, 0.0, 12.0 * delta)
	if player.is_firing:
		recoil_punch = 0.06
	
	# Animate the 3D Watermelon Boy Model
	if melon_boy_mesh and melon_boy_mesh.visible:
		_animate_3d_watermelon_boy(delta, speed)
	
	# Animate fallback rig if visible
	_animate_legacy_rig(delta, speed)

func _animate_3d_watermelon_boy(delta: float, speed: float) -> void:
	if not melon_boy_mesh:
		return
	
	if is_moving and player.is_on_floor():
		walk_cycle += delta * speed * 2.5
		
		# Footstep vertical stride bounce
		var stride_bounce = abs(sin(walk_cycle)) * 0.08
		melon_boy_mesh.position.y = stride_bounce
		
		# Forward sprint lean
		melon_boy_mesh.rotation.x = deg_to_rad(-8.0)
		
		# Lateral swagger / hip waddle
		var lateral_sway = sin(walk_cycle * 0.5) * deg_to_rad(4.5)
		melon_boy_mesh.rotation.z = lateral_sway + target_tilt_z
		
		# Normal scale
		melon_boy_mesh.scale.y = lerp(melon_boy_mesh.scale.y, 1.0, 10.0 * delta)
	else:
		# Standing still idle
		walk_cycle += delta * 2.2
		var idle_breath = sin(walk_cycle) * 0.02
		
		melon_boy_mesh.position.y = lerp(melon_boy_mesh.position.y, idle_breath, 8.0 * delta)
		melon_boy_mesh.scale.y = lerp(melon_boy_mesh.scale.y, 1.0 + sin(walk_cycle) * 0.015, 8.0 * delta)
		melon_boy_mesh.rotation.x = lerp_angle(melon_boy_mesh.rotation.x, 0.0, 8.0 * delta)
		melon_boy_mesh.rotation.z = lerp_angle(melon_boy_mesh.rotation.z, 0.0, 8.0 * delta)
	
	# Mid-air jump / fall
	if not player.is_on_floor():
		melon_boy_mesh.position.y = 0.06
		melon_boy_mesh.scale.y = 1.05
		melon_boy_mesh.rotation.x = deg_to_rad(-5.0)
	
	# Firing kickback & vibration
	if recoil_punch > 0.005:
		melon_boy_mesh.position.z = recoil_punch
		melon_boy_mesh.rotation.x += randf_range(-0.025, 0.025)
	else:
		melon_boy_mesh.position.z = lerp(melon_boy_mesh.position.z, 0.0, 12.0 * delta)

func _animate_legacy_rig(delta: float, speed: float) -> void:
	# Leaf on head wiggle animation!
	if leaf_sprout:
		var leaf_wiggle = sin(walk_cycle * 2.5) * deg_to_rad(15) if is_moving else sin(walk_cycle) * deg_to_rad(5)
		leaf_sprout.rotation.z = leaf_wiggle
		leaf_sprout.rotation.x = cos(walk_cycle * 2.0) * deg_to_rad(8)
	
	if is_moving and player.is_on_floor():
		var leg_angle = sin(walk_cycle) * deg_to_rad(38)
		var arm_angle = -sin(walk_cycle) * deg_to_rad(25)
		
		if left_leg: left_leg.rotation.x = leg_angle
		if right_leg: right_leg.rotation.x = -leg_angle
		if left_arm: left_arm.rotation.x = arm_angle
		if right_arm:
			if player.is_firing:
				right_arm.rotation.x = deg_to_rad(-85) + randf_range(-0.04, 0.04)
			else:
				right_arm.rotation.x = -arm_angle * 0.4
		if body_mesh:
			body_mesh.position.y = 0.75 + abs(sin(walk_cycle)) * 0.07
	else:
		if left_leg: left_leg.rotation.x = lerp_angle(left_leg.rotation.x, 0, 10.0 * delta)
		if right_leg: right_leg.rotation.x = lerp_angle(right_leg.rotation.x, 0, 10.0 * delta)
		if left_arm: left_arm.rotation.x = lerp_angle(left_arm.rotation.x, 0, 10.0 * delta)
		if right_arm:
			if player.is_firing:
				right_arm.rotation.x = deg_to_rad(-85) + randf_range(-0.04, 0.04)
			else:
				right_arm.rotation.x = lerp_angle(right_arm.rotation.x, 0, 10.0 * delta)
		if body_mesh:
			body_mesh.position.y = lerp(body_mesh.position.y, 0.75 + sin(walk_cycle) * 0.02, 10.0 * delta)
	
	if not player.is_on_floor():
		if left_leg: left_leg.rotation.x = deg_to_rad(-22)
		if right_leg: right_leg.rotation.x = deg_to_rad(18)
		if body_mesh: body_mesh.position.y = 0.85
