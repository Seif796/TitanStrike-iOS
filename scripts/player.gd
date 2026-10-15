extends CharacterBody3D
class_name Player

# Player Script (res://scripts/player.gd)
# Features strict button-only firing (camera swipes never shoot),
# Run & Gun simultaneous move+shoot, Melon Boy textures, building, and revive.

signal health_changed(current: float, max_val: float)
signal downed_state_changed(is_down: bool)
signal weapon_switched(weapon_node: Weapon)

@export var peer_id: int = 1
@export var class_id: int = 0

var max_hp: float = 130.0
var current_hp: float = 130.0
var move_speed: float = 7.5
var jump_velocity: float = 8.5
var gravity: float = 18.0
var is_down: bool = false
var revive_timer: float = 0.0

var primary_weapon: Weapon = null
var secondary_weapon: Weapon = null
var active_weapon: Weapon = null

# Input vectors
var input_vector: Vector2 = Vector2.ZERO
var look_input: Vector2 = Vector2.ZERO
var is_firing: bool = false

@onready var model: Node3D = $Model
@onready var melon_boy_3d: Node3D = $Model/WatermelonBoyMesh
@onready var head_mesh: MeshInstance3D = $Model/Head/HeadMesh
@onready var leaf_sprout: Node3D = $Model/Head/LeafSprout
@onready var chest_plate: MeshInstance3D = $Model/BodyMesh/ChestPlate
@onready var leg_l: MeshInstance3D = $Model/LeftLeg/LegMesh
@onready var leg_r: MeshInstance3D = $Model/RightLeg/LegMesh
@onready var arm_l: MeshInstance3D = $Model/LeftArm/ArmMesh
@onready var arm_r: MeshInstance3D = $Model/RightArm/ArmMesh

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var weapons_container: Node3D = $Model/Weapons
@onready var interact_area: Area3D = $InteractArea
@onready var building_system: BuildingSystem = $BuildingSystem

var melon_tex = preload("res://assets/watermelon_pattern.svg")
var berry_tex = preload("res://assets/strawberry_pattern.svg")
var citrus_tex = preload("res://assets/citrus_pattern.svg")
var melon_shader = preload("res://shaders/watermelon_boy.gdshader")

var sync_position: Vector3 = Vector3.ZERO
var sync_rotation_y: float = 0.0

func _enter_tree() -> void:
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
		if building_system:
			building_system.set_process(false)
			building_system.set_physics_process(false)
	
	_setup_weapons()

func is_local_player() -> bool:
	return is_multiplayer_authority()

func apply_class_stats(c_id: int) -> void:
	class_id = c_id
	var data = GameManager.CLASSES.get(class_id, GameManager.CLASSES[0])
	max_hp = data["hp"]
	current_hp = max_hp
	move_speed = data["speed"]
	
	if melon_boy_3d:
		if class_id == 0:
			# Authentic 3D Watermelon Boy model with baked vertex colors & strictly opaque shader!
			melon_boy_3d.visible = true
			_set_legacy_rig_visible(false)
			var mesh_inst = melon_boy_3d.get_node_or_null("WatermelonBoy")
			if mesh_inst and mesh_inst is MeshInstance3D:
				mesh_inst.rotation.y = PI
				var sh_mat = ShaderMaterial.new()
				sh_mat.shader = melon_shader
				sh_mat.set_shader_parameter("base_tint", Color(1.0, 1.0, 1.0, 1.0))
				sh_mat.set_shader_parameter("use_vertex_color", true)
				sh_mat.set_shader_parameter("roughness", 0.35)
				sh_mat.set_shader_parameter("metallic", 0.05)
				mesh_inst.material_override = sh_mat
		elif class_id == 3:
			# 3D Model coated in glowing Golden Cyber Admin armor (500 HP)!
			melon_boy_3d.visible = true
			_set_legacy_rig_visible(false)
			var mesh_inst = melon_boy_3d.get_node_or_null("WatermelonBoy")
			if mesh_inst and mesh_inst is MeshInstance3D:
				mesh_inst.rotation.y = PI
				var sh_mat = ShaderMaterial.new()
				sh_mat.shader = melon_shader
				sh_mat.set_shader_parameter("base_tint", Color(1.0, 0.85, 0.15, 1.0))
				sh_mat.set_shader_parameter("use_vertex_color", false)
				sh_mat.set_shader_parameter("roughness", 0.15)
				sh_mat.set_shader_parameter("metallic", 0.95)
				sh_mat.set_shader_parameter("emission_color", Color(1.0, 0.75, 0.1, 1.0))
				sh_mat.set_shader_parameter("emission_energy", 3.0)
				mesh_inst.material_override = sh_mat
		else:
			# Berry Striker or Citrus Tank
			melon_boy_3d.visible = false
			_set_legacy_rig_visible(true)
			var target_tex = berry_tex if class_id == 1 else citrus_tex
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = target_tex
			mat.uv1_scale = Vector3(2.5, 2.5, 2.5)
			mat.roughness = 0.35
			if head_mesh: head_mesh.material_override = mat
			if chest_plate: chest_plate.material_override = mat
			if leg_l: leg_l.material_override = mat
			if leg_r: leg_r.material_override = mat
			if arm_l: arm_l.material_override = mat
			if arm_r: arm_r.material_override = mat
	else:
		_set_legacy_rig_visible(true)
	
	if leaf_sprout:
		leaf_sprout.visible = (class_id == 0)
	
	health_changed.emit(current_hp, max_hp)

