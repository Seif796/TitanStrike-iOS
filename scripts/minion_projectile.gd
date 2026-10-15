extends Area3D
class_name MinionProjectile

# MinionProjectile Script (res://scripts/minion_projectile.gd)
# Energy spore ball thrown by minions towards players.

var direction: Vector3 = Vector3.FORWARD
var speed: float = 18.0
var damage: float = 16.0
var lifetime: float = 4.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var light: OmniLight3D = $OmniLight3D

func setup(pos: Vector3, dir: Vector3, dmg: float = 16.0) -> void:
	global_position = pos
	direction = dir.normalized()
	damage = dmg

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(func():
		queue_free()
	)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies") or body.is_in_group("boss"):
		return
	
	if body.is_in_group("players") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
	elif body.is_in_group("structures") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
	elif body is StaticBody3D or body is CSGShape3D:
		queue_free()
