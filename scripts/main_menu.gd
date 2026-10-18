extends Control

# MainMenu Controller (res://scripts/main_menu.gd)
# Features Start/Settings/Exit flow, Singleplayer/Multiplayer Hub,
# Audio volume controls & Redeem Code system, Accounts (Sign In/Up/Out),
# and Friends List & Party Invitations.

# --- View Containers ---
@onready var view_home: Control = $ViewHome
@onready var view_mode_select: Control = $ViewModeSelect
@onready var view_settings: Control = $ViewSettings
@onready var view_account: Control = $ViewAccount
@onready var view_friends: Control = $ViewFriends

# --- Top Header ---
@onready var account_pill_btn: Button = $TopHeader/HeaderHBox/AccountPillBtn
@onready var friends_pill_btn: Button = $TopHeader/HeaderHBox/FriendsPillBtn

# --- Home Buttons ---
@onready var start_btn: Button = $ViewHome/HomeCenterBox/StartBtn
@onready var settings_btn: Button = $ViewHome/HomeCenterBox/SettingsBtn
@onready var friends_btn: Button = $ViewHome/HomeCenterBox/FriendsBtn
@onready var exit_btn: Button = $ViewHome/HomeCenterBox/ExitBtn

# --- Mode Select Views & Controls ---
@onready var mode_back_btn: Button = $ViewModeSelect/ModeNavBar/ModeBackBtn
@onready var class_option: OptionButton = $ViewModeSelect/HBox/LeftCol/Panel/VBox/ClassOption
@onready var char_preview: CharacterPreview = $ViewModeSelect/HBox/LeftCol/Panel/VBox/PreviewContainer/SubViewport/CharacterPreview
@onready var class_desc: Label = $ViewModeSelect/HBox/LeftCol/Panel/VBox/ClassDesc
@onready var class_stats: Label = $ViewModeSelect/HBox/LeftCol/Panel/VBox/ClassStats
@onready var bot_option: OptionButton = $ViewModeSelect/HBox/LeftCol/Panel/VBox/BotOption
@onready var solo_wave_btn: Button = $ViewModeSelect/HBox/LeftCol/Panel/VBox/SoloWaveBtn
@onready var training_btn: Button = $ViewModeSelect/HBox/LeftCol/Panel/VBox/TrainingBtn

@onready var name_input: LineEdit = $ViewModeSelect/HBox/RightCol/Panel/VBox/NameHBox/NameInput
@onready var map_option: OptionButton = $ViewModeSelect/HBox/RightCol/Panel/VBox/MapHBox/MapOption
@onready var create_room_btn: Button = $ViewModeSelect/HBox/RightCol/Panel/VBox/CreateRoomBtn
@onready var code_input: LineEdit = $ViewModeSelect/HBox/RightCol/Panel/VBox/JoinBox/CodeInput
@onready var join_room_btn: Button = $ViewModeSelect/HBox/RightCol/Panel/VBox/JoinBox/JoinRoomBtn
@onready var bt_btn: Button = $ViewModeSelect/HBox/RightCol/Panel/VBox/QuickButtonsBox/BluetoothBtn
@onready var scan_btn: Button = $ViewModeSelect/HBox/RightCol/Panel/VBox/QuickButtonsBox/ScanBtn
@onready var party_play_btn: Button = $ViewModeSelect/HBox/RightCol/Panel/VBox/PartyPlayBtn
@onready var voice_banner: Label = $ViewModeSelect/HBox/RightCol/Panel/VBox/VoiceBanner
@onready var status_label: Label = $ViewModeSelect/HBox/RightCol/Panel/VBox/StatusLabel

# --- Settings Controls ---
@onready var settings_back_btn: Button = $ViewSettings/SettingsNavBar/SettingsBackBtn
@onready var music_slider: HSlider = $ViewSettings/SettingsCard/VBox/MusicHBox/MusicSlider
@onready var music_val_label: Label = $ViewSettings/SettingsCard/VBox/MusicHBox/MusicValLabel
@onready var sfx_slider: HSlider = $ViewSettings/SettingsCard/VBox/SfxHBox/SfxSlider
@onready var sfx_val_label: Label = $ViewSettings/SettingsCard/VBox/SfxHBox/SfxValLabel
@onready var mute_check: CheckBox = $ViewSettings/SettingsCard/VBox/MuteCheck
@onready var redeem_input: LineEdit = $ViewSettings/SettingsCard/VBox/RedeemHBox/RedeemInput
@onready var redeem_btn: Button = $ViewSettings/SettingsCard/VBox/RedeemHBox/RedeemBtn
@onready var redeem_status: Label = $ViewSettings/SettingsCard/VBox/RedeemStatus

