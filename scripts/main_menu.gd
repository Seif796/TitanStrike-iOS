extends Control

# MainMenu Script (res://scripts/main_menu.gd)
# Features mandatory player name, live 3D character preview, Room Code system (no IP), and voice prompts.

@onready var name_input: LineEdit = $HBox/RightCol/Panel/VBox/NameInput
@onready var class_option: OptionButton = $HBox/LeftCol/Panel/VBox/ClassOption
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
	
	# Populate classes
	class_option.clear()
	for id in GameManager.CLASSES:
		var c = GameManager.CLASSES[id]
		if id == 3 and not GameManager.admin_unlocked:
			class_option.add_item("🔒 Admin (Locked - Win 1 Game to Unlock)", id)
		else:
			class_option.add_item(c["name"], id)
	
	class_option.item_selected.connect(_on_class_selected)
	_update_class_info(0)
	
	create_room_btn.pressed.connect(_on_create_room_pressed)
	join_room_btn.pressed.connect(_on_join_room_pressed)
	
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	_speak_prompt("Welcome! Enter your name, select your hero, and Create Room or enter Room Code.")

func _speak_prompt(text: String) -> void:
	if voice_banner:
		voice_banner.text = "🎙️ " + text

func _on_class_selected(index: int) -> void:
	if index == 3 and not GameManager.admin_unlocked:
		status_label.text = "🔒 شخصية Admin (500 HP) مقفولة! يجب الفوز في لعبة كاملة (هزيمة الـ 2 بيج بوس) لفتحها!"
		status_label.modulate = Color.YELLOW
		_speak_prompt("Admin hero is locked! Win 1 match to unlock.")
		class_option.select(0)
		selected_class = 0
		_update_class_info(0)
		return
	
	selected_class = index
	_update_class_info(index)

func _update_class_info(index: int) -> void:
	var c = GameManager.CLASSES[index]
	if index == 3 and not GameManager.admin_unlocked:
		class_desc.text = "🔒 مقفولة! عليك الفوز في لعبة كاملة والتغلب على الـ 3 موجات والاثنين بيج بوس لفتح الأدمن الخارق (500 HP)!"
		class_stats.text = "HP: 500  |  Speed: 9.2 m/s  |  Status: 🔒 LOCKED"
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
