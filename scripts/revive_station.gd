extends Node3D
class_name ReviveStation

# ReviveStation Script (res://scripts/revive_station.gd)
# High-tech battlefield recovery terminal that allows players to revive fallen squad teammates!

@onready var trigger_area: Area3D = $Area3D
@onready var label_3d: Label3D = $Label3D
@onready var beacon_light: OmniLight3D = $OmniLight3D
@onready var beacon_cylinder: CSGCylinder3D = $BeaconBeam
@onready var station_base: CSGCylinder3D = $Base
@onready var terminal_screen: CSGBox3D = $TerminalScreen

var is_cooldown: bool = false
var cooldown_timer: float = 0.0
const COOLDOWN_DURATION: float = 8.0

var players_in_zone: Array[Node] = []

func _ready() -> void:
	add_to_group("revive_stations")
	if trigger_area:
		trigger_area.body_entered.connect(_on_body_entered)
		trigger_area.body_exited.connect(_on_body_exited)
	_update_visuals()

func _process(delta: float) -> void:
	if is_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			is_cooldown = false
			_update_visuals()
		else:
			if label_3d:
				label_3d.text = "⚡ جهاز الإنعاش: جاري الشحن...\n(Recharging: %.1fs)" % cooldown_timer
				label_3d.modulate = Color(0.7, 0.7, 0.7)
			return
	
	# Pulse beacon beam
	if beacon_cylinder and beacon_cylinder.material is StandardMaterial3D:
		var mat = beacon_cylinder.material as StandardMaterial3D
		var pulse = (sin(Time.get_ticks_msec() * 0.005) + 1.0) * 0.5
		mat.albedo_color.a = 0.35 + (pulse * 0.25)
	
	_update_visuals()

func _update_visuals() -> void:
	if is_cooldown:
		return
	
	var has_downed = _has_downed_teammates()
	if has_downed:
		if label_3d:
			label_3d.text = "⚡ جهاز الإنعاش جاهز! ⚡\n(اضغط E أو زر الإنعاش لإحياء زميلك!)"
			label_3d.modulate = Color(0.2, 1.0, 0.5)
		if beacon_light:
			beacon_light.light_color = Color(0.2, 1.0, 0.5)
			beacon_light.light_energy = 3.5
	else:
		if label_3d:
			label_3d.text = "🏥 محطة الإنعاش الطبي 🏥\n(جميع أفراد الفريق بخير)"
			label_3d.modulate = Color(0.3, 0.85, 1.0)
		if beacon_light:
			beacon_light.light_color = Color(0.3, 0.85, 1.0)
			beacon_light.light_energy = 1.8

func _has_downed_teammates() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.has_method("is_downed") and p.is_downed():
			return true
	return false

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players") and (not body.has_method("is_downed") or not body.is_downed()):
		if not players_in_zone.has(body):
			players_in_zone.append(body)
		_check_player_prompt(body)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("players"):
		players_in_zone.erase(body)

func _check_player_prompt(p: Node) -> void:
	var is_local = (not p.has_method("is_local_player")) or p.is_local_player()
	if is_local and _has_downed_teammates() and not is_cooldown:
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_alert"):
			hud.show_alert("⚡ اضغط زر الإنعاش لإحياء زميلك فوراً!", Color(0.2, 1.0, 0.5), 2.5)

func can_revive() -> bool:
	return not is_cooldown and _has_downed_teammates()

func try_activate_from_player(p: Node) -> bool:
	if not can_revive():
		return false
	
	var peer_id = p.get("peer_id") if p.get("peer_id") != null else 1
	if multiplayer.has_multiplayer_peer():
		rpc("activate_revive", peer_id)
	else:
		activate_revive(peer_id)
	return true

@rpc("call_local", "reliable")
func activate_revive(reviver_peer_id: int) -> void:
	is_cooldown = true
	cooldown_timer = COOLDOWN_DURATION
	
	var reviver_name = "Agent"
	if NetworkManager.players.has(reviver_peer_id):
		reviver_name = NetworkManager.players[reviver_peer_id].get("name", "Agent")
	
	var count = 0
	var offset_dist = 2.0
	for p in get_tree().get_nodes_in_group("players"):
		if p.has_method("is_downed") and p.is_downed():
			count += 1
			# Teleport to revive station platform
			var spawn_angle = randf() * TAU
			var spawn_offset = Vector3(cos(spawn_angle), 0, sin(spawn_angle)) * offset_dist
			p.global_position = global_position + spawn_offset
			
			if multiplayer.has_multiplayer_peer():
				p.rpc("revive")
			else:
				p.revive()
	
	# Visual Burst
	_play_revive_effect()
	
	# Broadcast HUD alert
	var msg = "⚡ تم إنعاش الزميل بنجاح عبر جهاز الإنعاش بواسطة %s! ⚡\n(TEAMMATE RESPAWNED AT TERMINAL)" % reviver_name
	for hud in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("show_alert"):
			hud.show_alert(msg, Color(0.2, 1.0, 0.5), 3.5)

func _play_revive_effect() -> void:
	if beacon_light:
		beacon_light.light_energy = 8.0
		var tw = create_tween()
		tw.tween_property(beacon_light, "light_energy", 2.0, 1.2)
