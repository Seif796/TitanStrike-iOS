extends Node3D
class_name Weapon

# Weapon Script (res://scripts/weapon.gd)
# Handles shooting, ammo, reloading, and projectile instantiation.

signal ammo_changed(current: int, max_mag: int, is_reloading: bool)

@export var weapon_name: String = "Rifle"
@export var damage: float = 20.0
@export var fire_rate: float = 0.15 # seconds between shots
@export var max_ammo: int = 30
@export var reload_time: float = 1.8
@export var bullet_speed: float = 45.0
@export var spread_angle: float = 1.5 # degrees
@export var pellets_per_shot: int = 1 # >1 for shotgun
@export var bullet_color: Color = Color(1.0, 0.85, 0.2)

var current_ammo: int = 30
var can_shoot: bool = true
var is_reloading: bool = false
var owner_peer_id: int = 1

@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: OmniLight3D = $MuzzleFlash
@onready var mesh: Node3D = $Model

var bullet_scene = preload("res://scenes/bullet.tscn")

func _ready() -> void:
	current_ammo = max_ammo
	if muzzle_flash:
		muzzle_flash.visible = false

func try_shoot(aim_target: Vector3) -> bool:
	if is_reloading or not can_shoot or current_ammo <= 0:
		if current_ammo <= 0 and not is_reloading:
			start_reload()
		return false
	
	current_ammo -= 1
	ammo_changed.emit(current_ammo, max_ammo, false)
	can_shoot = false
	
	_spawn_shot_visuals(aim_target)
	
	get_tree().create_timer(fire_rate).timeout.connect(func():
		can_shoot = true
	)
	return true

func _spawn_shot_visuals(aim_target: Vector3) -> void:
	# Show muzzle flash momentarily
	if muzzle_flash:
		muzzle_flash.visible = true
		get_tree().create_timer(0.05).timeout.connect(func():
			if muzzle_flash:
				muzzle_flash.visible = false
		)
	
	# Spawn bullets
	var spawn_pos = muzzle.global_position if muzzle else global_position
	var base_dir = (aim_target - spawn_pos).normalized()
	if base_dir == Vector3.ZERO:
		base_dir = -global_transform.basis.z
	
	for i in range(pellets_per_shot):
		var spread_dir = base_dir
		if spread_angle > 0:
			var rand_x = deg_to_rad(randf_range(-spread_angle, spread_angle))
			var rand_y = deg_to_rad(randf_range(-spread_angle, spread_angle))
			spread_dir = spread_dir.rotated(Vector3.UP, rand_y)
			spread_dir = spread_dir.rotated(global_transform.basis.x, rand_x)
		
		# If multiplayer, bullets should be spawned on server or RPC'd
		_spawn_bullet(spawn_pos, spread_dir)

func _spawn_bullet(pos: Vector3, dir: Vector3) -> void:
	if bullet_scene:
		var b = bullet_scene.instantiate()
		b.setup(pos, dir, bullet_speed, damage, owner_peer_id, bullet_color)
		get_tree().current_scene.add_child(b)

func start_reload() -> void:
	if is_reloading or current_ammo == max_ammo:
		return
	is_reloading = true
	ammo_changed.emit(current_ammo, max_ammo, true)
	
	get_tree().create_timer(reload_time).timeout.connect(func():
		current_ammo = max_ammo
		is_reloading = false
		ammo_changed.emit(current_ammo, max_ammo, false)
	)
