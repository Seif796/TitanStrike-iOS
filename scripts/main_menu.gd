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
@onready var check_update_btn: Button = $ViewSettings/SettingsCard/VBox/CheckUpdateBtn
@onready var server_state_label: Label = $ViewSettings/SettingsCard/VBox/ServerStatusHBox/ServerStateLabel
@onready var version_status_label: Label = $ViewSettings/SettingsCard/VBox/VersionStatusLabel

# --- Update Modal Controls ---
@onready var update_modal: Control = $UpdateModal
@onready var modal_title: Label = $UpdateModal/Card/VBox/ModalTitle
@onready var modal_version_tag: Label = $UpdateModal/Card/VBox/ModalVersionTag
@onready var changelog_label: Label = $UpdateModal/Card/VBox/ChangelogScroll/ChangelogLabel
@onready var progress_bar: ProgressBar = $UpdateModal/Card/VBox/ProgressBar
@onready var progress_label: Label = $UpdateModal/Card/VBox/ProgressLabel
@onready var update_now_btn: Button = $UpdateModal/Card/VBox/ButtonsHBox/UpdateNowBtn
@onready var update_later_btn: Button = $UpdateModal/Card/VBox/ButtonsHBox/UpdateLaterBtn

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
		if AccountManager.is_logged_in():
			AudioManager.play_sfx("click")
			_switch_view(view_home)
	)
	friends_back_btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		_switch_view(view_home)
	)
	
	_setup_settings_view()
	_setup_update_system()
	_setup_account_view()
	_setup_friends_view()
	_setup_mode_select_view()
	
	_refresh_top_pills()
	
	GameManager.classes_updated.connect(func():
		_refresh_hero_options()
		if not GameManager.is_hero_enabled(selected_class):
			var fallback_id = 0
			for id in GameManager.CLASSES:
				if GameManager.is_hero_enabled(id):
					fallback_id = id
					break
			_on_class_selected(fallback_id)
		else:
			_update_class_info(selected_class)
	)
	
	GameManager.server_announcement_received.connect(func(msg: String):
		if voice_banner:
			voice_banner.text = "📢 [السيرفر]: " + msg
	)
	
	# Mandatory Sign In / Sign Up at startup if not logged in
	if not AccountManager.is_logged_in():
		_switch_view(view_account)
	else:
		_switch_view(view_home)

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
		account_back_btn.visible = true
	else:
		account_pill_btn.text = "👤 تسجيل الدخول"
		account_pill_btn.modulate = Color(1.0, 0.85, 0.2)
		name_input.text = ""
		account_back_btn.visible = false
	
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
	
	# Server status indicator (Open in green / close in red)
	if server_state_label:
		server_state_label.text = "Open" if UpdateManager.is_server_open else "close"
		server_state_label.modulate = Color(0.2, 0.95, 0.5) if UpdateManager.is_server_open else Color(1.0, 0.25, 0.25)
	
	UpdateManager.server_status_updated.connect(func(is_open: bool, status_str: String):
		if server_state_label:
			server_state_label.text = status_str
			if is_open:
				server_state_label.modulate = Color(0.2, 0.95, 0.5)
			else:
				server_state_label.modulate = Color(1.0, 0.25, 0.25)
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
# 2. OTA UPDATE SYSTEM & SERVER
# ==============================================================================
func _setup_update_system() -> void:
	if check_update_btn:
		check_update_btn.pressed.connect(func():
			AudioManager.play_sfx("click")
			version_status_label.text = "🔍 جاري فحص التحديثات في الخلفية..."
			version_status_label.modulate = Color.YELLOW
			UpdateManager.check_for_updates()
		)
	
	_update_version_badge()
	
	UpdateManager.update_available.connect(_on_update_available)
	UpdateManager.update_checked.connect(_on_update_checked)
	UpdateManager.download_progress.connect(_on_update_download_progress)
	UpdateManager.download_failed.connect(_on_update_download_failed)
	UpdateManager.update_installed.connect(_on_update_installed)
	
	if update_later_btn:
		update_later_btn.pressed.connect(func():
			AudioManager.play_sfx("click")
			update_modal.visible = false
		)
	
	if update_now_btn:
		update_now_btn.pressed.connect(func():
			AudioManager.play_sfx("click")
			update_now_btn.disabled = true
			update_later_btn.disabled = true
			update_now_btn.text = "⏳ جاري التحميل من السيرفر..."
			progress_label.text = "بدء تنزيل حزمة التحديث..."
			progress_label.modulate = Color(0.3, 0.85, 1.0)
			UpdateManager.start_download_update()
		)

func _update_version_badge() -> void:
	if version_status_label:
		version_status_label.text = "حالة اللعبة: الإصدار v%s (Build %d) | متصل بخادم التحديثات" % [
			UpdateManager.current_version,
			UpdateManager.current_build
		]
		version_status_label.modulate = Color(0.2, 0.95, 0.6)

func _on_update_checked(has_update: bool, info: Dictionary) -> void:
	if not has_update:
		if info.has("error"):
			version_status_label.text = "⚠️ لم يتم العثور على تحديثات جديدة حالياً"
			version_status_label.modulate = Color(0.7, 0.8, 0.9)
		else:
			version_status_label.text = "✅ اللعبة على أحدث إصدار v%s (Build %d)" % [
				UpdateManager.current_version,
				UpdateManager.current_build
			]
			version_status_label.modulate = Color.GREEN

func _on_update_available(info: Dictionary) -> void:
	AudioManager.play_sfx("redeem")
	modal_version_tag.text = "الإصدار الجديد: v%s (Build %d) — %s" % [
		info.get("version", "1.1.0"),
		int(info.get("version_code", 2)),
		info.get("title", "تحديث جديد")
	]
	
	var changelog_items = info.get("changelog", [])
	var notes_text = ""
	if changelog_items is Array:
		for item in changelog_items:
			notes_text += "• " + str(item) + "\n"
	else:
		notes_text = str(changelog_items)
	changelog_label.text = notes_text
	
	var size_mb = round(float(info.get("file_size_bytes", 0)) / (1024.0 * 1024.0) * 100.0) / 100.0
	progress_label.text = "حجم التحديث: %.2f MB | جاهز للتحميل والتثبيت التلقائي." % size_mb
	progress_label.modulate = Color(0.3, 0.85, 1.0)
	progress_bar.value = 0.0
	
	update_now_btn.disabled = false
	update_later_btn.disabled = false
	update_now_btn.text = "🔄 تحديث اللعبة الآن (Update Now)"
	
	update_modal.visible = true

func _on_update_download_progress(downloaded: int, total: int, pct: float) -> void:
	progress_bar.value = pct * 100.0
	var dl_mb = float(downloaded) / (1024.0 * 1024.0)
	var tot_mb = float(total) / (1024.0 * 1024.0)
	progress_label.text = "جاري التحميل... %.1f / %.1f MB (%d%%)" % [dl_mb, tot_mb, int(pct * 100.0)]

func _on_update_download_failed(msg: String) -> void:
	AudioManager.play_sfx("error")
	progress_label.text = "❌ " + msg
	progress_label.modulate = Color.RED
	update_now_btn.disabled = false
	update_later_btn.disabled = false
	update_now_btn.text = "🔄 إعادة المحاولة (Retry)"

func _on_update_installed() -> void:
	AudioManager.play_sfx("success")
	progress_bar.value = 100.0
	progress_label.text = "✅ تم تثبيت التحديث بنجاح! جاري إعادة تشغيل اللعبة وتطبيق التحديث..."
	progress_label.modulate = Color.GREEN
	
	_update_version_badge()
	
	get_tree().create_timer(1.2).timeout.connect(func():
		get_tree().reload_current_scene()
	)

# ==============================================================================
# 3. ACCOUNTS (SIGN IN, SIGN UP, SIGN OUT)
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
		_switch_view(view_account)
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
		account_back_btn.visible = true
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
		account_back_btn.visible = false
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
		auth_status_label.text = res["message"] + " جاري تحويلك لبدء اللعبة..."
		auth_status_label.modulate = Color.GREEN
		auth_username_input.text = ""
		auth_password_input.text = ""
		_refresh_top_pills()
		_refresh_account_ui()
		# Immediately transition directly to Start screen (Mode Select) as requested!
		get_tree().create_timer(0.4).timeout.connect(func():
			_switch_view(view_mode_select)
		)
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
		if not GameManager.is_hero_enabled(id):
			class_option.add_item("⛔ %s (معطل من السيرفر)" % c["name"], id)
		elif not GameManager.is_hero_unlocked(id):
			var unlock_hint = ""
			match id:
				1: unlock_hint = "Win Wave 1"
				2: unlock_hint = "Win Wave 2"
				3: unlock_hint = "Beat Big Bosses to unlock"
			class_option.add_item("🔒 %s (Locked - %s)" % [c["name"], unlock_hint], id)
		else:
			class_option.add_item(c["name"], id)
	
	if prev_idx >= 0 and prev_idx < class_option.item_count and GameManager.is_hero_enabled(prev_idx):
		class_option.select(prev_idx)
	else:
		# Auto-select first enabled hero
		var first_enabled = 0
		for id in GameManager.CLASSES:
			if GameManager.is_hero_enabled(id):
				first_enabled = id
				break
		class_option.select(first_enabled)
		selected_class = first_enabled
	
	if bot_option:
		bot_option.clear()
		bot_option.add_item("🚫 بدون بوت (Solo - No Bot)", -1)
		for id in GameManager.CLASSES:
			var c = GameManager.CLASSES[id]
			if not GameManager.is_hero_enabled(id):
				bot_option.add_item("⛔ %s (معطل)" % c["name"], id)
			elif not GameManager.is_hero_unlocked(id):
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
				if not GameManager.is_hero_enabled(class_id):
					status_label.text = "⛔ هذا البوت معطل من السيرفر حالياً!"
					status_label.modulate = Color.RED
					bot_option.select(0)
					GameManager.bot_enabled = false
				elif not GameManager.is_hero_unlocked(class_id):
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
	if not GameManager.is_hero_enabled(index):
		status_label.text = "⛔ هذه الشخصية معطلة حالياً من لوحة تحكم السيرفر! اختر بطلاً آخر."
		status_label.modulate = Color(1.0, 0.3, 0.3)
		_speak_prompt("Hero disabled by server control center! Please select another hero.")
		
		var fallback_id = 0
		for id in GameManager.CLASSES:
			if GameManager.is_hero_enabled(id):
				fallback_id = id
				break
		class_option.select(fallback_id)
		selected_class = fallback_id
		_update_class_info(fallback_id)
		return

	if not GameManager.is_hero_unlocked(index):
		var req_msg = ""
		match index:
			1: req_msg = "فوز بالجولة الأولى (Wave 1) أو استرد كود الهدية السري لفتح بطلة الفراولة!"
			2: req_msg = "فوز بالجولة الثانية (Wave 2) أو استرد كود الهدية السري لفتح البرتقال المدرّع!"
			3: req_msg = "اهزم البيج بوس في الجولة الأخيرة لفتح بطل الأدمن الخارق!"
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
	if not GameManager.is_hero_enabled(index):
		class_desc.text = "⛔ هذه الشخصية معطلة مؤقتاً ومحجوبة بواسطة مدير السيرفر من الموقع."
		class_stats.text = "HP: %d  |  Speed: %.1f m/s  |  Status: ⛔ معطل من السيرفر" % [c["hp"], c["speed"]]
	elif not GameManager.is_hero_unlocked(index):
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
	status_label.text = "⚠️ تعذر الاتصال بالغرفة!\nتأكد أن كلا الجهازين متصلان بنفس الشبكة (Wi-Fi أو Hotspot/Bluetooth) وتأكد من كود الغرفة."
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
			status_label.text = "🔵 جاري الاتصال التلقائي بمضيف البلوتوث / هوتسبوت..."
			status_label.modulate = Color.CYAN
			NetworkManager.stop_discovery_listener()
			NetworkManager.join_room_with_code("BT", p_name, selected_class)
	)

func _on_room_discovered(room_code: String, _host_ip: String, _map_id: int) -> void:
	NetworkManager.stop_discovery_listener()
	status_label.text = "✅ تم العثور على غرفة: #%s! جاري الدخول..." % room_code
	status_label.modulate = Color.GREEN
	code_input.text = "#" + room_code
	var p_name = _validate_player_name()
	if not p_name.is_empty():
		NetworkManager.join_room_with_code(room_code, p_name, selected_class)
