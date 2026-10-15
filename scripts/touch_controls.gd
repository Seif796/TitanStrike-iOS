extends Control
class_name TouchControls

# TouchControls Script (res://scripts/touch_controls.gd)
# Features 100% independent multi-touch processing:
# - Simultaneous Run & Gun: Moving with left thumb NEVER cancels or stops firing with right thumb!
# - Ergonomic 140x140 circular FIRE button positioned for natural thumb resting.
# - Smooth camera swipe trackpad on the right screen without false clicks.

@onready var left_zone: Control = $LeftZone
@onready var dpad: Control = $LeftZone/DPad
@onready var btn_up: Button = $LeftZone/DPad/BtnUp
@onready var btn_down: Button = $LeftZone/DPad/BtnDown
@onready var btn_left: Button = $LeftZone/DPad/BtnLeft
@onready var btn_right: Button = $LeftZone/DPad/BtnRight

@onready var right_zone: Control = $RightZone
@onready var jump_btn: Button = $RightZone/JumpBtn
@onready var combat_bar: Control = $RightZone/CombatBar
@onready var fire_btn: Button = $RightZone/CombatBar/FireBtn
@onready var reload_btn: Button = $RightZone/CombatBar/ReloadBtn
@onready var switch_btn: Button = $RightZone/CombatBar/SwitchBtn
@onready var build_toggle_btn: Button = $RightZone/BuildToggleBtn

@onready var build_bar: Control = $RightZone/BuildBar
@onready var place_btn: Button = $RightZone/BuildBar/PlaceBtn
@onready var wall_btn: Button = $RightZone/BuildBar/WallBtn
@onready var ramp_btn: Button = $RightZone/BuildBar/RampBtn
@onready var turret_btn: Button = $RightZone/BuildBar/TurretBtn

@onready var revive_btn: Button = $CenterZone/ReviveBtn

var player_ref: Player = null
var is_in_build_mode: bool = false

# Independent multi-touch pointer tracking
var move_touch_index: int = -1
var fire_touch_index: int = -1
var look_touch_index: int = -1
var last_look_pos: Vector2 = Vector2.ZERO

var dpad_vector: Vector2 = Vector2.ZERO

func _ready() -> void:
	if revive_btn:
		revive_btn.visible = false
	if build_bar:
		build_bar.visible = false

func bind_player(p: Player) -> void:
	player_ref = p

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_process_touch_down(event.index, event.position)
		else:
			_process_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_process_touch_drag(event.index, event.position, event.relative)
	elif event is InputEventMouseButton:
		# Fallback for mouse testing in PC editor
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_process_touch_down(999, event.position)
			else:
				_process_touch_up(999)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_process_touch_drag(999, event.position, event.relative)

func _process_touch_down(index: int, pos: Vector2) -> void:
	var screen_w = get_viewport_rect().size.x
	
	# 1. Check Revive Button
	if revive_btn and revive_btn.visible and revive_btn.get_global_rect().has_point(pos):
		if player_ref:
			player_ref._try_revive_teammate()
		return
	
	# 2. Check Build Mode Toggle
	if build_toggle_btn and build_toggle_btn.get_global_rect().has_point(pos):
		_on_build_toggle_pressed()
		return
	
	# 3. Check JUMP BUTTON (works in both combat and build modes)
	if jump_btn and jump_btn.visible and jump_btn.get_global_rect().has_point(pos):
		if player_ref:
			player_ref.jump()
		jump_btn.modulate = Color(1.4, 1.4, 1.4)
		return
	
	# 4. Check Right Zone Action Buttons
	if is_in_build_mode:
		if place_btn and place_btn.get_global_rect().has_point(pos):
			if player_ref:
				player_ref.place_structure()
			return
		if wall_btn and wall_btn.get_global_rect().has_point(pos):
			if player_ref: player_ref.select_structure_type(0)
			return
		if ramp_btn and ramp_btn.get_global_rect().has_point(pos):
			if player_ref: player_ref.select_structure_type(1)
			return
		if turret_btn and turret_btn.get_global_rect().has_point(pos):
			if player_ref: player_ref.select_structure_type(2)
			return
	else:
		# Combat Mode Buttons:
		# Check FIRE BUTTON
		if fire_btn and fire_btn.get_global_rect().has_point(pos):
			fire_touch_index = index
			if player_ref:
				player_ref.is_firing = true
			fire_btn.modulate = Color(1.3, 1.3, 1.3)
			return
		
		# Check RELOAD BUTTON
		if reload_btn and reload_btn.get_global_rect().has_point(pos):
			if player_ref:
				player_ref.reload_active_weapon()
			return
		
		# Check SWITCH WEAPON BUTTON
		if switch_btn and switch_btn.get_global_rect().has_point(pos):
			if player_ref:
				player_ref.switch_weapon()
			return
	
	# 5. Check Left Zone (Movement / D-Pad)
	if pos.x < screen_w * 0.45:
		move_touch_index = index
		_update_movement_from_pos(pos)
		return
	
	# 6. Check Right Zone (Camera Look swipe)
	if pos.x >= screen_w * 0.45 and look_touch_index == -1:
		look_touch_index = index
		last_look_pos = pos