# --- Account Controls ---
@onready var account_back_btn: Button = $ViewAccount/AccountNavBar/AccountBackBtn
@onready var logged_in_box: VBoxContainer = $ViewAccount/AccountCard/VBox/LoggedInBox
@onready var welcome_label: Label = $ViewAccount/AccountCard/VBox/LoggedInBox/WelcomeUserLabel
@onready var heroes_status_label: Label = $ViewAccount/AccountCard/VBox/LoggedInBox/HeroesStatusLabel
@onready var sign_out_btn: Button = $ViewAccount/AccountCard/VBox/LoggedInBox/SignOutBtn
@onready var auth_box: VBoxContainer = $ViewAccount/AccountCard/VBox/AuthBox
@onready var tab_sign_in_btn: Button = $ViewAccount/AccountCard/VBox/AuthBox/AuthModeHBox/TabSignInBtn
@onready var tab_sign_up_btn: Button = $ViewAccount/AccountCard/VBox/AuthBox/AuthModeHBox/TabSignUpBtn
@onready var auth_title_label: Label = $ViewAccount/AccountCard/VBox/AuthBox/AuthTitleLabel
@onready var auth_username_input: LineEdit = $ViewAccount/AccountCard/VBox/AuthBox/AuthUsernameInput
@onready var auth_password_input: LineEdit = $ViewAccount/AccountCard/VBox/AuthBox/AuthPasswordInput
@onready var auth_submit_btn: Button = $ViewAccount/AccountCard/VBox/AuthBox/AuthSubmitBtn
@onready var auth_status_label: Label = $ViewAccount/AccountCard/VBox/AuthBox/AuthStatusLabel

# --- Friends & Party Controls ---
@onready var friends_back_btn: Button = $ViewFriends/FriendsNavBar/FriendsBackBtn
@onready var friend_name_input: LineEdit = $ViewFriends/FriendsCard/VBox/AddFriendHBox/FriendNameInput
@onready var add_friend_btn: Button = $ViewFriends/FriendsCard/VBox/AddFriendHBox/AddFriendBtn
@onready var friends_status_label: Label = $ViewFriends/FriendsCard/VBox/FriendsStatusLabel
@onready var friends_list_vbox: VBoxContainer = $ViewFriends/FriendsCard/VBox/FriendsListScroll/FriendsListVBox
@onready var party_members_label: Label = $ViewFriends/FriendsCard/VBox/PartySection/PartyVBox/PartyMembersLabel
@onready var start_with_party_btn: Button = $ViewFriends/FriendsCard/VBox/PartySection/PartyVBox/PartyActionsHBox/StartWithPartyBtn
@onready var leave_party_btn: Button = $ViewFriends/FriendsCard/VBox/PartySection/PartyVBox/PartyActionsHBox/LeavePartyBtn

var selected_class: int = 0
var is_signup_mode: bool = false

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	
	# Show Home by default
	_switch_view(view_home)
	
	# Connect Navigation buttons
	start_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_mode_select)
	)
	settings_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_settings)
	)
	friends_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_friends)
	)
	exit_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		get_tree().quit()
	)
	
	account_pill_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_account)
	)
	friends_pill_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_friends)
	)
	
	mode_back_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_home)
	)
	settings_back_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_home)
	)
	account_back_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_home)
	)
	friends_back_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_home)
	)
	
	_setup_settings_view()
	_setup_account_view()
	_setup_friends_view()
	_setup_mode_select_view()
	
	_refresh_top_pills()

func _switch_view(target_view: Control) -> void:
	view_home.visible = (target_view == view_home)
	view_mode_select.visible = (target_view == view_mode_select)
	view_settings.visible = (target_view == view_settings)
	view_account.visible = (target_view == view_account)
	view_friends.visible = (target_view == view_friends)
	
	if target_view == view_account:
		_refresh_account_ui()
	elif target_view == view_friends:
		_refresh_friends_ui()
	elif target_view == view_mode_select:
		_refresh_hero_options()