func _set_legacy_rig_visible(v: bool) -> void:
	if head_mesh and head_mesh.get_parent(): head_mesh.get_parent().visible = v
	if chest_plate and chest_plate.get_parent(): chest_plate.get_parent().visible = v
	if leg_l and leg_l.get_parent(): leg_l.get_parent().visible = v
	if leg_r and leg_r.get_parent(): leg_r.get_parent().visible = v
	if arm_l and arm_l.get_parent(): arm_l.get_parent().visible = v
	if arm_r and arm_r.get_parent(): arm_r.get_parent().visible = v

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
		_handle_camera_and_input(delta)
		_process_movement(delta)
		move_and_slide()
		
		if multiplayer.has_multiplayer_peer():
			rpc("_sync_transform", global_position, rotation.y, is_firing)
	else:
		global_position = global_position.lerp(sync_position, 15.0 * delta)
		rotation.y = lerp_angle(rotation.y, sync_rotation_y, 15.0 * delta)
		move_and_slide()

func _handle_camera_and_input(_delta: float) -> void:
	if is_down:
		velocity.x = 0
		velocity.z = 0
		return
	
	# Smooth Camera swipe look
	if look_input != Vector2.ZERO:
		rotate_y(-look_input.x)
		if camera_pivot:
			camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - look_input.y, deg_to_rad(-60), deg_to_rad(45))
		look_input = Vector2.ZERO
	
	# PC Keyboard fallback for WASD
	if input_vector == Vector2.ZERO and not OS.has_feature("mobile"):
		var x = Input.get_action_raw_strength("move_right") - Input.get_action_raw_strength("move_left")
		var y = Input.get_action_raw_strength("move_backward") - Input.get_action_raw_strength("move_forward")
		input_vector = Vector2(x, y).normalized()
	
	# STRICT BUTTON-ONLY FIRING:
	# On mobile, ONLY fire if the on-screen FIRE button is pressed (is_firing == true)!
	# Swiping the camera will NEVER trigger shooting.
	var should_fire = is_firing
	if not OS.has_feature("mobile") and Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		should_fire = true
	
	if should_fire and (not building_system or not building_system.is_build_mode):
		try_fire()
	
	if Input.is_action_just_pressed("reload"):
		reload_active_weapon()
	if Input.is_action_just_pressed("switch_weapon"):
		switch_weapon()
	if Input.is_action_just_pressed("toggle_build"):
		toggle_build_mode()
	if Input.is_action_pressed("interact"):
		_try_revive_teammate()
	if Input.is_action_just_pressed("jump"):
		jump()

func jump() -> void:
	if is_down:
		return
	if is_on_floor():
		velocity.y = jump_velocity
		var ca = get_node_or_null("CharacterAnimator")
		if ca and ca.has_method("on_jump"):
			ca.on_jump()

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
	
	if move_dir.length() > 0.05:
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
		
		# Smooth model alignment:
		if model:
			if is_firing:
				model.rotation.y = lerp_angle(model.rotation.y, 0.0, 0.35)
			else:
				var local_move_dir = global_transform.basis.inverse() * move_dir
				var target_model_rot = atan2(-local_move_dir.x, -local_move_dir.z)
				model.rotation.y = lerp_angle(model.rotation.y, target_model_rot, 0.25)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if model and is_firing:
			model.rotation.y = lerp_angle(model.rotation.y, 0.0, 0.35)

func try_fire() -> void:
	if is_down or not active_weapon or (building_system and building_system.is_build_mode):
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

func toggle_build_mode() -> bool:
	if not building_system or is_down:
		return false
	var is_building = building_system.toggle_build_mode()
	if active_weapon:
		active_weapon.visible = !is_building
	return is_building

func place_structure() -> void:
	if building_system and not is_down:
		building_system.try_place_structure()

func select_structure_type(idx: int) -> void:
	if building_system and not is_down:
		building_system.select_structure(idx)

func switch_weapon() -> void:
	if is_down or (building_system and building_system.is_build_mode):
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
	if active_weapon and not is_down and (not building_system or not building_system.is_build_mode):
		active_weapon.start_reload()

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
	GameManager.check_all_players_down()

func revive() -> void:
	is_down = false
	current_hp = max_hp * 0.6
	health_changed.emit(current_hp, max_hp)
	downed_state_changed.emit(false)

@rpc("call_local", "reliable")
func full_restore() -> void:
	is_down = false
	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)
	downed_state_changed.emit(false)
	if active_weapon:
		active_weapon.current_ammo = active_weapon.max_ammo
		active_weapon.is_reloading = false
		active_weapon.ammo_changed.emit(active_weapon.current_ammo, active_weapon.max_ammo, false)

func _try_revive_teammate() -> void:
	for body in interact_area.get_overlapping_bodies():
		if body is Player and body != self and body.is_down:
			body.rpc("revive")
			break

func is_downed() -> bool:
	return is_down

@rpc("unreliable")
func _sync_transform(pos: Vector3, rot_y: float, firing: bool = false) -> void:
	sync_position = pos
	sync_rotation_y = rot_y
	is_firing = firing

@rpc("any_peer", "call_remote")
func _sync_shoot(target: Vector3) -> void:
	if active_weapon:
		active_weapon._spawn_shot_visuals(target)
