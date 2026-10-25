extends CharacterBody3D
class_name TrainingDummy

# TrainingDummy Script (res://scripts/training_dummy.gd)
# Target practice bot for testing all weapons, damage calculations, and hero capabilities.

@export var dummy_title: String = "🎯 روبوت التدريب (Training Dummy)"
@export var is_moving: bool = false
@export var move_speed: float = 4.5
@export var move_distance: float = 12.0
@export var start_hp: float = 1000.0

@onready var label_3d: Label3D = $Label3D
@onready var damage_popup: Label3D = $DamagePopup
@onready var model_mesh: CSGBox3D = $Model/Body

var max_hp: float = 1000.0
var current_hp: float = 1000.0
var total_damage_taken: float = 0.0
var recent_hits: Array[Dictionary] = [] # [{time: float, dmg: float}]
var popup_timer: float = 0.0
var initial_pos_x: float = 0.0
var move_direction: float = 1.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("damageable")
	max_hp = start_hp
	current_hp = max_hp
	initial_pos_x = position.x
	_update_label()
	if damage_popup:
		damage_popup.visible = false

func _process(delta: float) -> void:
	# Floating damage popup animation
	if popup_timer > 0.0:
		popup_timer -= delta
		if damage_popup:
			damage_popup.position.y += delta * 0.9
		if popup_timer <= 0.0 and damage_popup:
			damage_popup.visible = false
	
	# Horizontal patrol movement if enabled
	if is_moving:
		position.x += move_direction * move_speed * delta
		if position.x > initial_pos_x + move_distance:
			position.x = initial_pos_x + move_distance
			move_direction = -1.0
		elif position.x < initial_pos_x - move_distance:
			position.x = initial_pos_x - move_distance
			move_direction = 1.0

	# Calculate DPS over the last 1.5 seconds
	var now = Time.get_ticks_msec() / 1000.0
	while recent_hits.size() > 0 and (now - recent_hits[0]["time"]) > 1.5:
		recent_hits.pop_front()
	
	# Slowly regenerate HP
	if current_hp < max_hp:
		current_hp = min(max_hp, current_hp + (200.0 * delta))
	
	_update_label()

func take_damage(amount: float, _shooter_id: int = 1) -> void:
	current_hp = max(1.0, current_hp - amount)
	total_damage_taken += amount
	
	var now = Time.get_ticks_msec() / 1000.0
	recent_hits.append({"time": now, "dmg": amount})
	
	# Show floating damage
	if damage_popup:
		damage_popup.visible = true
		damage_popup.position = Vector3(0, 2.8, 0)
		damage_popup.text = "-%.0f DMG!" % amount
		damage_popup.modulate = Color(1.0, 0.85, 0.2) if amount < 50 else Color(1.0, 0.2, 0.4)
		popup_timer = 1.2
	
	# Sound & visual hit feedback
	if AudioManager:
		AudioManager.play_sfx("hit")
	
	# Small hit flash & wobble
	if model_mesh:
		var tw = create_tween()
		tw.tween_property(model_mesh, "scale", Vector3(1.18, 0.82, 1.18), 0.05)
		tw.tween_property(model_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.12)
	
	_update_label()

func _update_label() -> void:
	if not label_3d:
		return
	var rolling_dmg: float = 0.0
	for h in recent_hits:
		rolling_dmg += h["dmg"]
	var dps = rolling_dmg / 1.5
	label_3d.text = "%s\nHP: %.0f / %.0f | DPS: %.0f | Total: %.0f" % [dummy_title, current_hp, max_hp, dps, total_damage_taken]