func _refresh_top_pills() -> void:
	if AccountManager.is_logged_in():
		account_pill_btn.text = "👤 " + AccountManager.get_current_user()
		account_pill_btn.modulate = Color(0.2, 0.95, 0.6)
		name_input.text = AccountManager.get_current_user()
	else:
		account_pill_btn.text = "👤 ضيف (Guest)"
		account_pill_btn.modulate = Color.WHITE
		if name_input.text.is_empty():
			name_input.text = "Guest_%d" % (randi() % 900 + 100)
	
	var friends = AccountManager.get_friends()
	friends_pill_btn.text = "👥 الأصدقاء (%d)" % friends.size()

# ==============================================================================
# 1. SETTINGS & AUDIO & REDEEM CODE
# ==============================================================================
func _setup_settings_view() -> void:
	music_slider.value = AudioManager.music_volume
	music_val_label.text = "%d%%" % int(AudioManager.music_volume * 100)
	music_slider.value_changed.connect(func(v: float):
		AudioManager.set_music_volume(v)
		music_val_label.text = "%d%%" % int(v * 100)
	)
	
	sfx_slider.value = AudioManager.sfx_volume
	sfx_val_label.text = "%d%%" % int(AudioManager.sfx_volume * 100)
	sfx_slider.value_changed.connect(func(v: float):
		AudioManager.set_sfx_volume(v)
		sfx_val_label.text = "%d%%" % int(v * 100)
	)
	
	mute_check.button_pressed = AudioManager.is_muted
	mute_check.toggled.connect(func(b: bool):
		AudioManager.set_muted(b)
	)
	
	redeem_btn.pressed.connect(_on_redeem_pressed)
	redeem_input.text_submitted.connect(func(_t): _on_redeem_pressed())

func _on_redeem_pressed() -> void:
	var code = redeem_input.text
	var result = AccountManager.redeem_code(code)
	if result["success"]:
		AudioManager.play_sfx("redeem")
		redeem_status.text = result["message"]
		redeem_status.modulate = Color(0.2, 0.95, 0.6)
		redeem_input.text = ""
		_refresh_hero_options()
	else:
		AudioManager.play_sfx("error")
		redeem_status.text = result["message"]
		redeem_status.modulate = Color(1.0, 0.4, 0.4)

# ==============================================================================
# 2. ACCOUNTS (SIGN IN, SIGN UP, SIGN OUT)
# ==============================================================================
func _setup_account_view() -> void:
	tab_sign_in_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		is_signup_mode = false
		_update_auth_tab_styles()
	)
	tab_sign_up_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		is_signup_mode = true
		_update_auth_tab_styles()
	)
	
	auth_submit_btn.pressed.connect(_on_auth_submit)
	sign_out_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		AccountManager.sign_out()
		_refresh_top_pills()
		_refresh_account_ui()
	)
	
	AccountManager.user_logged_in.connect(func(_u):
		_refresh_top_pills()
		_refresh_account_ui()
	)
	AccountManager.user_logged_out.connect(func():
		_refresh_top_pills()
		_refresh_account_ui()
	)

func _update_auth_tab_styles() -> void:
	auth_status_label.text = ""
	if is_signup_mode:
		auth_title_label.text = "إنشاء حساب جديد للاحتفاظ بأبطالك وأصدقائك:"
		auth_submit_btn.text = "➕ إنشاء حساب (Sign Up)"
		tab_sign_up_btn.modulate = Color(0.2, 0.95, 0.6)
		tab_sign_in_btn.modulate = Color.WHITE
	else:
		auth_title_label.text = "تسجيل الدخول إلى حسابك المسجل:"
		auth_submit_btn.text = "🔑 تسجيل الدخول (Sign In)"
		tab_sign_in_btn.modulate = Color(0, 0.9, 1.0)
		tab_sign_up_btn.modulate = Color.WHITE

func _refresh_account_ui() -> void:
	if AccountManager.is_logged_in():
		logged_in_box.visible = true
		auth_box.visible = false
		var user = AccountManager.get_current_user()
		welcome_label.text = "✅ مرحباً بك يا بطل: " + user
		
		var unlocked_heroes: Array = []
		for id in GameManager.CLASSES:
			if GameManager.is_hero_unlocked(id):
				unlocked_heroes.append(GameManager.CLASSES[id]["name"])
		heroes_status_label.text = "الأبطال المتاحون لك: " + ", ".join(unlocked_heroes)
	else:
		logged_in_box.visible = false
		auth_box.visible = true
		_update_auth_tab_styles()

