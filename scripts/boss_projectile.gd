extends Area3D
class_name BossProjectile

# BossProjectile Script (res://scripts/boss_projectile.gd)
# Energy fireball launched by the Boss towards players.

var direction: Vector3 = Vector3.FORWARD
var speed: float = 16.0
var damage: float = 35.0
var target_player: Node3D = null
var homing_strength: float = 2.0
var lifetime: float = 6.0

func setup(pos: Vector3, dir: Vector3, dmg: float = 35.0, target: Node3D = null) -> void:
	global_position = pos
	direction = dir.normalized()
	damage = dmg
	target_player = target

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(func():
		queue_free()
	)

func _physics_process(delta: float) -> void:
	if is_instance_valid(target_player):
		var to_target = (target_player.global_position + Vector3(0, 1, 0) - global_position).normalized()
		direction = direction.slerp(to_target, homing_strength * delta).normalized()
	
	global_position += direction * speed * delta
	look_at_safe(global_position + direction)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies") or body.is_in_group("boss"):
		return
	
	if body.is_in_group("players") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
	elif body is StaticBody3D or body is CSGShape3D:
		queue_free()

func look_at_safe(target: Vector3) -> void:
	if global_position.is_equal_approx(target):
		return
	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.FORWARD
	look_at(target, up)

