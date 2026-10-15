extends Control

# MainMenu Script (res://scripts/main_menu.gd)
# Character selection, hosting, joining via IP.

@onready var name_input: LineEdit = $Panel/VBox/NameInput
@onready var class_option: OptionButton = $Panel/VBox/ClassOption
@onready var class_desc: Label = $Panel/VBox/ClassDesc
@onready var ip_input: LineEdit = $Panel/VBox/JoinContainer/IPInput
@onready var host_btn: Button = $Panel/VBox/HostBtn
@onready var join_btn: Button = $Panel/VBox/JoinContainer/JoinBtn
@onready var status_label: Label = $Panel/VBox/StatusLabel

var selected_class: int = 0

func _ready() -> void:
	# Setup class options
	class_option.clear()
	for id in GameManager.CLASSES:
		var c = GameManager.CLASSES[id]
		class_option.add_item("%s (HP: %d, Spd: %.1f)" % [c["name"], c["hp"], c["speed"]], id)
	
	class_option.item_selected.connect(_on_class_selected)
	_update_class_info(0)
	
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	var default_ip = NetworkManager.get_local_ip()
	ip_input.placeholder_text = "Host IP (e.g. %s)" % default_ip

func _on_class_selected(index: int) -> void:
	selected_class = index
	_update_class_info(index)

func _update_class_info(index: int) -> void:
	var c = GameManager.CLASSES[index]
	class_desc.text = c["role"]

func _get_player_name() -> String:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		p_name = "Player_%d" % randi_range(100, 999)
	return p_name

func _on_host_pressed() -> void:
	status_label.text = "Starting Server..."
	var p_name = _get_player_name()
	var err = NetworkManager.host_game(p_name, selected_class)
	if err == OK:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	else:
		status_label.text = "Failed to host: %s" % error_string(err)

func _on_join_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	
	status_label.text = "Connecting to %s..." % ip
	var p_name = _get_player_name()
	var err = NetworkManager.join_game(ip, p_name, selected_class)
	if err != OK:
		status_label.text = "Connection error: %s" % error_string(err)

func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_connection_failed() -> void:
	status_label.text = "Failed to connect to host. Make sure host is running and IP is correct."

