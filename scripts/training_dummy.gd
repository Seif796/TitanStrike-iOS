extends CharacterBody3D
class_name TrainingDummy

# TrainingDummy Script (res://scripts/training_dummy.gd)
# Target practice bot for testing all weapons, damage calculations, and hero capabilities.

@onready var label_3d: Label3D = $Label3D
@onready var damage_popup: Label3D = $DamagePopup
@onready var model_mesh: CSGBox3D = $Model/Body

var max_hp: float = 1000.0
var current_hp: float = 1000.0
var total_damage_taken: float = 0.0
var recent_hits: Array[float] = []
var popup_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("damageable")
	_update_label()
	if damage_popup:
		damage_popup.visible = false

func _process(delta: float) -> void:
	if popup_timer > 0.0:
		popup_timer -= delta
		if damage_popup:
			damage_popup.position.y += delta * 0.8
		if popup_timer <= 0.0 and damage_popup:
			damage_popup.visible = false
	
	# Slowly regenerate HP
	if current_hp < max_hp:
		current_hp = min(max_hp, current_hp + (150.0 * delta))
		_update_label()

func take_damage(amount: float, _shooter_id: int = 1) -> void:
	current_hp = max(1.0, current_hp - amount)
	total_damage_taken += amount
	
	# Show floating damage
	if damage_popup:
		damage_popup.visible = true
		damage_popup.position = Vector3(0, 2.8, 0)
		damage_popup.text = "-%.0f DMG!" % amount
		popup_timer = 1.2
	
	# Small hit flash & wobble
	if model_mesh:
		var tw = create_tween()
		tw.tween_property(model_mesh, "scale", Vector3(1.15, 0.85, 1.15), 0.06)
		tw.tween_property(model_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.12)
	
	_update_label()

func _update_label() -> void:
	if label_3d:
		label_3d.text = "🎯 روبوت التدريب (Training Dummy)\nHP: %.0f / %.0f | Total Dmg: %.0f" % [current_hp, max_hp, total_damage_taken]