func _on_auth_submit() -> void:
	var u = auth_username_input.text
	var p = auth_password_input.text
	
	var res: Dictionary
	if is_signup_mode:
		res = AccountManager.sign_up(u, p)
	else:
		res = AccountManager.sign_in(u, p)
	
	if res["success"]:
		AudioManager.play_sfx("success")
		auth_status_label.text = res["message"]
		auth_status_label.modulate = Color.GREEN
		auth_username_input.text = ""
		auth_password_input.text = ""
	else:
		AudioManager.play_sfx("error")
		auth_status_label.text = res["message"]
		auth_status_label.modulate = Color.RED

# ==============================================================================
# 3. FRIENDS & PARTY SYSTEM
# ==============================================================================
func _setup_friends_view() -> void:
	add_friend_btn.pressed.connect(_on_add_friend_pressed)
	friend_name_input.text_submitted.connect(func(_t): _on_add_friend_pressed())
	
	start_with_party_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_mode_select)
		_on_create_room_pressed()
	)
	
	leave_party_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		AccountManager.leave_party()
		_refresh_friends_ui()
	)
	
	AccountManager.friends_updated.connect(func(_fl): _refresh_friends_ui())
	AccountManager.party_updated.connect(func(_pm): _refresh_friends_ui())

func _on_add_friend_pressed() -> void:
	var f_name = friend_name_input.text
	var res = AccountManager.add_friend(f_name)
	if res["success"]:
		AudioManager.play_sfx("success")
		friends_status_label.text = res["message"]
		friends_status_label.modulate = Color.GREEN
		friend_name_input.text = ""
		_refresh_friends_ui()
	else:
		AudioManager.play_sfx("error")
		friends_status_label.text = res["message"]
		friends_status_label.modulate = Color.YELLOW

func _refresh_friends_ui() -> void:
	for child in friends_list_vbox.get_children():
		child.queue_free()
	
	var friends = AccountManager.get_friends()
	if friends.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "لا يوجد أصدقاء مضافون بعد. اكتب اسم صديقك أعلاه لإضافته!"
		empty_lbl.modulate = Color(0.7, 0.75, 0.85)
		friends_list_vbox.add_child(empty_lbl)
	else:
		for f in friends:
			var row = HBoxContainer.new()
			row.custom_minimum_size = Vector2(0, 42)
			
			var name_lbl = Label.new()
			name_lbl.text = "👤 " + str(f)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(name_lbl)
			
			var invite_btn = Button.new()
			invite_btn.text = "🎉 دعوة لبارتي"
			invite_btn.custom_minimum_size = Vector2(130, 36)
			invite_btn.pressed.connect(func():
				AudioManager.play_sfx("success")
				var inv_res = AccountManager.invite_to_party(str(f))
				friends_status_label.text = inv_res["message"]
				friends_status_label.modulate = Color.GREEN
				_refresh_friends_ui()
			)
			row.add_child(invite_btn)
			
			var del_btn = Button.new()
			del_btn.text = "❌"
			del_btn.custom_minimum_size = Vector2(40, 36)
			del_btn.pressed.connect(func():
				AudioManager.play_sfx("click")
				AccountManager.remove_friend(str(f))
				_refresh_friends_ui()
			)
			row.add_child(del_btn)
			
			friends_list_vbox.add_child(row)
	
	# Update party
	var p_members = AccountManager.current_party
	party_members_label.text = "البارتي الحالي (%d): " % p_members.size() + ", ".join(p_members)
	_refresh_top_pills()

# ==============================================================================
# 4. MODE SELECTION (SINGLEPLAYER VS MULTIPLAYER)
# ==============================================================================
func _setup_mode_select_view() -> void:
	# Maps
	if map_option:
		map_option.clear()
		for m_id in GameManager.MAPS:
			map_option.add_item(GameManager.MAPS[m_id]["name"], m_id)
		map_option.select(GameManager.selected_map_id)
		map_option.item_selected.connect(func(idx: int):
			GameManager.selected_map_id = idx
		)
	
	_refresh_hero_options()
	class_option.item_selected.connect(_on_class_selected)
	_update_class_info(0)
	
	# Solo buttons
	solo_wave_btn.pressed.connect(_on_solo_wave_pressed)
	training_btn.pressed.connect(_on_training_pressed)
	
	# Multiplayer buttons
	create_room_btn.pressed.connect(_on_create_room_pressed)
	join_room_btn.pressed.connect(_on_join_room_pressed)
	bt_btn.pressed.connect(_on_bluetooth_btn_pressed)
	scan_btn.pressed.connect(_on_scan_btn_pressed)
	party_play_btn.pressed.connect(func():
		_speak_prompt("Starting multiplayer room with Party members...")
		_on_create_room_pressed()
	)
	
	NetworkManager.room_discovered.connect(_on_room_discovered)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	_speak_prompt("Welcome! Select your hero, then choose Singleplayer or Multiplayer.")

