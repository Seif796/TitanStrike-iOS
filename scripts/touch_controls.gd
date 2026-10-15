extends Control
class_name TouchControls

# TouchControls Script (res://scripts/touch_controls.gd)
# Features directional movement buttons (D-Pad), smooth right-screen finger swipe camera look,
# combat buttons, and Fortnite-style building buttons.

# Directional Movement Buttons (D-Pad)
@onready var btn_up: Button = $LeftZone/DPad/BtnUp
@onready var btn_down: Button = $LeftZone/DPad/BtnDown
@onready var btn_left: Button = $LeftZone/DPad/BtnLeft
@onready var btn_right: Button = $LeftZone/DPad/BtnRight

# Combat buttons
@onready var fire_btn: Button = $RightZone/CombatBar/FireBtn
@onready var reload_btn: Button = $RightZone/CombatBar/ReloadBtn
@onready var switch_btn: Button = $RightZone/CombatBar/SwitchBtn

# Build mode buttons
@onready var build_toggle_btn: Button = $RightZone/BuildToggleBtn
@onready var build_bar: Control = $RightZone/BuildBar
@onready var wall_btn: Button = $RightZone/BuildBar/WallBtn
@onready var ramp_btn: Button = $RightZone/BuildBar/RampBtn
@onready var turret_btn: Button = $RightZone/BuildBar/TurretBtn
@onready var place_btn: Button = $RightZone/BuildBar/PlaceBtn

@onready var combat_bar: Control = $RightZone/CombatBar
@onready var revive_btn: Button = $CenterZone/ReviveBtn

var dpad_vector: Vector2 = Vector2.ZERO
var look_touch_index: int = -1
var last_look_pos: Vector2 = Vector2.ZERO

var player_ref: Player = null
var is_in_build_mode: bool = false

# D-pad button states
var up_pressed: bool = false
var down_pressed: bool = false
var left_pressed: bool = false
var right_pressed: bool = false

func _ready() -> void:
	if revive_btn:
		revive_btn.visible = false
	if build_bar:
		build_bar.visible = false
	
	_connect_movement_buttons()
	_connect_action_buttons()

func bind_player(p: Player) -> void:
	player_ref = p

func _connect_movement_buttons() -> void:
	if btn_up:
		btn_up.button_down.connect(func(): up_pressed = true; _update_dpad())
		btn_up.button_up.connect(func(): up_pressed = false; _update_dpad())
	if btn_down:
		btn_down.button_down.connect(func(): down_pressed = true; _update_dpad())
		btn_down.button_up.connect(func(): down_pressed = false; _update_dpad())
	if btn_left:
		btn_left.button_down.connect(func(): left_pressed = true; _update_dpad())
		btn_left.button_up.connect(func(): left_pressed = false; _update_dpad())
	if btn_right:
		btn_right.button_down.connect(func(): right_pressed = true; _update_dpad())
		btn_right.button_up.connect(func(): right_pressed = false; _update_dpad())

func _update_dpad() -> void:
	var v = Vector2.ZERO
	if up_pressed:
		v.y -= 1.0
	if down_pressed:
		v.y += 1.0
	if left_pressed:
		v.x -= 1.0
	if right_pressed:
		v.x += 1.0
	
	dpad_vector = v.normalized()
	if player_ref:
		player_ref.input_vector = dpad_vector

func _connect_action_buttons() -> void:
	if fire_btn:
		fire_btn.button_down.connect(func():
			if player_ref:
				player_ref.is_firing = true
		)
		fire_btn.button_up.connect(func():
			if player_ref:
				player_ref.is_firing = false
		)
	
	if reload_btn:
		reload_btn.pressed.connect(func():
			if player_ref:
				player_ref.reload_active_weapon()
		)
	
	if switch_btn:
		switch_btn.pressed.connect(func():
			if player_ref:
				player_ref.switch_weapon()
		)
	
	if build_toggle_btn:
		build_toggle_btn.pressed.connect(_on_build_toggle_pressed)
	
	if wall_btn:
		wall_btn.pressed.connect(func():
			if player_ref:
				player_ref.select_structure_type(0)
		)
	if ramp_btn:
		ramp_btn.pressed.connect(func():
			if player_ref:
				player_ref.select_structure_type(1)
		)
	if turret_btn:
		turret_btn.pressed.connect(func():
			if player_ref:
				player_ref.select_structure_type(2)
		)
	if place_btn:
		place_btn.pressed.connect(func():
			if player_ref:
				player_ref.place_structure()
		)
	
	if revive_btn:
		revive_btn.pressed.connect(func():
			if player_ref:
				player_ref._try_revive_teammate()
		)

func _on_build_toggle_pressed() -> void:
	if not player_ref:
		return
	is_in_build_mode = player_ref.toggle_build_mode()
	
	if build_bar:
		build_bar.visible = is_in_build_mode
	if combat_bar:
		combat_bar.visible = !is_in_build_mode
	
	build_toggle_btn.text = "⚔️ COMBAT" if is_in_build_mode else "🔨 BUILD"

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	var screen_width = get_viewport_rect().size.x
	var is_right_half = event.position.x >= (screen_width * 0.45)
	
	if event.pressed:
		if is_right_half and look_touch_index == -1:
			# Touch started on right side -> begin camera swipe look
			look_touch_index = event.index
			last_look_pos = event.position
	else:
		if event.index == look_touch_index:
			look_touch_index = -1

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == look_touch_index:
		var delta = event.position - last_look_pos
		last_look_pos = event.position
		if player_ref:
			# Smooth finger drag camera rotation
			player_ref.look_input = delta * 0.0055