func _process_touch_drag(index: int, pos: Vector2, _rel: Vector2) -> void:
	if index == move_touch_index:
		_update_movement_from_pos(pos)
	elif index == fire_touch_index:
		# Maintain firing even if thumb wiggles slightly
		if player_ref:
			player_ref.is_firing = true
	elif index == look_touch_index:
		var delta = pos - last_look_pos
		last_look_pos = pos
		if player_ref:
			player_ref.look_input = delta * 0.0055

func _process_touch_up(index: int) -> void:
	if jump_btn:
		jump_btn.modulate = Color(1.0, 1.0, 1.0)
	
	if index == move_touch_index:
		move_touch_index = -1
		dpad_vector = Vector2.ZERO
		if player_ref:
			player_ref.input_vector = Vector2.ZERO
		_highlight_dpad(Vector2.ZERO)
	
	if index == fire_touch_index:
		fire_touch_index = -1
		if player_ref:
			player_ref.is_firing = false
		if fire_btn:
			fire_btn.modulate = Color(1.0, 1.0, 1.0)
	
	if index == look_touch_index:
		look_touch_index = -1

func _update_movement_from_pos(pos: Vector2) -> void:
	if not dpad:
		return
	var center = dpad.get_global_rect().get_center()
	var offset = pos - center
	var dist = offset.length()
	
	if dist > 15.0:
		dpad_vector = offset.normalized()
		var strength = clamp(dist / 65.0, 0.0, 1.0)
		dpad_vector *= strength
	else:
		dpad_vector = Vector2.ZERO
	
	if player_ref:
		player_ref.input_vector = dpad_vector
	_highlight_dpad(dpad_vector)

func _highlight_dpad(vec: Vector2) -> void:
	if btn_up:
		btn_up.modulate = Color(1.4, 1.4, 1.4) if vec.y < -0.25 else Color(1, 1, 1)
	if btn_down:
		btn_down.modulate = Color(1.4, 1.4, 1.4) if vec.y > 0.25 else Color(1, 1, 1)
	if btn_left:
		btn_left.modulate = Color(1.4, 1.4, 1.4) if vec.x < -0.25 else Color(1, 1, 1)
	if btn_right:
		btn_right.modulate = Color(1.4, 1.4, 1.4) if vec.x > 0.25 else Color(1, 1, 1)

func _on_build_toggle_pressed() -> void:
	if not player_ref:
		return
	is_in_build_mode = player_ref.toggle_build_mode()
	
	if build_bar:
		build_bar.visible = is_in_build_mode
	if combat_bar:
		combat_bar.visible = !is_in_build_mode
	
	build_toggle_btn.text = "⚔️ COMBAT" if is_in_build_mode else "🔨 BUILD"