func _refresh_hero_options() -> void:
	if not class_option:
		return
	var prev_idx = class_option.selected
	class_option.clear()
	for id in GameManager.CLASSES:
		var c = GameManager.CLASSES[id]
		if not GameManager.is_hero_unlocked(id):
			var unlock_hint = ""
			match id:
				1: unlock_hint = "Win Wave 1"
				2: unlock_hint = "Win Wave 2"
				3: unlock_hint = "Beat Bosses / Redeem ADMIN2026"
			class_option.add_item("🔒 %s (Locked - %s)" % [c["name"], unlock_hint], id)
		else:
			class_option.add_item(c["name"], id)
	
	if prev_idx >= 0 and prev_idx < class_option.item_count:
		class_option.select(prev_idx)
	else:
		class_option.select(0)
	
	if bot_option:
		bot_option.clear()
		bot_option.add_item("🚫 بدون بوت (Solo - No Bot)", -1)
		for id in GameManager.CLASSES:
			var c = GameManager.CLASSES[id]
			if not GameManager.is_hero_unlocked(id):
				bot_option.add_item("🔒 %s (مقفول)" % c["name"], id)
			else:
				bot_option.add_item("🤖 " + c["name"], id)
		
		if not GameManager.bot_enabled:
			bot_option.select(0)
		else:
			bot_option.select(GameManager.bot_class_id + 1)
		
		bot_option.item_selected.connect(func(idx: int):
			if idx == 0:
				GameManager.bot_enabled = false
			else:
				var class_id = idx - 1
				if not GameManager.is_hero_unlocked(class_id):
					status_label.text = "🔒 هذا البوت مقفول حالياً! تم اختيار ولد البطيخ."
					status_label.modulate = Color.YELLOW
					bot_option.select(1)
					GameManager.bot_enabled = true
					GameManager.bot_class_id = 0
				else:
					GameManager.bot_enabled = true
					GameManager.bot_class_id = class_id
		)

func _speak_prompt(text: String) -> void:
	if voice_banner:
		voice_banner.text = "🎙️ " + text

func _on_class_selected(index: int) -> void:
	AudioManager.play_sfx("click")
	if not GameManager.is_hero_unlocked(index):
		var req_msg = ""
		match index:
			1: req_msg = "فوز بالجولة الأولى (Wave 1) أو استخدم كود BERRY2026!"
			2: req_msg = "فوز بالجولة الثانية (Wave 2) أو استخدم كود CITRUS2026!"
			3: req_msg = "اهزم البيج بوس أو استخدم كود ADMIN2026 في الإعدادات!"
		status_label.text = "🔒 البطل مقفول! " + req_msg
		status_label.modulate = Color.YELLOW
		_speak_prompt("Hero locked! " + req_msg)
		class_option.select(0)
		selected_class = 0
		_update_class_info(0)
		return
	
	selected_class = index
	_update_class_info(index)

func _update_class_info(index: int) -> void:
	var c = GameManager.CLASSES[index]
	if not GameManager.is_hero_unlocked(index):
		class_desc.text = "🔒 مقفول! يمكنك فتحه بالفوز بالجولات أو استرداد الكود من الإعدادات."
		class_stats.text = "HP: %d  |  Speed: %.1f m/s  |  Status: 🔒 LOCKED" % [c["hp"], c["speed"]]
	else:
		class_desc.text = c["role"]
		class_stats.text = "HP: %d  |  Speed: %.1f m/s  |  Hero: %s" % [c["hp"], c["speed"], c["name"]]
	
	if char_preview:
		char_preview.update_class_visual(index)

func _validate_player_name() -> String:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		status_label.text = "⚠️ يجب كتابة اسمك أولاً للدخول إلى اللعبة!"
		status_label.modulate = Color.RED
		_speak_prompt("Please enter your name first!")
		name_input.grab_focus()
		return ""
	return p_name

