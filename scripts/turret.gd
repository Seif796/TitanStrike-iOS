extends Structure
class_name AutoTurret

# AutoTurret Script (res://scripts/turret.gd)
# Automated defense turret built by players that shoots incoming minions and the boss.

@export var fire_rate: float = 0.5
@export var damage: float = 18.0
@export var detection_range: float = 18.0

@onready var head: Node3D = $Head
@onready var barrel: Marker3D = $Head/Barrel
@onready var muzzle_light: OmniLight3D = $Head/Barrel/Light

var target: Node3D = null
var can_shoot: bool = true
var bullet_scene = preload("res://scenes/bullet.tscn")

func _ready() -> void:
	super._ready()
	if muzzle_light:
		muzzle_light.visible = false

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	
	_find_target()
	
	if is_instance_valid(target):
		var target_pos = target.global_position + Vector3(0, 1, 0)
		var dir = (target_pos - head.global_position).normalized()
		var target_rot = atan2(-dir.x, -dir.z)
		head.rotation.y = lerp_angle(head.rotation.y, target_rot, 8.0 * delta)
		
		if can_shoot:
			_shoot(target_pos)

func _find_target() -> void:
	if is_instance_valid(target) and global_position.distance_to(target.global_position) <= detection_range:
		return
	
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest_dist = detection_range
	var closest: Node3D = null
	
	for e in enemies:
		if is_instance_valid(e):
			var d = global_position.distance_to(e.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = e
	
	target = closest

func _shoot(target_pos: Vector3) -> void:
	can_shoot = false
	rpc("_play_turret_shot", target_pos)
	
	get_tree().create_timer(fire_rate).timeout.connect(func():
		can_shoot = true
	)

@rpc("call_local", "reliable")
func _play_turret_shot(target_pos: Vector3) -> void:
	if muzzle_light:
		muzzle_light.visible = true
		get_tree().create_timer(0.06).timeout.connect(func():
			if muzzle_light:
				muzzle_light.visible = false
		)
	
	if bullet_scene and barrel:
		var b = bullet_scene.instantiate()
		var dir = (target_pos - barrel.global_position).normalized()
		b.setup(barrel.global_position, dir, 45.0, damage, builder_peer_id, Color.CYAN)
		get_tree().current_scene.add_child(b)
