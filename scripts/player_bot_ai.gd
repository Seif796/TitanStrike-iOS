extends Node
class_name PlayerBotAI

# PlayerBotAI Script (res://scripts/player_bot_ai.gd)
# Autonomous AI companion for solo play:
# - Fights minions and bosses actively alongside the human player.
# - High priority: If the human player is downed, rushes to them and revives them!
# - Aims accurately with 3D lead targeting and shoots weapons.
# - Dynamic tactical footwork: advances, backs up, strafes to dodge enemy fire, and jumps over obstacles.
# - Keeps reasonable squad leash distance from the human player.

@onready var bot: Player = get_parent() as Player

var human_player: Player = null
var current_target: Node3D = null
var scan_timer: float = 0.0
var search_interval: float = 0.2

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
			bot.bot_aim_target = Vector3.ZERO
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
		bot.bot_aim_target = Vector3.ZERO

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
	var closest_dist: float = 45.0
	
	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("enemies"))
	candidates.append_array(get_tree().get_nodes_in_group("minions"))
	candidates.append_array(get_tree().get_nodes_in_group("boss"))
	
	var seen: Dictionary = {}
	for c in candidates:
		if not is_instance_valid(c) or not (c is Node3D):
			continue
		if seen.has(c):
			continue
		seen[c] = true
		
		if "state" in c and c.state == 4: # BossState.DEFEATED
			continue
		if "current_hp" in c and c.current_hp <= 0:
			continue
		if c.is_queued_for_deletion():
			continue
		
		var d = bot.global_position.distance_to(c.global_position)
		if d < closest_dist:
			closest_dist = d
			current_target = c

func _behavior_rescue_player(delta: float) -> void:
	var to_player = human_player.global_position - bot.global_position
	var dist = to_player.length()
	
	_turn_towards(human_player.global_position, delta)
	bot.is_firing = false
	bot.bot_aim_target = Vector3.ZERO
	
	if dist > 2.2:
		# Sprint to downed teammate
		bot.input_vector = Vector2(0, -1.0)
		if bot.is_on_wall():
			bot.jump()
	else:
		bot.input_vector = Vector2.ZERO
		if multiplayer.has_multiplayer_peer():
			human_player.rpc("revive")
		else:
			human_player.revive()

func _behavior_combat(delta: float) -> void:
	if not is_instance_valid(current_target) or current_target.is_queued_for_deletion() or ("current_hp" in current_target and current_target.current_hp <= 0) or ("state" in current_target and current_target.state == 4):
		current_target = null
		bot.is_firing = false
		bot.bot_aim_target = Vector3.ZERO
		return
	
	# Squad leash: if human player is far away, don't stay behind forever
	if is_instance_valid(human_player) and not human_player.is_down:
		var dist_to_human = bot.global_position.distance_to(human_player.global_position)
		if dist_to_human > 28.0:
			_behavior_escort_player(delta)
			return
	
	var aim_height = 0.9
	if "is_final_boss" in current_target and current_target.is_final_boss:
		aim_height = 2.4
	elif "boss_type" in current_target:
		aim_height = 1.8
	
	var target_pos = current_target.global_position + Vector3(0, aim_height, 0)
	bot.bot_aim_target = target_pos
	
	# Turn to face enemy
	_turn_towards(current_target.global_position, delta)
	
	var to_target = current_target.global_position - bot.global_position
	var dist = to_target.length()
	
	# Tactical range maintenance (7 to 15m)
	if dist > 15.0:
		bot.input_vector = Vector2(0, -0.9) # Advance towards enemy
	elif dist < 5.5:
		bot.input_vector = Vector2(0, 0.7) # Back away
	else:
		# Strafe sideways dynamically to dodge enemy projectiles
		var strafe_x = sin(Time.get_ticks_msec() * 0.003) * 0.75
		bot.input_vector = Vector2(strafe_x, 0)
	
	if bot.is_on_wall():
		bot.jump()
	
	# Open fire on enemy!
	bot.is_firing = true
	
	# Auto-reload if magazine depleted
	if bot.active_weapon and bot.active_weapon.current_ammo <= 0 and not bot.active_weapon.is_reloading:
		bot.active_weapon.start_reload()

func _behavior_escort_player(delta: float) -> void:
	var to_player = human_player.global_position - bot.global_position
	var dist = to_player.length()
	
	_turn_towards(human_player.global_position, delta)
	bot.is_firing = false
	bot.bot_aim_target = Vector3.ZERO
	
	if dist > 6.0:
		bot.input_vector = Vector2(0, -1.0)
		if bot.is_on_wall():
			bot.jump()
	elif dist < 3.0:
		bot.input_vector = Vector2(0, 0.5)
	else:
		bot.input_vector = Vector2.ZERO

func _turn_towards(target_pos: Vector3, delta: float) -> void:
	var dir = target_pos - bot.global_position
	dir.y = 0
	if dir.length() > 0.1:
		var target_angle = atan2(-dir.x, -dir.z)
		bot.rotation.y = lerp_angle(bot.rotation.y, target_angle, 14.0 * delta)
