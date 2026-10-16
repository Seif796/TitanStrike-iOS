@tool
extends Node3D

# AdminModel Script (res://scripts/admin_model.gd)
# Tool script ensures the Admin model animates live inside the Godot Editor viewport
# and provides easy playback in gameplay.

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
