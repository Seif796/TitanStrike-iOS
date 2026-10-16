extends Control

# MainMenu Script (res://scripts/main_menu.gd)
# Features mandatory player name, live 3D character preview, Room Code system (no IP), and voice prompts.

@onready var name_input: LineEdit = $HBox/RightCol/Panel/VBox/NameInput
@onready var class_option: OptionButton = $HBox/LeftCol/Panel/VBox/ClassOption
@onready var bot_option: OptionButton = $HBox/LeftCol/Panel/VBox/BotOption
@onready var class_desc: Label = $HBox/LeftCol/Panel/VBox/ClassDesc
@onready var class_stats: Label = $HBox/LeftCol/Panel/VBox/ClassStats

@onready var code_input: LineEdit = $HBox/RightCol/Panel/VBox/JoinBox/CodeInput
@onready var create_room_btn: Button = $HBox/RightCol/Panel/VBox/CreateRoomBtn
@onready var join_room_btn: Button = $HBox/RightCol/Panel/VBox/JoinBox/JoinRoomBtn
@onready var status_label: Label = $HBox/RightCol/Panel/VBox/StatusLabel
@onready var voice_banner: Label = $TopBar/VoiceBanner

@onready var char_preview: CharacterPreview = $HBox/LeftCol/Panel/VBox/PreviewContainer/SubViewport/CharacterPreview

var selected_class: int = 0

func _ready() -> void:
	# Force landscape orientation
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	
	# Populate player classes
	class_option.clear()
	for id in GameManager.CLASSES:
		var c = GameManager.CLASSES[id]
		if not GameManager.is_hero_unlocked(id):
			var unlock_hint = ""
			match id:
				1: unlock_hint = "Win Round 1"
				2: unlock_hint = "Win Round 2"
				3: unlock_hint = "Beat Bosses"
			class_option.add_item("🔒 %s (Locked - %s)" % [c["name"], unlock_hint], id)
		else:
			class_option.add_item(c["name"], id)
	
	class_option.item_selected.connect(_on_class_selected)
	_update_class_info(0)
	
	# Populate Bot Companion — first item is "No Bot"
	if bot_option:
		bot_option.clear()
		bot_option.add_item("🚫 بدون بوت (Solo - No Bot)", -1)
		for id in GameManager.CLASSES:
			var c = GameManager.CLASSES[id]
			if not GameManager.is_hero_unlocked(id):
				bot_option.add_item("🔒 %s (مقفول)" % c["name"], id)
			else:
				bot_option.add_item("🤖 " + c["name"], id)
		
		# Ensure bot fallback to unlocked hero
		if not GameManager.is_hero_unlocked(GameManager.bot_class_id):
			GameManager.bot_class_id = 0 # Melon Boy
		
		# Reflect current saved state
		if not GameManager.bot_enabled:
			bot_option.select(0)
		else:
			bot_option.select(GameManager.bot_class_id + 1)
			
		bot_option.item_selected.connect(func(idx: int):
			if idx == 0:
				# No bot
				GameManager.bot_enabled = false
			else:
				var class_id = idx - 1
				if not GameManager.is_hero_unlocked(class_id):
					status_label.text = "🔒 هذا البوت مقفول حالياً! تم اختيار ولد البطيخ."
					status_label.modulate = Color.YELLOW
					bot_option.select(1) # Melon Boy
					GameManager.bot_enabled = true
					GameManager.bot_class_id = 0
				else:
					GameManager.bot_enabled = true
					GameManager.bot_class_id = class_id
		)
	
	create_room_btn.pressed.connect(_on_create_room_pressed)
	join_room_btn.pressed.connect(_on_join_room_pressed)
	
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	_speak_prompt("Welcome! Enter your name, select your hero, and Create Room or enter Room Code.")

func _speak_prompt(text: String) -> void:
	if voice_banner:
		voice_banner.text = "🎙️ " + text

func _on_class_selected(index: int) -> void:
	if not GameManager.is_hero_unlocked(index):
		var req_msg = ""
		match index:
			1: req_msg = "فوز بالجولة الأولى (Wave 1) لفتح بطلة الفراولة!"
			2: req_msg = "فوز بالجولة الثانية (Wave 2) لفتح البرتقال المدرّع!"
			3: req_msg = "فوز باللعبة وهزيمة البيج بوس لفتح الأدمن الخارق (500 HP)!"
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
		var req_desc = ""
		match index:
			1: req_desc = "🔒 مقفول! فوز بالجولة الأولى (Wave 1) لفتح بطلة الفراولة السريعة."
			2: req_desc = "🔒 مقفول! فوز بالجولة الثانية (Wave 2) لفتح البرتقال المدرّع العملاق."
			3: req_desc = "🔒 مقفول! عليك الفوز في لعبة كاملة وهزيمة البيج بوس لفتح الأدمن الخارق (500 HP)!"
		class_desc.text = req_desc
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

func _on_create_room_pressed() -> void:
	var p_name = _validate_player_name()
	if p_name.is_empty():
		return
	
	# Generate simple friendly Room Code
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
	_speak_prompt("Could not find room with this code!")
	status_label.text = "⚠️ لم نتمكن من العثور على الغرفة بهذا الكود! تأكد من تشغيل الغرفة ومن شبكة الـ Wi-Fi."
	status_label.modulate = Color.RED
