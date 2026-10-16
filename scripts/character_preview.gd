extends Node3D
class_name CharacterPreview

# CharacterPreview Script (res://scripts/character_preview.gd)
# Rotates 3D Character and updates textures/colors between Melon Boy (3D model), Berry Striker, Citrus Tank, and Admin.

@onready var melon_boy_3d: Node3D = $Model/WatermelonBoyMesh
@onready var admin_model: Node3D = $Model/AdminModel
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
var melon_shader = preload("res://shaders/watermelon_boy.gdshader")

var rot_speed: float = 0.85

func _physics_process(delta: float) -> void:
	$Model.rotation.y += rot_speed * delta

func update_class_visual(class_id: int) -> void:
	if class_id == 3:
		if admin_model: admin_model.visible = true
		if melon_boy_3d: melon_boy_3d.visible = false
		_set_legacy_preview_visible(false)
		return
	else:
		if admin_model: admin_model.visible = false
	
	if melon_boy_3d:
		if class_id == 0:
			melon_boy_3d.visible = true
			_set_legacy_preview_visible(false)
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
			return
		else:
			melon_boy_3d.visible = false
			_set_legacy_preview_visible(true)
	
	var target_tex: Texture2D = berry_tex if class_id == 1 else citrus_tex
	var mat = StandardMaterial3D.new()
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

func _set_legacy_preview_visible(v: bool) -> void:
	if head_mesh and head_mesh.get_parent(): head_mesh.get_parent().visible = v
	if chest_mesh: chest_mesh.visible = v
	if leg_l: leg_l.visible = v
	if leg_r: leg_r.visible = v
	if arm_l: arm_l.visible = v
	if arm_r: arm_r.visible = v
