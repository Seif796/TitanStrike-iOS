@tool
extends Node3D
class_name SpiderHeroModel

# SpiderHeroModel Script (res://scripts/spider_hero_model.gd)
# Tool script ensures the Chibi Spider-Hero animates live inside the Godot Editor viewport
# and provides smooth animation controls for gameplay.

@onready var anim_player: AnimationPlayer = $AnimationPlayer

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
