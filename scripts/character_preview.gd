extends Node3D
class_name CharacterPreview

# CharacterPreview Script (res://scripts/character_preview.gd)
# Rotates the 3D character preview and updates armor color/mesh when a class is selected.

@onready var chest_mesh: MeshInstance3D = $Model/ChestPlate
@onready var core_light: OmniLight3D = $Model/ChestPlate/Reactor/CoreLight
@onready var weapon_mesh: MeshInstance3D = $Model/Weapon

var rot_speed: float = 0.8

func _physics_process(delta: float) -> void:
	$Model.rotation.y += rot_speed * delta

func update_class_visual(class_id: int) -> void:
	var c_data = GameManager.CLASSES.get(class_id, GameManager.CLASSES[0])
	var col: Color = c_data["color"]
	
	if chest_mesh and chest_mesh.material_override is StandardMaterial3D:
		chest_mesh.material_override.albedo_color = col
		chest_mesh.material_override.emission = col
	
	if core_light:
		core_light.light_color = col
