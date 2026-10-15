extends Node3D
class_name BuildingSystem

# BuildingSystem Script (res://scripts/building_system.gd)
# Handles 3D Fortnite/Rust-style base building with preview hologram and multiplayer sync.

signal build_mode_toggled(is_building: bool)
signal structure_selected(type_name: String, cost: int)
signal materials_changed(current: int)

enum StructureType {
	WALL = 0,
	RAMP = 1,
	TURRET = 2
}

var current_type: StructureType = StructureType.WALL
var is_build_mode: bool = false
var materials: int = 250 # Nano-materials for building

const COSTS: Dictionary = {
	StructureType.WALL: 30,
	StructureType.RAMP: 25,
	StructureType.TURRET: 60
}

var wall_scene = preload("res://scenes/structure_wall.tscn")
var ramp_scene = preload("res://scenes/structure_ramp.tscn")
var turret_scene = preload("res://scenes/structure_turret.tscn")

@onready var preview_mesh: MeshInstance3D = $PreviewMesh
var player_ref: Node3D = null

func _ready() -> void:
	if preview_mesh:
		preview_mesh.visible = false
	player_ref = get_parent()

func toggle_build_mode() -> bool:
	is_build_mode = !is_build_mode
	if preview_mesh:
		preview_mesh.visible = is_build_mode
		_update_preview_mesh()
	build_mode_toggled.emit(is_build_mode)
	structure_selected.emit(_get_current_type_name(), COSTS[current_type])
	return is_build_mode

func select_structure(type_idx: int) -> void:
	current_type = type_idx as StructureType
	_update_preview_mesh()
	structure_selected.emit(_get_current_type_name(), COSTS[current_type])

func _get_current_type_name() -> String:
	match current_type:
		StructureType.WALL: return "Defense Wall (جدار)"
		StructureType.RAMP: return "Tactical Ramp (سلم)"
		StructureType.TURRET: return "Auto-Turret (برج)"
	return "Wall"

func _update_preview_mesh() -> void:
	if not preview_mesh:
		return
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 1, 0.8, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0, 1, 0.8)
	mat.emission_energy_multiplier = 2.0
	
	match current_type:
		StructureType.WALL:
			var m = BoxMesh.new()
			m.size = Vector3(4.5, 3.2, 0.4)
			preview_mesh.mesh = m
			preview_mesh.rotation = Vector3.ZERO
		StructureType.RAMP:
			var m = BoxMesh.new()
			m.size = Vector3(3.8, 0.35, 5.5)
			preview_mesh.mesh = m
			preview_mesh.rotation = Vector3(deg_to_rad(-30), 0, 0)
		StructureType.TURRET:
			var m = CylinderMesh.new()
			m.top_radius = 0.7
			m.bottom_radius = 1.0
			m.height = 1.8
			preview_mesh.mesh = m
			preview_mesh.rotation = Vector3.ZERO
	
	preview_mesh.material_override = mat

func _physics_process(_delta: float) -> void:
	if not is_build_mode or not is_instance_valid(player_ref):
		return
	
	# Position preview 4.5 meters in front of the player
	var forward = -player_ref.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	
	var target_pos = player_ref.global_position + (forward * 4.5)
	target_pos.y = player_ref.global_position.y
	
	# Snap to 1-meter grid
	target_pos.x = round(target_pos.x)
	target_pos.z = round(target_pos.z)
	
	global_position = target_pos
	rotation.y = player_ref.rotation.y

func try_place_structure() -> bool:
	if not is_build_mode:
		return false
	
	var cost = COSTS.get(current_type, 30)
	if materials < cost:
		return false
	
	materials -= cost
	materials_changed.emit(materials)
	
	var pos = global_position
	var rot_y = rotation.y
	var p_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	
	if multiplayer.has_multiplayer_peer():
		rpc("_sync_spawn_structure", int(current_type), pos, rot_y, p_id)
	else:
		_spawn_local_structure(current_type, pos, rot_y, p_id)
	
	return true

@rpc("any_peer", "call_local", "reliable")
func _sync_spawn_structure(type_idx: int, pos: Vector3, rot_y: float, p_id: int) -> void:
	_spawn_local_structure(type_idx as StructureType, pos, rot_y, p_id)

func _spawn_local_structure(st_type: StructureType, pos: Vector3, rot_y: float, p_id: int) -> void:
	var instance: Node3D = null
	match st_type:
		StructureType.WALL:
			instance = wall_scene.instantiate()
		StructureType.RAMP:
			instance = ramp_scene.instantiate()
		StructureType.TURRET:
			instance = turret_scene.instantiate()
	
	if instance:
		instance.global_position = pos
		instance.rotation.y = rot_y
		if instance is Structure:
			instance.builder_peer_id = p_id
		get_tree().current_scene.add_child(instance)

