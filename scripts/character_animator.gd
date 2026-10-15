extends Node
class_name CharacterAnimator

# CharacterAnimator Script (res://scripts/character_animator.gd)
# Supports full Run & Gun (moving and shooting simultaneously),
# head leaf wiggling, footstep stride cycles, and body lean.

@export var player: CharacterBody3D
@export var model_root: Node3D
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

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	
	var horizontal_vel = Vector2(player.velocity.x, player.velocity.z)
	var speed = horizontal_vel.length()
	is_moving = speed > 0.15
	
	# Turning lean/banking
	var current_rot_y = player.rotation.y
	var rot_delta = wrapf(current_rot_y - last_rot_y, -PI, PI)
	last_rot_y = current_rot_y
	target_tilt_z = clamp(-rot_delta * 4.0, deg_to_rad(-12), deg_to_rad(12))
	
	if model_root:
		model_root.rotation.z = lerp_angle(model_root.rotation.z, target_tilt_z, 10.0 * delta)
	
	# Leaf on head wiggle animation!
	if leaf_sprout:
		var leaf_wiggle = sin(walk_cycle * 2.5) * deg_to_rad(15) if is_moving else sin(walk_cycle) * deg_to_rad(5)
		leaf_sprout.rotation.z = leaf_wiggle
		leaf_sprout.rotation.x = cos(walk_cycle * 2.0) * deg_to_rad(8)
	
	if is_moving and player.is_on_floor():
		walk_cycle += delta * speed * 2.4
		var leg_angle = sin(walk_cycle) * deg_to_rad(38)
		var arm_angle = -sin(walk_cycle) * deg_to_rad(25)
		
		# Legs always walk at full stride regardless of firing! (Run & Gun)
		if left_leg:
			left_leg.rotation.x = leg_angle
		if right_leg:
			right_leg.rotation.x = -leg_angle
			
		if left_arm:
			left_arm.rotation.x = arm_angle
			
		# Right arm aiming / recoil while running
		if right_arm:
			if player.is_firing:
				# Aim weapon forward at target with slight firing vibration
				var recoil = randf_range(-0.04, 0.04)
				right_arm.rotation.x = deg_to_rad(-85) + recoil
			else:
				right_arm.rotation.x = -arm_angle * 0.4
			
		# Torso vertical bounce with footsteps
		if body_mesh:
			var bounce = abs(sin(walk_cycle)) * 0.07
			body_mesh.position.y = 0.75 + bounce
	else:
		# Standing still idle
		walk_cycle += delta * 2.2
		var idle_breath = sin(walk_cycle) * 0.02
		
		if left_leg:
			left_leg.rotation.x = lerp_angle(left_leg.rotation.x, 0, 10.0 * delta)
		if right_leg:
			right_leg.rotation.x = lerp_angle(right_leg.rotation.x, 0, 10.0 * delta)
		if left_arm:
			left_arm.rotation.x = lerp_angle(left_arm.rotation.x, 0, 10.0 * delta)
		
		if right_arm:
			if player.is_firing:
				right_arm.rotation.x = deg_to_rad(-85) + randf_range(-0.04, 0.04)
			else:
				right_arm.rotation.x = lerp_angle(right_arm.rotation.x, 0, 10.0 * delta)
			
		if body_mesh:
			body_mesh.position.y = lerp(body_mesh.position.y, 0.75 + idle_breath, 10.0 * delta)
			
	# In mid-air
	if not player.is_on_floor():
		if left_leg:
			left_leg.rotation.x = deg_to_rad(-22)
		if right_leg:
			right_leg.rotation.x = deg_to_rad(18)
		if body_mesh:
			body_mesh.position.y = 0.85