func _on_solo_wave_pressed() -> void:
	AudioManager.play_sfx("click")
	var p_name = _validate_player_name()
	if p_name.is_empty():
		return
	_speak_prompt("Starting Solo Wave Defense...")
	GameManager.selected_game_mode = GameManager.GameMode.COOP_WAVES
	NetworkManager.leave_game()
	NetworkManager.local_player_name = p_name
	NetworkManager.local_class_id = selected_class
	GameManager.start_game_scene()

func _on_training_pressed() -> void:
	AudioManager.play_sfx("click")
	_speak_prompt("Entering Training Grounds...")
	GameManager.start_training_mode(selected_class)

func _on_create_room_pressed() -> void:
	AudioManager.play_sfx("click")
	var p_name = _validate_player_name()
	if p_name.is_empty():
		return
	
	var code = NetworkManager.generate_room_code()
	_speak_prompt("Room Created! Your Room Code is: #" + code)
	status_label.text = "Creating Room #%s..." % code
	status_label.modulate = Color.GREEN
	
	var err = NetworkManager.create_room(p_name, selected_class)
	if err == OK:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	else:
		status_label.text = "Error creating room: %s" % error_string(err)

func _on_join_room_pressed() -> void:
	AudioManager.play_sfx("click")
	var p_name = _validate_player_name()
	if p_name.is_empty():
		return
	
	var code = code_input.text.strip_edges().to_upper().replace("#", "")
	if code.is_empty():
		status_label.text = "⚠️ اكتب كود الغرفة (Room Code) للانضمام!"
		status_label.modulate = Color.YELLOW
		_speak_prompt("Please enter the Room Code!")
		code_input.grab_focus()
		return
	
	_speak_prompt("Joining Room #%s..." % code)
	status_label.text = "Connecting to Room #%s..." % code
	status_label.modulate = Color.CYAN
	
	var err = NetworkManager.join_room_with_code(code, p_name, selected_class)
	if err != OK:
		status_label.text = "Connection error: %s" % error_string(err)

func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_connection_failed() -> void:
	AudioManager.play_sfx("error")
	_speak_prompt("Could not connect to room!")
	status_label.text = "⚠️ تعذر الاتصال بالغرفة!\nتأكد أن كلا الجهازين على نفس شبكة الواي فاي أو الهوتسبوت/البلوتوث.\n💡 نصيحة: اكتب كود الغرفة أو رقم الآي بي (Host IP) مباشرة!"
	status_label.modulate = Color(1.0, 0.4, 0.4)

func _on_bluetooth_btn_pressed() -> void:
	AudioManager.play_sfx("click")
	var p_name = _validate_player_name()
	if p_name.is_empty():
		return
	
	_speak_prompt("Connecting to host via Bluetooth / Hotspot...")
	status_label.text = "🔵 جاري الاتصال المباشر عبر البلوتوث / هوتسبوت..."
	status_label.modulate = Color.CYAN
	
	var err = NetworkManager.join_room_with_code("BT", p_name, selected_class)
	if err != OK:
		status_label.text = "Connection error: %s" % error_string(err)

func _on_scan_btn_pressed() -> void:
	AudioManager.play_sfx("click")
	var p_name = _validate_player_name()
	if p_name.is_empty():
		return
	
	_speak_prompt("Scanning for nearby rooms...")
	status_label.text = "🔍 جاري البحث التلقائي عن غرف قريبة (Wi-Fi / Hotspot / Bluetooth)..."
	status_label.modulate = Color.YELLOW
	NetworkManager.start_discovery_listener()
	
	get_tree().create_timer(1.8).timeout.connect(func():
		if NetworkManager.udp_listener and NetworkManager.peer == null:
			var candidate_ip = NetworkManager.get_bluetooth_or_hotspot_host_ip()
			status_label.text = "🔵 محاولة الدخول لمضيف البلوتوث / هوتسبوت (%s)..." % candidate_ip
			status_label.modulate = Color.CYAN
			NetworkManager.stop_discovery_listener()
			NetworkManager.join_room_with_code("BT", p_name, selected_class)
	)

func _on_room_discovered(room_code: String, host_ip: String, _map_id: int) -> void:
	NetworkManager.stop_discovery_listener()
	status_label.text = "✅ تم العثور على غرفة: #%s (%s)! جاري الدخول..." % [room_code, host_ip]
	status_label.modulate = Color.GREEN
	code_input.text = "#" + room_code
	var p_name = _validate_player_name()
	if not p_name.is_empty():
		NetworkManager.join_room_with_code(room_code, p_name, selected_class)
