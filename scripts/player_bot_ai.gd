extends Node
class_name PlayerBotAI

# PlayerBotAI Script (res://scripts/player_bot_ai.gd)
# Autonomous AI companion for solo play:
# - Stays close to human player (tactical squad escort).
# - Targets nearby minions and bosses, rotates, aims, and fires weapons.
# - High priority: If the human player is downed, rushes to them and revives them!
# - Jumps over obstacles and reloads active weapon automatically.

@onready var bot: Player = get_parent() as Player

var human_player: Player = null
var current_target: Node3D = null
var scan_timer: float = 0.0
var search_interval: float = 0.25

func _ready() -> void:
	if not bot:
		queue_free()
		return
	bot.is_bot = true

func _physics_process(delta: float) -> void:
	if not is_instance_valid(bot) or bot.is_down:
		if bot:
			bot.input_vector = Vector2.ZERO
			bot.is_firing = false
		return
	
	_locate_human_player()
	
	scan_timer += delta
	if scan_timer >= search_interval:
		scan_timer = 0.0
		_find_best_target()
	
	# PRIORITY 1: Rescue human player if downed!
	if is_instance_valid(human_player) and human_player.is_down:
		_behavior_rescue_player(delta)
		return
	
	# PRIORITY 2: Engage targets if present
	if is_instance_valid(current_target):
		_behavior_combat(delta)
		return
	
	# PRIORITY 3: Escort human player
	if is_instance_valid(human_player):
		_behavior_escort_player(delta)
	else:
		bot.input_vector = Vector2.ZERO
		bot.is_firing = false

func _locate_human_player() -> void:
	if is_instance_valid(human_player) and not human_player.is_bot:
		return
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p is Player and not p.is_bot:
			human_player = p
			break

func _find_best_target() -> void:
	current_target = null
	var closest_dist: float = 40.0
	
	# Check minions
	var minions = get_tree().get_nodes_in_group("minions")
	for m in minions:
		if is_instance_valid(m) and m is Node3D:
			var d = bot.global_position.distance_to(m.global_position)
			if d < closest_dist:
				closest_dist = d
				current_target = m
	
	# Check bosses
	var bosses = get_tree().get_nodes_in_group("boss")
	for b in bosses:
		if is_instance_valid(b) and b is Node3D:
			var d = bot.global_position.distance_to(b.global_position)
			if d < closest_dist:
				closest_dist = d
				current_target = b

func _behavior_rescue_player(delta: float) -> void:
	var to_player = human_player.global_position - bot.global_position
	var dist = to_player.length()
	
	# Aim towards human player
	_turn_towards(human_player.global_position, delta)
	
	if dist > 2.2:
		# Run fast to the downed friend!
		bot.input_vector = Vector2(0, -1) # Move forward in local space
		bot.is_firing = false
		if bot.is_on_wall():
			bot.jump()
	else:
		# Within revive distance: revive!
		bot.input_vector = Vector2.ZERO
		bot.is_firing = false
		human_player.revive()

func _behavior_combat(delta: float) -> void:
	var to_target = current_target.global_position - bot.global_position
	var dist = to_target.length()
	
	# Turn to face enemy
	_turn_towards(current_target.global_position, delta)
	
	# Maintain tactical combat distance (between 8 and 14 meters)
	if dist > 14.0:
		bot.input_vector = Vector2(0, -0.85) # Advance forward
	elif dist < 6.0:
		bot.input_vector = Vector2(0, 0.7) # Back away slightly
	else:
		# Strafe sideways dynamically
		var strafe_x = sin(Time.get_ticks_msec() * 0.003) * 0.6
		bot.input_vector = Vector2(strafe_x, 0)
	
	if bot.is_on_wall():
		bot.jump()
	
	# Fire weapon at target!
	bot.is_firing = true
	
	# Auto reload if out of ammo
	if bot.active_weapon and bot.active_weapon.current_ammo <= 0:
		bot.active_weapon.start_reload()

func _behavior_escort_player(delta: float) -> void:
	var to_player = human_player.global_position - bot.global_position
	var dist = to_player.length()
	
	_turn_towards(human_player.global_position, delta)
	bot.is_firing = false
	
	if dist > 6.0:
		# Catch up with the leader!
		bot.input_vector = Vector2(0, -1)
		if bot.is_on_wall():
			bot.jump()
	elif dist < 3.2:
		# Too close, back off slightly
		bot.input_vector = Vector2(0, 0.5)
	else:
		bot.input_vector = Vector2.ZERO

func _turn_towards(target_pos: Vector3, delta: float) -> void:
	var dir = target_pos - bot.global_position
	dir.y = 0
	if dir.length() > 0.1:
		var target_angle = atan2(-dir.x, -dir.z)
		bot.rotation.y = lerp_angle(bot.rotation.y, target_angle, 8.0 * delta)
