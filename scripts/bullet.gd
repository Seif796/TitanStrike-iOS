extends Area3D
class_name Bullet

# Bullet Script (res://scripts/bullet.gd)
# 3D physical projectile that damages enemies and the Titan Boss.

var direction: Vector3 = Vector3.FORWARD
var speed: float = 40.0
var damage: float = 20.0
var shooter_peer_id: int = 1
var lifetime: float = 3.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func setup(pos: Vector3, dir: Vector3, spd: float, dmg: float, peer_id: int, color: Color = Color.YELLOW) -> void:
	global_position = pos
	direction = dir.normalized()
	speed = spd
	damage = dmg
	shooter_peer_id = peer_id
	look_at_safe(global_position + direction)
	
	# Apply color material
	if mesh and mesh.material_override is StandardMaterial3D:
		mesh.material_override.albedo_color = color
		mesh.material_override.emission = color

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	get_tree().create_timer(lifetime).timeout.connect(func():
		queue_free()
	)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		if GameManager.selected_game_mode == GameManager.GameMode.PVP_DUEL:
			var target_peer = body.get("peer_id")
			if target_peer != null and target_peer != shooter_peer_id:
				if body.has_method("take_damage"):
					body.take_damage(damage)
					_spawn_impact()
					queue_free()
		return
	
	if body.has_method("take_damage"):
		body.take_damage(damage, shooter_peer_id)
		_spawn_impact()
		queue_free()
	elif body is StaticBody3D or body is CSGShape3D:
		# Hit wall/obstacle
		_spawn_impact()
		queue_free()

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("damageable") and area.has_method("take_damage"):
		area.take_damage(damage, shooter_peer_id)
		_spawn_impact()
		queue_free()

func _spawn_impact() -> void:
	# Small visual spark/flash on impact
	pass

func look_at_safe(target: Vector3) -> void:
	if global_position.is_equal_approx(target):
		return
	var up = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.FORWARD
	look_at(target, up)

