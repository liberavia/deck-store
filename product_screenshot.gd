extends Control

@onready var panel: Panel = $MarginContainer/Panel
@onready var screenshot_rect: TextureRect = $MarginContainer/Panel/MarginContainer/Screenshot

var _original_panel_style: StyleBox
var _focus_sound_player: AudioStreamPlayer
	
func _ready():
	if panel: 
		_original_panel_style = panel.get_theme_stylebox("panel")
		# Ensure children don't block mouse events
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		for child in panel.get_children():
			if child is Control: child.mouse_filter = Control.MOUSE_FILTER_PASS
	else: 
		printerr("Panel node not found in ProductBox!")

	self.focus_entered.connect(_on_focus_entered_visual)
	self.focus_exited.connect(_on_focus_exited_visual)
	self.focus_entered.connect(_on_focus_entered_sound)
	self.mouse_entered.connect(func(): self.grab_focus())
	self.gui_input.connect(_on_gui_input)
	
	self.focus_mode = Control.FOCUS_ALL

	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	if not _focus_sound_player:
		printerr("FocusSoundPlayer not found at /root/App/FocusSoundPlayer!")

func _on_focus_entered_visual():
	if not is_instance_valid(panel): return
	if _original_panel_style is StyleBoxFlat:
		var focused_style = _original_panel_style.duplicate() as StyleBoxFlat
		focused_style.border_color = Color.PURPLE
		focused_style.border_width_top = 3 
		focused_style.border_width_left = 3 
		focused_style.border_width_right = 3 
		focused_style.border_width_bottom = 3 
		panel.add_theme_stylebox_override("panel", focused_style)
	else:
		panel.modulate = Color.REBECCA_PURPLE.lightened(0.6)

func _on_focus_exited_visual():
	if not is_instance_valid(panel): return
	panel.remove_theme_stylebox_override("panel")
	panel.modulate = Color(1, 1, 1)

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Simulate ui_accept to trigger the zoom logic in DetailsView
		var a = InputEventAction.new()
		a.action = "ui_accept"
		a.pressed = true
		Input.parse_input_event(a)
		get_viewport().set_input_as_handled()

func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()
