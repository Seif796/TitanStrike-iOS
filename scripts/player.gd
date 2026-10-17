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
@export var is_bot: bool = false

var max_hp: float = 130.0
var current_hp: float = 130.0
var move_speed: float = 7.5
var jump_velocity: float = 8.5
var gravity: float = 18.0
var is_down: bool = false
var revive_timer: float = 0.0
var bot_aim_target: Vector3 = Vector3.ZERO

var primary_weapon: Weapon = null
var secondary_weapon: Weapon = null
var active_weapon: Weapon = null

# Input vectors
var input_vector: Vector2 = Vector2.ZERO
var look_input: Vector2 = Vector2.ZERO
var is_firing: bool = false

@onready var model: Node3D = $Model
@onready var melon_model: Node3D = $Model/MelonModel
@onready var admin_model: Node3D = $Model/AdminModel
@onready var spider_model: Node3D = get_node_or_null("Model/SpiderModel")
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
@onready var overhead_health_bar: Node3D = get_node_or_null("OverheadHealthBar")

var melon_tex = preload("res://assets/watermelon_pattern.svg")
var berry_tex = preload("res://assets/strawberry_pattern.svg")
var citrus_tex = preload("res://assets/citrus_pattern.svg")
var melon_shader = preload("res://shaders/watermelon_boy.gdshader")

var sync_position: Vector3 = Vector3.ZERO
var sync_rotation_y: float = 0.0

# Network sync optimization (throttled to 20 ticks/sec to save mobile data & reduce lag)
var network_sync_timer: float = 0.0
const NETWORK_SYNC_INTERVAL: float = 0.05
var last_synced_pos: Vector3 = Vector3.ZERO
var last_synced_rot: float = 0.0

# Spectator camera
var spectate_target: Node3D = null
var default_cam_transform: Transform3D

func _enter_tree() -> void:
	var id_from_name = name.to_int()
	if id_from_name > 0:
		peer_id = id_from_name
		set_multiplayer_authority(peer_id)

func _ready() -> void:
	add_to_group("players")
	apply_class_stats(class_id)
	
	if overhead_health_bar:
		var hero_info = GameManager.CLASSES.get(class_id, GameManager.CLASSES[0])
		var display_name = hero_info.get("name", "Hero")
		if is_bot:
			display_name = "🤖 Bot Companion"
		elif NetworkManager.players.has(peer_id):
			var p_name = NetworkManager.players[peer_id].get("name", "")
			if not p_name.is_empty():
				display_name = "%s (%s)" % [p_name, hero_info.get("name", "")]
		overhead_health_bar.set_entity_name(display_name)
		overhead_health_bar.update_health(current_hp, max_hp)
		overhead_health_bar.set_downed(is_down)
		health_changed.connect(func(curr, max_v):
			if overhead_health_bar: overhead_health_bar.update_health(curr, max_v)
		)
		downed_state_changed.connect(func(down):
			if overhead_health_bar: overhead_health_bar.set_downed(down)
		)
	
	if is_bot:
		camera.current = false
		if building_system:
			building_system.set_process(false)
			building_system.set_physics_process(false)
	elif is_local_player():
		camera.current = true
		if camera:
			default_cam_transform = camera.transform
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
	
	if class_id == 4:
		# Dedicated 3D Chibi Spider-Hero Model (Oversized Hoodie, Spider Mask & Retro Sneakers)!
		if spider_model: spider_model.visible = true
		if admin_model: admin_model.visible = false
		if melon_model: melon_model.visible = false
		_set_legacy_rig_visible(false)
	elif class_id == 3:
		# Dedicated 3D Cyber Admin Model (Crown, Cyber Visor, Reactor Core & Gold Armor)!
		if spider_model: spider_model.visible = false
		if admin_model: admin_model.visible = true
		if melon_model: melon_model.visible = false
		_set_legacy_rig_visible(false)
	elif class_id == 0:
		if spider_model: spider_model.visible = false
		if admin_model: admin_model.visible = false
		if melon_model: melon_model.visible = true
		_set_legacy_rig_visible(false)
	else:
		if spider_model: spider_model.visible = false
		if admin_model: admin_model.visible = false
		if melon_model: melon_model.visible = false
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
	
	if is_bot:
		_process_movement(delta)
		if is_firing and (not building_system or not building_system.is_build_mode):
			try_fire()
		move_and_slide()
	elif is_local_player():
		if is_down:
			_update_spectator_camera(delta)
		else:
			_handle_camera_and_input(delta)
			_process_movement(delta)
			move_and_slide()
		
		# Low-bandwidth sync: throttled to 20Hz (saves ~65% mobile bandwidth)
		if multiplayer.has_multiplayer_peer():
			network_sync_timer += delta
			if network_sync_timer >= NETWORK_SYNC_INTERVAL:
				network_sync_timer = 0.0
				var pos_changed = global_position.distance_squared_to(last_synced_pos) > 0.001
				var rot_changed = abs(rotation.y - last_synced_rot) > 0.01
				if pos_changed or rot_changed or is_firing:
					last_synced_pos = global_position
					last_synced_rot = rotation.y
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
	
	var forward: Vector3
	var right: Vector3
	if is_bot or not camera:
		forward = -global_transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		right = global_transform.basis.x
		right.y = 0
		right = right.normalized()
	else:
		forward = -camera.global_transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		right = camera.global_transform.basis.x
		right.y = 0
		right = right.normalized()
	
	var move_dir = (right * input_vector.x + forward * -input_vector.y).normalized()
	
	if move_dir.length() > 0.05:
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
		
		# Smooth model alignment:
		if model:
			if is_firing or is_bot:
				model.rotation.y = lerp_angle(model.rotation.y, 0.0, 0.35)
			else:
				var local_move_dir = global_transform.basis.inverse() * move_dir
				var target_model_rot = atan2(-local_move_dir.x, -local_move_dir.z)
				model.rotation.y = lerp_angle(model.rotation.y, target_model_rot, 0.25)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if model and (is_firing or is_bot):
			model.rotation.y = lerp_angle(model.rotation.y, 0.0, 0.35)

