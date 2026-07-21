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
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE # Don't block
	
	# Add spacing before item
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)
	
	# Split by "/" for multiple buttons
	var button_names = button_str.split("/")
	
	for i in range(button_names.size()):
		var b_name = button_names[i].strip_edges()
		
		# Instantiate our interactive GlyphDisplay
		var glyph_scene = load("res://glyph_display.tscn")
		var glyph_instance = glyph_scene.instantiate()
		glyph_instance.name = "Glyph_" + b_name
		glyph_instance.action_name = b_name
		
		# Determine size based on button type
		if b_name.length() > 1:
			glyph_instance.custom_minimum_size = Vector2(50, 25)
		else:
			glyph_instance.custom_minimum_size = Vector2(30, 30)
		
		hbox.add_child(glyph_instance)
		
		# Add "/" separator label if not the last one
		if i < button_names.size() - 1:
			var sep = Label.new()
			sep.text = "/"
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(sep)
	
	# Action Label
	var action_label = Label.new()
	action_label.text = label_text
	action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
			if child.name == "Glyph_" + btn_name and child.has_method("apply_feedback"):
				child.apply_feedback(pressed)

func set_action_pulsing(btn_name: String, pulsing: bool):
	for hbox in container.get_children():
		if not hbox is HBoxContainer: continue
		for child in hbox.get_children():
			if child.name == "Glyph_" + btn_name:
				var action_label = hbox.get_child(hbox.get_child_count() - 1) as Label
				if pulsing:
					if not child.has_meta("is_pulsing") or not child.get_meta("is_pulsing"):
						child.set_meta("is_pulsing", true)
						_start_pulse(child)
						_start_pulse(action_label)
				else:
					child.set_meta("is_pulsing", false)
					if child.has_meta("pulse_tween"):
						var t = child.get_meta("pulse_tween") as Tween
						if is_instance_valid(t): t.kill()
						child.modulate.a = 1.0
					if action_label.has_meta("pulse_tween"):
						var t = action_label.get_meta("pulse_tween") as Tween
						if is_instance_valid(t): t.kill()
						action_label.modulate.a = 1.0

func _start_pulse(node: Control):
	var t = create_tween().set_loops()
	t.tween_property(node, "modulate:a", 0.4, 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	node.set_meta("pulse_tween", t)
