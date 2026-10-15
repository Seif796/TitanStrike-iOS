extends CanvasLayer
class_name HUD

# HUD Script (res://scripts/hud.gd)
# Displays player health, ammo, boss health bar, waves, and co-op alerts.

@onready var health_bar: ProgressBar = $SafeArea/PlayerStats/HealthBar
@onready var health_label: Label = $SafeArea/PlayerStats/HealthLabel
@onready var ammo_label: Label = $SafeArea/WeaponStats/AmmoLabel
@onready var weapon_label: Label = $SafeArea/WeaponStats/WeaponLabel
@onready var boss_container: VBoxContainer = $SafeArea/BossContainer
@onready var boss_bar: ProgressBar = $SafeArea/BossContainer/BossBar
@onready var boss_name_label: Label = $SafeArea/BossContainer/BossName
@onready var wave_label: Label = $SafeArea/TopInfo/WaveLabel
@onready var alert_label: Label = $SafeArea/CenterAlert
@onready var end_screen: Control = $EndScreen
@onready var end_title: Label = $EndScreen/Panel/VBox/Title
@onready var end_desc: Label = $EndScreen/Panel/VBox/Desc
@onready var restart_btn: Button = $EndScreen/Panel/VBox/RestartBtn

func _ready() -> void:
	if boss_container:
		boss_container.visible = false
	if alert_label:
		alert_label.visible = false
	if end_screen:
		end_screen.visible = false
	
	GameManager.boss_health_updated.connect(_on_boss_health_updated)
	GameManager.wave_updated.connect(_on_wave_updated)
	GameManager.game_over_triggered.connect(_on_game_over)
	
	if restart_btn:
		restart_btn.pressed.connect(func():
			NetworkManager.leave_game()
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		)

func update_health(current: float, max_val: float) -> void:
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = current
	if health_label:
		health_label.text = "HP: %d / %d" % [int(current), int(max_val)]

func update_ammo(current: int, max_mag: int, is_reloading: bool) -> void:
	if ammo_label:
		if is_reloading:
			ammo_label.text = "RELOADING..."
		else:
			ammo_label.text = "%d / %d" % [current, max_mag]

func update_weapon_info(w_name: String) -> void:
	if weapon_label:
		weapon_label.text = w_name

func show_downed_alert(is_down: bool) -> void:
	if alert_label:
		if is_down:
			alert_label.text = "⚠️ DOWNED! WAIT FOR TEAMMATE TO REVIVE! ⚠️"
			alert_label.visible = true
		else:
			alert_label.visible = false

func _on_boss_health_updated(current: float, max_val: float) -> void:
	if boss_container:
		boss_container.visible = true
		boss_bar.max_value = max_val
		boss_bar.value = current
		if current <= 0:
			boss_container.visible = false

func _on_wave_updated(wave: int, max_w: int, left: int) -> void:
	if wave_label:
		if wave > max_w:
			wave_label.text = "⚔️ BOSS BATTLE ⚔️"
		else:
			wave_label.text = "Wave %d / %d | Enemies: %d" % [wave, max_w, left]

func _on_game_over(is_victory: bool) -> void:
	if end_screen:
		end_screen.visible = true
		if is_victory:
			end_title.text = "🏆 VICTORY! 🏆"
			end_title.modulate = Color.GREEN
			end_desc.text = "You and your co-op squad defeated the Titan Boss!"
		else:
			end_title.text = "💀 DEFEAT 💀"
			end_title.modulate = Color.RED
			end_desc.text = "All squad members were eliminated by the Titan."

