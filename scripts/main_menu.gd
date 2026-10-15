extends Control

# MainMenu Script (res://scripts/main_menu.gd)
# Widescreen landscape UI with character preview, Create Room, Join Room, and audio cues.

@onready var name_input: LineEdit = $HBox/RightCol/Panel/VBox/NameInput
@onready var class_option: OptionButton = $HBox/LeftCol/Panel/VBox/ClassOption
@onready var class_desc: Label = $HBox/LeftCol/Panel/VBox/ClassDesc
@onready var class_stats: Label = $HBox/LeftCol/Panel/VBox/ClassStats

@onready var ip_input: LineEdit = $HBox/RightCol/Panel/VBox/JoinBox/IPInput
@onready var create_room_btn: Button = $HBox/RightCol/Panel/VBox/CreateRoomBtn
@onready var join_room_btn: Button = $HBox/RightCol/Panel/VBox/JoinBox/JoinRoomBtn
@onready var status_label: Label = $HBox/RightCol/Panel/VBox/StatusLabel
@onready var voice_banner: Label = $TopBar/VoiceBanner

var selected_class: int = 0

func _ready() -> void:
	# Setup classes
	class_option.clear()
	for id in GameManager.CLASSES:
		var c = GameManager.CLASSES[id]
		class_option.add_item(c["name"], id)
	
	class_option.item_selected.connect(_on_class_selected)
	_update_class_info(0)
	
	create_room_btn.pressed.connect(_on_create_room_pressed)
	join_room_btn.pressed.connect(_on_join_room_pressed)
	
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	var default_ip = NetworkManager.get_local_ip()
	ip_input.placeholder_text = "Host IP (e.g. %s)" % default_ip
	_speak_prompt("Welcome to CyberFort 3D! Choose Create Room or Join Room.")

func _speak_prompt(text: String) -> void:
	if voice_banner:
		voice_banner.text = "🎙️ " + text
		voice_banner.visible = true

func _on_class_selected(index: int) -> void:
	selected_class = index
	_update_class_info(index)

func _update_class_info(index: int) -> void:
	var c = GameManager.CLASSES[index]
	class_desc.text = c["role"]
	class_stats.text = "Health: %d HP  |  Speed: %.1f m/s  |  Build Skill: Expert" % [c["hp"], c["speed"]]

func _get_player_name() -> String:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		p_name = "Agent_%d" % randi_range(100, 999)
	return p_name

func _on_create_room_pressed() -> void:
	_speak_prompt("Creating Room... Waiting for squad members to join!")
	status_label.text = "Creating Room..."
	var p_name = _get_player_name()
	var err = NetworkManager.create_room(p_name, selected_class)
	if err == OK:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	else:
		status_label.text = "Failed to create room: %s" % error_string(err)

func _on_join_room_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	
	_speak_prompt("Joining Room at %s..." % ip)
	status_label.text = "Connecting to Room at %s..." % ip
	var p_name = _get_player_name()
	var err = NetworkManager.join_room(ip, p_name, selected_class)
	if err != OK:
		status_label.text = "Connection error: %s" % error_string(err)

func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_connection_failed() -> void:
	_speak_prompt("Failed to join room! Check host IP and Wi-Fi.")
	status_label.text = "Room connection failed. Make sure Room Host is running."
