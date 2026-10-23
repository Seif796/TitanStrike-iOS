@tool
extends Node3D
class_name CitrusTankModel

# CitrusTankModel Script (res://scripts/citrus_tank_model.gd)
# Dedicated Heavy 3D Juggernaut Citrus Tank character model with dual exhaust stacks and heavy armor.

@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var core_light: OmniLight3D = get_node_or_null("Model/Torso/CoreLight")

func _ready() -> void:
	if anim_player:
		anim_player.play("idle")

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if anim_player and not anim_player.is_playing():
			anim_player.play("idle")

func play_anim(anim_name: String) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		if anim_player.current_animation != anim_name:
			anim_player.play(anim_name)

func set_anim_speed(speed_ratio: float) -> void:
	if anim_player:
		anim_player.speed_scale = speed_ratio
