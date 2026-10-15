extends Node
class_name CharacterAnimator

# CharacterAnimator Script (res://scripts/character_animator.gd)
# Seamlessly coordinates AnimationPlayer (idle, run, jump, shoot)
# and procedural additive motion (turning banking, weapon recoil)
# for both the 3D Watermelon Boy model and legacy rigs.

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
	if anim_player and anim_player.has_animation("idle"):
		anim_player.play("idle")

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
	
	# Coordinate AnimationPlayer states
	if anim_player:
		if not player.is_on_floor():
			if anim_player.has_animation("jump") and anim_player.current_animation != "jump":
				anim_player.play("jump", 0.15)
		elif is_moving:
			if anim_player.current_animation != "run":
				anim_player.play("run", 0.15)
			# Scale animation speed with movement speed
			anim_player.speed_scale = clamp(speed / 6.5, 0.75, 1.6)
		else:
			anim_player.speed_scale = 1.0
			if anim_player.current_animation != "idle" and anim_player.current_animation != "shoot":
				anim_player.play("idle", 0.25)
	
	# Fallback legacy rig if Melon Boy 3D is hidden (for classes 1 and 2)
	if melon_boy_mesh and not melon_boy_mesh.visible:
		_animate_legacy_rig(delta, speed)

func _animate_legacy_rig(delta: float, speed: float) -> void:
	if leaf_sprout:
		var leaf_wiggle = sin(walk_cycle * 2.5) * deg_to_rad(15) if is_moving else sin(walk_cycle) * deg_to_rad(5)
		leaf_sprout.rotation.z = leaf_wiggle
		leaf_sprout.rotation.x = cos(walk_cycle * 2.0) * deg_to_rad(8)
	
	if is_moving and player.is_on_floor():
		walk_cycle += delta * speed * 2.5
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
		walk_cycle += delta * 2.2
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
