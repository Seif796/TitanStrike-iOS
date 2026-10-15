extends Node3D
class_name CharacterPreview

# CharacterPreview Script (res://scripts/character_preview.gd)
# Rotates 3D Character and updates textures/colors between Melon Boy, Berry Striker, and Citrus Tank.

@onready var head_mesh: MeshInstance3D = $Model/Head/HeadMesh
@onready var chest_mesh: MeshInstance3D = $Model/ChestPlate
@onready var leg_l: MeshInstance3D = $Model/LeftLeg
@onready var leg_r: MeshInstance3D = $Model/RightLeg
@onready var arm_l: MeshInstance3D = $Model/LeftArm
@onready var arm_r: MeshInstance3D = $Model/RightArm
@onready var leaf_sprout: Node3D = $Model/Head/LeafSprout

var melon_tex = preload("res://assets/watermelon_pattern.svg")
var berry_tex = preload("res://assets/strawberry_pattern.svg")
var citrus_tex = preload("res://assets/citrus_pattern.svg")

var rot_speed: float = 0.85

func _physics_process(delta: float) -> void:
	$Model.rotation.y += rot_speed * delta

func update_class_visual(class_id: int) -> void:
	var mat = StandardMaterial3D.new()
	if class_id == 3:
		mat.albedo_color = Color(1.0, 0.85, 0.15)
		mat.metallic = 0.95
		mat.roughness = 0.15
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.8, 0.1)
		mat.emission_energy_multiplier = 3.0
	else:
		var target_tex: Texture2D = melon_tex
		match class_id:
			0: target_tex = melon_tex
			1: target_tex = berry_tex
			2: target_tex = citrus_tex
		
		mat.albedo_texture = target_tex
		mat.uv1_scale = Vector3(2.5, 2.5, 2.5)
		mat.roughness = 0.35
	
	if head_mesh: head_mesh.material_override = mat
	if chest_mesh: chest_mesh.material_override = mat
	if leg_l: leg_l.material_override = mat
	if leg_r: leg_r.material_override = mat
	if arm_l: arm_l.material_override = mat
	if arm_r: arm_r.material_override = mat
	
	if leaf_sprout:
		leaf_sprout.visible = (class_id == 0)
