extends CanvasLayer
class_name HUD

# HUD Script (res://scripts/hud.gd)
# Displays player health, ammo, nano-materials building stats, boss health bar, waves, and alerts.
# Includes 1-chance emergency Try Again button on defeat and victory unlock announcements.

@onready var health_bar: ProgressBar = $SafeArea/PlayerStats/HealthBar
@onready var health_label: Label = $SafeArea/PlayerStats/HealthLabel
@onready var materials_label: Label = $SafeArea/PlayerStats/MaterialsLabel
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
@onready var try_again_btn: Button = $EndScreen/Panel/VBox/TryAgainBtn
@onready var return_to_room_btn: Button = get_node_or_null("EndScreen/Panel/VBox/ReturnToRoomBtn")
@onready var restart_btn: Button = $EndScreen/Panel/VBox/RestartBtn

func _ready() -> void:
	if boss_container:
		boss_container.visible = false
	if alert_label:
		alert_label.visible = false
	if end_screen:
		end_screen.visible = false
	if try_again_btn:
		try_again_btn.visible = false
	
	GameManager.boss_health_updated.connect(_on_boss_health_updated)
	GameManager.wave_updated.connect(_on_wave_updated)
	GameManager.game_over_triggered.connect(_on_game_over)
	
	if try_again_btn:
		try_again_btn.pressed.connect(_on_try_again_pressed)
	
	if return_to_room_btn:
		return_to_room_btn.pressed.connect(func():
			if multiplayer.is_server():
				GameManager.rpc("return_to_lobby_together")
			else:
				GameManager.rpc_id(1, "request_return_to_lobby")
		)
	
	if restart_btn:
		restart_btn.pressed.connect(func():
			NetworkManager.leave_game()
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		)

func _on_try_again_pressed() -> void:
	if GameManager.has_used_retry:
		return
	if try_again_btn:
		try_again_btn.visible = false
	if end_screen:
		end_screen.visible = false
	GameManager.rpc("request_retry_stage")

func update_health(current: float, max_val: float) -> void:
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = current
	if health_label:
		health_label.text = "HP: %d / %d" % [int(current), int(max_val)]

func update_materials(amount: int) -> void:
	if materials_label:
		materials_label.text = "🔨 Nano-Materials: %d" % amount

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

func _on_boss_health_updated(current: float, max_val: float, boss_title: String = "") -> void:
	if boss_container:
		boss_container.visible = true
		boss_bar.max_value = max_val
		boss_bar.value = current
		if boss_title != "" and boss_name_label:
			boss_name_label.text = boss_title
		if current <= 0:
			boss_container.visible = false

func _on_wave_updated(wave: int, max_w: int, left: int) -> void:
	if wave_label:
		if wave > max_w:
			wave_label.text = "⚔️ TITAN BOSS BATTLE ⚔️"
		else:
			wave_label.text = "Wave %d / %d | Minions Left: %d" % [wave, max_w, left]

func _on_game_over(is_victory: bool) -> void:
	if end_screen:
		end_screen.visible = true
		if is_victory:
			end_title.text = "🏆 VICTORY! 🏆"
			end_title.modulate = Color.GREEN
			if GameManager.admin_just_unlocked:
				end_desc.text = "You eliminated both Titans!\n👑 ADMIN CHARACTER UNLOCKED! (تم فتح شخصية الأدمن 500 HP!) 👑"
			else:
				end_desc.text = "You eliminated both Titans!\n🏆 ALL BOSSES DEFEATED! CYBERFORT IS SAVED! 🏆"
			if try_again_btn:
				try_again_btn.visible = false
		else:
			end_title.text = "💀 DEFEAT 💀"
			end_title.modulate = Color.RED
			if not GameManager.has_used_retry:
				end_desc.text = "All squad members were eliminated!\nYou have 1 emergency retry to replay this stage."
				if try_again_btn:
					try_again_btn.visible = true
			else:
				end_desc.text = "All squad members were eliminated.\n(Used 1 retry chance - No retries remaining)"
				if try_again_btn:
					try_again_btn.visible = false