func try_fire() -> void:
	if is_down or not active_weapon or (building_system and building_system.is_build_mode):
		return
	
	var aim_point = _get_aim_target()
	var shot_fired = active_weapon.try_shoot(aim_point)
	if shot_fired and multiplayer.has_multiplayer_peer():
		rpc("_sync_shoot", aim_point)

func _get_aim_target() -> Vector3:
	if is_bot and bot_aim_target != Vector3.ZERO:
		return bot_aim_target
	
	if not camera:
		return global_position - global_transform.basis.z * 30.0 + Vector3(0, 1.2, 0)
	
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
	
	if is_bot or is_local_player():
		_apply_damage(amount)
		if multiplayer.has_multiplayer_peer():
			rpc("_sync_damage", amount)

@rpc("any_peer", "call_local", "reliable")
func _sync_damage(amount: float) -> void:
	if not is_local_player() and not is_bot:
		_apply_damage(amount)

func _apply_damage(amount: float) -> void:
	current_hp = max(0, current_hp - amount)
	health_changed.emit(current_hp, max_hp)
	
	if current_hp <= 0 and not is_down:
		_enter_downed_state()

func _enter_downed_state() -> void:
	is_down = true
	downed_state_changed.emit(true)
	
	if is_local_player() and GameManager.selected_game_mode != GameManager.GameMode.PVP_DUEL:
		var teammate_name = ""
		for p in get_tree().get_nodes_in_group("players"):
			if p != self and is_instance_valid(p) and not p.is_down:
				teammate_name = p.name
				if NetworkManager.players.has(p.peer_id):
					teammate_name = NetworkManager.players[p.peer_id].get("name", teammate_name)
				elif p.is_bot:
					teammate_name = "🤖 Bot Companion"
				break
		
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_downed_alert"):
			hud.show_downed_alert(true, teammate_name)
	
	GameManager.check_all_players_down()

func _update_spectator_camera(delta: float) -> void:
	if spectate_target == null or not is_instance_valid(spectate_target) or (spectate_target.has_method("is_downed") and spectate_target.is_downed()):
		spectate_target = null
		for p in get_tree().get_nodes_in_group("players"):
			if p != self and is_instance_valid(p):
				if not p.has_method("is_downed") or not p.is_downed():
					spectate_target = p
					break
	
	if spectate_target and camera:
		var target_head = spectate_target.global_position + Vector3(0, 2.2, 0)
		var cam_offset = -spectate_target.global_transform.basis.z * 4.0 + Vector3(0, 1.8, 0)
		var desired_pos = spectate_target.global_position + cam_offset
		camera.global_position = camera.global_position.lerp(desired_pos, 7.0 * delta)
		camera.look_at(target_head, Vector3.UP)

@rpc("call_local", "reliable")
func revive() -> void:
	is_down = false
	spectate_target = null
	if camera and default_cam_transform != Transform3D():
		camera.transform = default_cam_transform
	current_hp = max_hp * 0.6
	health_changed.emit(current_hp, max_hp)
	downed_state_changed.emit(false)

@rpc("call_local", "reliable")
func full_restore() -> void:
	is_down = false
	spectate_target = null
	if camera and default_cam_transform != Transform3D():
		camera.transform = default_cam_transform
	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)
	downed_state_changed.emit(false)
	if active_weapon:
		active_weapon.current_ammo = active_weapon.max_ammo
		active_weapon.is_reloading = false
		active_weapon.ammo_changed.emit(active_weapon.current_ammo, active_weapon.max_ammo, false)

func _try_revive_teammate() -> void:
	if is_down:
		return
	
	# 1. First check if near any Revive Station terminal
	for station in get_tree().get_nodes_in_group("revive_stations"):
		if station.has_method("try_activate_from_player") and global_position.distance_to(station.global_position) < 5.5:
			if station.try_activate_from_player(self):
				return
	
	# 2. Check if near downed player body
	for body in interact_area.get_overlapping_bodies():
		if body is Player and body != self and body.is_down:
			if multiplayer.has_multiplayer_peer():
				body.rpc("revive")
			else:
				body.revive()
			break

func is_downed() -> bool:
	return is_down

@rpc("call_local", "reliable")
func notify_pvp_result(won: bool) -> void:
	if is_local_player():
		GameManager.trigger_game_over(won)

@rpc("unreliable")
func _sync_transform(pos: Vector3, rot_y: float, firing: bool = false) -> void:
	sync_position = pos
	sync_rotation_y = rot_y
	is_firing = firing

@rpc("any_peer", "call_remote")
func _sync_shoot(target: Vector3) -> void:
	if active_weapon:
		active_weapon._spawn_shot_visuals(target)
