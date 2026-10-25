extends Node3D
class_name CharacterPreview

# CharacterPreview Script (res://scripts/character_preview.gd)
# Rotates 3D Character and updates textures/colors between Melon Boy (3D model), Berry Striker, Citrus Tank, and Admin.

@onready var melon_model: Node3D = $Model/MelonModel
@onready var admin_model: Node3D = $Model/AdminModel
@onready var spider_model: Node3D = get_node_or_null("Model/SpiderModel")
@onready var strawberry_model: Node3D = get_node_or_null("Model/StrawberryModel")
@onready var citrus_model: Node3D = get_node_or_null("Model/CitrusModel")
@onready var rim_light: OmniLight3D = get_node_or_null("RimLight")

var melon_tex = preload("res://assets/watermelon_pattern.svg")
var berry_tex = preload("res://assets/strawberry_pattern.svg")
var citrus_tex = preload("res://assets/citrus_pattern.svg")

var rot_speed: float = 0.85

func _physics_process(delta: float) -> void:
	$Model.rotation.y += rot_speed * delta

func update_class_visual(class_id: int) -> void:
	if rim_light:
		match class_id:
			0: rim_light.light_color = Color(0.2, 0.95, 0.3)
			1: rim_light.light_color = Color(1.0, 0.2, 0.45)
			2: rim_light.light_color = Color(1.0, 0.6, 0.1)
			3: rim_light.light_color = Color(1.0, 0.85, 0.15)
			4: rim_light.light_color = Color(1.0, 0.15, 0.25)
			_: rim_light.light_color = Color(0.2, 0.9, 0.3)

	if spider_model: spider_model.visible = (class_id == 4)
	if admin_model: admin_model.visible = (class_id == 3)
	if citrus_model: citrus_model.visible = (class_id == 2)
	if strawberry_model: strawberry_model.visible = (class_id == 1)
	if melon_model: melon_model.visible = (class_id == 0)
	# Clean hero display
	# Ensure playing idle anim
	var active_m = [melon_model, strawberry_model, citrus_model, admin_model, spider_model][class_id] if class_id < 5 else melon_model
	if active_m and active_m.has_method('play_anim'):
		active_m.play_anim('idle')
