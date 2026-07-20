extends TextureRect

signal pressed(is_pressed: bool)

@export var action_name: String = "A"
@export var auto_update: bool = true

func _ready():
	if auto_update:
		ControllerManager.controller_type_changed.connect(_on_controller_type_changed)
		_update_glyph()
	
	self.mouse_filter = Control.MOUSE_FILTER_STOP
	self.gui_input.connect(_on_gui_input)
	
	# Initial pivot for scaling
	self.pivot_offset = custom_minimum_size / 2.0

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		apply_feedback(event.pressed)
		emit_signal("pressed", event.pressed)
		
		if event.pressed:
			_simulate_action()

func _simulate_action():
	var actions = []
	match action_name:
		"A": actions = ["ui_accept"]
		"B": actions = ["go_back", "ui_cancel"]
		"X": actions = ["ui_select"]
		"Y": actions = ["ui_secondary"]
		"L1": actions = ["section_previous", "previous_tab"]
		"R1": actions = ["section_next", "next_tab"]
		"L2": actions = ["ui_page_up", "previous_tab"]
		"R2": actions = ["ui_page_down", "next_tab"]
		"Menu": actions = ["open_settings"]
	
	for action in actions:
		var a = InputEventAction.new()
		a.action = action
		a.pressed = true
		Input.parse_input_event(a)
		
		var r = InputEventAction.new()
		r.action = action
		r.pressed = false
		Input.parse_input_event(r)

func _on_controller_type_changed(_type: String):
	_update_glyph()

func _update_glyph():
	var path = ControllerManager.get_glyph_path(action_name)
	self.texture = load(path)

func _input(event: InputEvent):
	if not visible or not is_visible_in_tree(): return
	
	if event is InputEventJoypadButton:
		var btn_name = _get_button_name_from_index(event.button_index)
		if btn_name == action_name:
			apply_feedback(event.pressed)
			emit_signal("pressed", event.pressed)

func _get_button_name_from_index(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1"
		JOY_BUTTON_START: return "Menu"
		4: return "Menu" # Also map select/back to Menu just in case
	return ""

func apply_feedback(is_pressed: bool):
	var target_scale = Vector2(1.2, 1.2) if is_pressed else Vector2(1.0, 1.0)
	var target_mod = Color(1.5, 1.5, 1.5, 1.0) if is_pressed else Color(1, 1, 1, 1)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", target_scale, 0.1)
	tween.tween_property(self, "modulate", target_mod, 0.1)
	self.pivot_offset = size / 2.0
