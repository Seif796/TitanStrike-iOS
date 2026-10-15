extends Node
class_name CharacterAnimator

# CharacterAnimator Script (res://scripts/character_animator.gd)
# Dynamic procedural animation system for fluid walking/running leg cycles,
# body bobbing, turning bank/lean, weapon breathing, and jump/fall reaction.

@export var player: CharacterBody3D
@export var model_root: Node3D
@export var left_leg: Node3D
@export var right_leg: Node3D
@export var left_arm: Node3D
@export var right_arm: Node3D
@export var head: Node3D
@export var body_mesh: Node3D

var walk_cycle: float = 0.0
var walk_speed_mult: float = 12.0
var is_moving: bool = false
var last_rot_y: float = 0.0
var target_tilt_z: float = 0.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	
	var horizontal_vel = Vector2(player.velocity.x, player.velocity.z)
	var speed = horizontal_vel.length()
	is_moving = speed > 0.2
	
	# Turning lean/banking
	var current_rot_y = player.rotation.y
	var rot_delta = wrapf(current_rot_y - last_rot_y, -PI, PI)
	last_rot_y = current_rot_y
	target_tilt_z = clamp(-rot_delta * 4.0, deg_to_rad(-15), deg_to_rad(15))
	
	if model_root:
		model_root.rotation.z = lerp_angle(model_root.rotation.z, target_tilt_z, 10.0 * delta)
	
	if is_moving and player.is_on_floor():
		# Animate leg walking cycle
		walk_cycle += delta * speed * 2.2
		var leg_angle = sin(walk_cycle) * deg_to_rad(35)
		var arm_angle = -sin(walk_cycle) * deg_to_rad(25)
		
		if left_leg:
			left_leg.rotation.x = leg_angle
		if right_leg:
			right_leg.rotation.x = -leg_angle
			
		if left_arm:
			left_arm.rotation.x = arm_angle
		if right_arm and not player.is_firing:
			right_arm.rotation.x = -arm_angle * 0.4
			
		# Torso vertical bounce
		if body_mesh:
			var bounce = abs(sin(walk_cycle)) * 0.08
			body_mesh.position.y = 0.8 + bounce
	else:
		# Idle breathing
		walk_cycle += delta * 2.0
		var idle_breath = sin(walk_cycle) * 0.02
		
		if left_leg:
			left_leg.rotation.x = lerp_angle(left_leg.rotation.x, 0, 10.0 * delta)
		if right_leg:
			right_leg.rotation.x = lerp_angle(right_leg.rotation.x, 0, 10.0 * delta)
		if left_arm:
			left_arm.rotation.x = lerp_angle(left_arm.rotation.x, 0, 10.0 * delta)
			
		if body_mesh:
			body_mesh.position.y = lerp(body_mesh.position.y, 0.8 + idle_breath, 10.0 * delta)
			
	# Mid-air jump posture
	if not player.is_on_floor():
		if left_leg:
			left_leg.rotation.x = deg_to_rad(-25)
		if right_leg:
			right_leg.rotation.x = deg_to_rad(20)
		if body_mesh:
			body_mesh.position.y = 0.95
