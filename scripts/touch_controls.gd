extends Control
class_name TouchControls

# TouchControls Script (res://scripts/touch_controls.gd)
# Mobile on-screen joystick, camera drag, combat buttons, and Fortnite-style building buttons.

@onready var joystick_base: Control = $LeftZone/JoystickBase
@onready var joystick_knob: Control = $LeftZone/JoystickBase/Knob

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

var joystick_active: bool = false
var joystick_touch_index: int = -1
var joystick_center: Vector2 = Vector2.ZERO
var joystick_radius: float = 75.0

var look_touch_index: int = -1
var last_look_pos: Vector2 = Vector2.ZERO

var player_ref: Player = null
var is_in_build_mode: bool = false

func _ready() -> void:
	if joystick_base:
		joystick_center = joystick_base.size / 2.0
		_reset_joystick()
	
	if revive_btn:
		revive_btn.visible = false
	
	if build_bar:
		build_bar.visible = false
	
	_connect_buttons()

func bind_player(p: Player) -> void:
	player_ref = p

func _connect_buttons() -> void:
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
	var is_left_half = event.position.x < (screen_width * 0.42)
	
	if event.pressed:
		if is_left_half and joystick_touch_index == -1:
			joystick_touch_index = event.index
			joystick_active = true
			if joystick_base:
				joystick_base.global_position = event.position - joystick_center
			_update_joystick(event.position)
		elif not is_left_half and look_touch_index == -1:
			look_touch_index = event.index
			last_look_pos = event.position
	else:
		if event.index == joystick_touch_index:
			joystick_touch_index = -1
			joystick_active = false
			_reset_joystick()
			if player_ref:
				player_ref.input_vector = Vector2.ZERO
		elif event.index == look_touch_index:
			look_touch_index = -1

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == joystick_touch_index and joystick_active:
		_update_joystick(event.position)
	elif event.index == look_touch_index:
		var delta = event.position - last_look_pos
		last_look_pos = event.position
		if player_ref:
			player_ref.look_input = delta * 0.0055

func _update_joystick(touch_pos: Vector2) -> void:
	if not joystick_base or not joystick_knob:
		return
	var base_center = joystick_base.global_position + joystick_center
	var offset = touch_pos - base_center
	if offset.length() > joystick_radius:
		offset = offset.normalized() * joystick_radius
	
	joystick_knob.position = joystick_center + offset - (joystick_knob.size / 2.0)
	
	var norm_input = offset / joystick_radius
	if player_ref:
		player_ref.input_vector = norm_input

func _reset_joystick() -> void:
	if joystick_knob:
		joystick_knob.position = joystick_center - (joystick_knob.size / 2.0)
