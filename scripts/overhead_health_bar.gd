extends Node3D
class_name OverheadHealthBar

# OverheadHealthBar Script (res://scripts/overhead_health_bar.gd)
# Renders a high-visibility billboarded 3D health bar and name tag above characters and enemies.

@onready var viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Sprite3D
@onready var name_label: Label = $SubViewport/Container/NameLabel
@onready var hp_bar: ProgressBar = $SubViewport/Container/HPBar
@onready var hp_label: Label = $SubViewport/Container/HPBar/HPLabel

var max_health: float = 100.0
var current_health: float = 100.0
var base_name: String = ""

func _ready() -> void:
	if viewport and sprite:
		sprite.texture = viewport.get_texture()
	update_health(current_health, max_health)

func set_entity_name(new_name: String, col: Color = Color.WHITE) -> void:
	base_name = new_name
	if name_label:
		name_label.text = new_name
		name_label.modulate = col

func update_health(current: float, max_val: float) -> void:
	current_health = max(0.0, current)
	max_health = max(1.0, max_val)
	
	if hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = current_health
		
		var pct = current_health / max_health
		var fill_style = hp_bar.get_theme_stylebox("fill").duplicate()
		if fill_style is StyleBoxFlat:
			if pct > 0.5:
				fill_style.bg_color = Color(0.18, 0.85, 0.25, 0.95) # Green
			elif pct > 0.25:
				fill_style.bg_color = Color(1.0, 0.75, 0.1, 0.95) # Amber
			else:
				fill_style.bg_color = Color(1.0, 0.18, 0.18, 0.95) # Critical Red
			hp_bar.add_theme_stylebox_override("fill", fill_style)
	
	if hp_label:
		hp_label.text = "%d / %d" % [int(ceil(current_health)), int(ceil(max_health))]

func set_downed(is_downed: bool) -> void:
	if is_downed:
		if name_label:
			name_label.text = "⚠️ " + base_name + " (REVIVE!)"
			name_label.modulate = Color(1.0, 0.2, 0.2)
	else:
		if name_label:
			name_label.text = base_name
			name_label.modulate = Color.WHITE

