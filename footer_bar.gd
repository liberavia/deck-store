extends PanelContainer

@onready var container: HBoxContainer = %ActionContainer

var _current_actions: Array = []

func _ready():
	ControllerManager.controller_type_changed.connect(_on_controller_type_changed)

# Example: [{"button": "A", "label": "Select"}, {"button": "L1 / R1", "label": "Back"}]
func set_actions(actions: Array):
	_current_actions = actions
	_refresh_ui()

func _on_controller_type_changed(_type: String):
	_refresh_ui()

func _refresh_ui():
	# Clear existing children
	for child in container.get_children():
		child.queue_free()
	
	for action in _current_actions:
		var action_node = _create_action_item(action["button"], action["label"])
		container.add_child(action_node)

func _create_action_item(button_str: String, label_text: String) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Add spacing before item
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	hbox.add_child(spacer)
	
	# Split by "/" for multiple buttons
	var button_names = button_str.split("/")
	
	for i in range(button_names.size()):
		var b_name = button_names[i].strip_edges()
		
		# Button Icon (SVG)
		var glyph_rect = TextureRect.new()
		glyph_rect.name = "Glyph_" + b_name
		glyph_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Determine size based on button type
		if b_name.length() > 1:
			glyph_rect.custom_minimum_size = Vector2(50, 25)
		else:
			glyph_rect.custom_minimum_size = Vector2(30, 30)
		
		var glyph_path = ControllerManager.get_glyph_path(b_name)
		glyph_rect.texture = load(glyph_path)
		
		hbox.add_child(glyph_rect)
		
		# Add "/" separator label if not the last one
		if i < button_names.size() - 1:
			var sep = Label.new()
			sep.text = "/"
			hbox.add_child(sep)
	
	# Action Label
	var action_label = Label.new()
	action_label.text = label_text
	action_label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(action_label)
	
	return hbox

func _input(event: InputEvent):
	if event is InputEventJoypadButton:
		var btn_name = _get_button_name_from_index(event.button_index)
		if btn_name != "":
			_apply_feedback(btn_name, event.pressed)

func _get_button_name_from_index(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1"
		6: return "L2" 
		7: return "R2"
	return ""

func _apply_feedback(btn_name: String, pressed: bool):
	for hbox in container.get_children():
		if not hbox is HBoxContainer: continue
		
		for child in hbox.get_children():
			if child is TextureRect and child.name == "Glyph_" + btn_name:
				var target_scale = Vector2(1.2, 1.2) if pressed else Vector2(1.0, 1.0)
				var target_mod = Color(1.5, 1.5, 1.5, 1.0) if pressed else Color(1, 1, 1, 1)
				
				var tween = create_tween()
				tween.set_parallel(true)
				tween.tween_property(child, "scale", target_scale, 0.1)
				tween.tween_property(child, "modulate", target_mod, 0.1)
				child.pivot_offset = child.custom_minimum_size / 2.0
