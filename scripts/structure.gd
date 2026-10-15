extends StaticBody3D
class_name Structure

# Structure Script (res://scripts/structure.gd)
# Base class for player-built defense walls, ramps, and auto-turrets.

signal health_changed(current: float, max_val: float)

@export var structure_type: String = "Wall"
@export var max_hp: float = 300.0
var current_hp: float = 300.0
var builder_peer_id: int = 1

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("structures")
	current_hp = max_hp

func take_damage(amount: float, _attacker_id: int = 0) -> void:
	current_hp -= amount
	health_changed.emit(current_hp, max_hp)
	
	# Visual damage flash
	if mesh and mesh.material_override is StandardMaterial3D:
		var orig_color = mesh.material_override.albedo_color
		mesh.material_override.albedo_color = Color.RED
		get_tree().create_timer(0.08).timeout.connect(func():
			if is_instance_valid(mesh) and mesh.material_override:
				mesh.material_override.albedo_color = orig_color
		)
	
	if current_hp <= 0:
		_destroy()

func _destroy() -> void:
	# Small explosion / crumbling effect
	queue_free()
