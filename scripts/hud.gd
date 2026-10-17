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

@onready var in_game_exit_btn: Button = get_node_or_null("SafeArea/TopRight/InGameExitBtn")
@onready var pause_menu: Control = get_node_or_null("PauseMenu")
@onready var resume_btn: Button = get_node_or_null("PauseMenu/Panel/VBox/ResumeBtn")
@onready var return_lobby_btn: Button = get_node_or_null("PauseMenu/Panel/VBox/ReturnLobbyBtn")
@onready var leave_match_btn: Button = get_node_or_null("PauseMenu/Panel/VBox/LeaveMatchBtn")

func _ready() -> void:
	add_to_group("hud")
	if boss_container:
		boss_container.visible = false
	if alert_label:
		alert_label.visible = false
	if end_screen:
		end_screen.visible = false
	if try_again_btn:
		try_again_btn.visible = false
	if pause_menu:
		pause_menu.visible = false
	
	GameManager.boss_health_updated.connect(_on_boss_health_updated)
	GameManager.wave_updated.connect(_on_wave_updated)
	GameManager.game_over_triggered.connect(_on_game_over)
	
	if in_game_exit_btn:
		in_game_exit_btn.pressed.connect(func():
			if pause_menu:
				pause_menu.visible = true
				if return_lobby_btn:
					return_lobby_btn.visible = (multiplayer.has_multiplayer_peer() and NetworkManager.players.size() > 1)
		)
	
	if resume_btn:
		resume_btn.pressed.connect(func():
			if pause_menu:
				pause_menu.visible = false
		)
	
	if return_lobby_btn:
		return_lobby_btn.pressed.connect(func():
			if multiplayer.is_server():
				GameManager.rpc("return_to_lobby_together")
			else:
				GameManager.rpc_id(1, "request_return_to_lobby")
		)
	
	if leave_match_btn:
		leave_match_btn.pressed.connect(func():
			NetworkManager.leave_game()
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		)
	
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

func show_downed_alert(is_down: bool, spectating_name: String = "") -> void:
	if alert_label:
		if is_down:
			if not spectating_name.is_empty():
				alert_label.text = "💀 لقد سقطت في المعركة! (DOWNED)\n👁️ وضع المشاهدة: تتابع الآن %s\n⚡ توجه لجهاز الإنعاش (Revive Station) لتعود للحياة!" % spectating_name
			else:
				alert_label.text = "💀 لقد سقطت في المعركة! (DOWNED)\n⚡ انتظر إنعاشك عبر جهاز الإنعاش!"
			alert_label.visible = true
			alert_label.modulate = Color(1.0, 0.3, 0.3)
		else:
			alert_label.visible = false

func show_alert(text: String, col: Color = Color.WHITE, duration: float = 3.0) -> void:
	if alert_label:
		alert_label.text = text
		alert_label.modulate = col
		alert_label.visible = true
		get_tree().create_timer(duration).timeout.connect(func():
			if alert_label.text == text:
				alert_label.visible = false
		)

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
		if GameManager.selected_game_mode == GameManager.GameMode.PVP_DUEL:
			wave_label.text = "⚔️ 1v1 PVP DUEL | مبارزة 1 ضد 1 ⚔️"
		elif GameManager.selected_game_mode == GameManager.GameMode.TRAINING:
			wave_label.text = "🎯 طور التدريب الحر (Training Grounds) | ذخيرة غير محدودة"
		elif wave > max_w:
			wave_label.text = "⚔️ TITAN BOSS BATTLE ⚔️"
		else:
			wave_label.text = "Wave %d / %d | Minions Left: %d" % [wave, max_w, left]

func _on_game_over(is_victory: bool) -> void:
	if end_screen:
		end_screen.visible = true
		if GameManager.selected_game_mode == GameManager.GameMode.PVP_DUEL:
			if is_victory:
				end_title.text = "🏆 VICTORY! فزت بالمبارزة 1v1! 🏆"
				end_title.modulate = Color.GREEN
				end_desc.text = "You eliminated your opponent in the 1v1 Duel!\nاضغط للعودة إلى الغرفة لمبارزة جديدة!"
			else:
				end_title.text = "💀 DEFEAT! خسرت في المبارزة! 💀"
				end_title.modulate = Color.RED
				end_desc.text = "You were eliminated in the 1v1 Duel.\nاضغط للعودة إلى الغرفة لمبارزة جديدة!"
			if try_again_btn:
				try_again_btn.visible = false
		else:
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
