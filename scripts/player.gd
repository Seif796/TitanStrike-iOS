extends CharacterBody3D
class_name Player

# Player Script (res://scripts/player.gd)
# 3D Third-person / Action Player controller with mobile touch and keyboard support,
# co-op revive system, multiple classes, and weapon switching.

signal health_changed(current: float, max_val: float)
signal downed_state_changed(is_down: bool)
signal weapon_switched(weapon_node: Weapon)

@export var peer_id: int = 1
@export var class_id: int = 0

var max_hp: float = 100.0
var current_hp: float = 100.0
var move_speed: float = 6.0
var gravity: float = 18.0
var is_down: bool = false
var revive_timer: float = 0.0
const REVIVE_REQUIRED_TIME: float = 3.0

var primary_weapon: Weapon = null
var secondary_weapon: Weapon = null
var active_weapon: Weapon = null

# Input vectors (from touch joystick or keyboard)
var input_vector: Vector2 = Vector2.ZERO
var look_input: Vector2 = Vector2.ZERO
var is_firing: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var weapons_container: Node3D = $Model/Weapons
@onready var mesh_body: MeshInstance3D = $Model/BodyMesh
@onready var interact_area: Area3D = $InteractArea

var sync_position: Vector3 = Vector3.ZERO
var sync_rotation_y: float = 0.0

func _enter_tree() -> void:
	# Set authority based on node name (which matches peer_id)
	var id_from_name = name.to_int()
	if id_from_name > 0:
		peer_id = id_from_name
		set_multiplayer_authority(peer_id)

func _ready() -> void:
	add_to_group("players")
	apply_class_stats(class_id)
	
	if is_local_player():
		camera.current = true
	else:
		camera.current = false
	
	_setup_weapons()

func is_local_player() -> bool:
	return is_multiplayer_authority()

func apply_class_stats(c_id: int) -> void:
	class_id = c_id
	var data = GameManager.CLASSES.get(class_id, GameManager.CLASSES[0])
	max_hp = data["hp"]
	current_hp = max_hp
	move_speed = data["speed"]
	
	# Apply class visual color
	if mesh_body and mesh_body.material_override is StandardMaterial3D:
		mesh_body.material_override.albedo_color = data["color"]
	
	health_changed.emit(current_hp, max_hp)

func _setup_weapons() -> void:
	var weapons = weapons_container.get_children()
	if weapons.size() > 0:
		primary_weapon = weapons[0] as Weapon
		primary_weapon.owner_peer_id = peer_id
	if weapons.size() > 1:
		secondary_weapon = weapons[1] as Weapon
		secondary_weapon.owner_peer_id = peer_id
		secondary_weapon.visible = false
	
	active_weapon = primary_weapon
	if active_weapon:
		active_weapon.visible = true
		weapon_switched.emit(active_weapon)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if is_local_player():
		_handle_local_input(delta)
		_process_movement(delta)
		move_and_slide()
		
		# Send sync data to other players
		if multiplayer.has_multiplayer_peer():
			rpc("_sync_transform", global_position, rotation.y)
	else:
		# Interpolate other players' position
		global_position = global_position.lerp(sync_position, 15.0 * delta)
		rotation.y = lerp_angle(rotation.y, sync_rotation_y, 15.0 * delta)
		move_and_slide()

func _handle_local_input(_delta: float) -> void:
	if is_down:
		velocity.x = 0
		velocity.z = 0
		return
	
	# PC / Keyboard fallback
	if input_vector == Vector2.ZERO:
		var x = Input.get_action_raw_strength("move_right") - Input.get_action_raw_strength("move_left")
		var y = Input.get_action_raw_strength("move_backward") - Input.get_action_raw_strength("move_forward")
		input_vector = Vector2(x, y).normalized()
	
	# Aim / Camera rotation with mouse or touch trackpad
	if look_input != Vector2.ZERO:
		rotate_y(-look_input.x)
		if camera_pivot:
			camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - look_input.y, deg_to_rad(-60), deg_to_rad(45))
		look_input = Vector2.ZERO
	
	# Firing
	if Input.is_action_pressed("fire") or is_firing:
		try_fire()
	
	# Reloading
	if Input.is_action_just_pressed("reload"):
		reload_active_weapon()
	
	# Switching weapons
	if Input.is_action_just_pressed("switch_weapon"):
		switch_weapon()
	
	# Revive nearby teammate
	if Input.is_action_pressed("interact"):
		_try_revive_teammate()

func _process_movement(_delta: float) -> void:
	if is_down:
		return
	
	var cam_forward = -camera.global_transform.basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()
	var cam_right = camera.global_transform.basis.x
	cam_right.y = 0
	cam_right = cam_right.normalized()
	
	var move_dir = (cam_right * input_vector.x + cam_forward * -input_vector.y).normalized()
	if move_dir.length() > 0.1:
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
		
		# Rotate body towards movement or aim
		var target_rot = atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 0.2)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

func try_fire() -> void:
	if is_down or not active_weapon:
		return
	
	var aim_point = _get_aim_target()
	var shot_fired = active_weapon.try_shoot(aim_point)
	if shot_fired and multiplayer.has_multiplayer_peer():
		rpc("_sync_shoot", aim_point)

func _get_aim_target() -> Vector3:
	var viewport = get_viewport()
	var center = viewport.get_visible_rect().size / 2.0
	var from = camera.project_ray_origin(center)
	var to = from + camera.project_ray_normal(center) * 100.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	if result:
		return result.position
	return to

func switch_weapon() -> void:
	if is_down:
		return
	if active_weapon == primary_weapon and secondary_weapon:
		active_weapon.visible = false
		active_weapon = secondary_weapon
		active_weapon.visible = true
	elif primary_weapon:
		if secondary_weapon:
			secondary_weapon.visible = false
		active_weapon = primary_weapon
		active_weapon.visible = true
	
	weapon_switched.emit(active_weapon)

func reload_active_weapon() -> void:
	if active_weapon and not is_down:
		active_weapon.start_reload()

# --- HEALTH, DAMAGE & CO-OP REVIVE ---

func take_damage(amount: float) -> void:
	if is_down:
		return
	
	if is_local_player():
		_apply_damage(amount)
		if multiplayer.has_multiplayer_peer():
			rpc("_sync_damage", amount)

@rpc("any_peer", "call_local", "reliable")
func _sync_damage(amount: float) -> void:
	if not is_local_player():
		_apply_damage(amount)

func _apply_damage(amount: float) -> void:
	current_hp = max(0, current_hp - amount)
	health_changed.emit(current_hp, max_hp)
	
	if current_hp <= 0 and not is_down:
		_enter_downed_state()

func _enter_downed_state() -> void:
	is_down = true
	downed_state_changed.emit(true)
	# Check if all players are down -> Defeat
	GameManager.check_all_players_down()

func revive() -> void:
	is_down = false
	current_hp = max_hp * 0.5 # Revive with 50% health
	health_changed.emit(current_hp, max_hp)
	downed_state_changed.emit(false)

func _try_revive_teammate() -> void:
	for body in interact_area.get_overlapping_bodies():
		if body is Player and body != self and body.is_down:
			body.rpc("revive")
			break

func is_downed() -> bool:
	return is_down

# --- RPC SYNC ---

@rpc("unreliable")
func _sync_transform(pos: Vector3, rot_y: float) -> void:
	sync_position = pos
	sync_rotation_y = rot_y

@rpc("any_peer", "call_remote")
func _sync_shoot(target: Vector3) -> void:
	if active_weapon:
		active_weapon._spawn_shot_visuals(target)

