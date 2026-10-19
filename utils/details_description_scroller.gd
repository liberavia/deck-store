extends ScrollContainer

var _focus_sound_player: AudioStreamPlayer
@export var focus_border_color: Color = Color.PURPLE
@export var focus_border_width: int = 3

var _original_panel_style: StyleBox


func _ready():
	self.focus_entered.connect(_on_focus_entered_sound)
	self.focus_mode = Control.FOCUS_ALL
	
	_original_panel_style = self.get_theme_stylebox("panel")
	
	self.focus_entered.connect(_on_focus_entered_visual)
	self.focus_exited.connect(_on_focus_exited_visual)

	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	if not _focus_sound_player:
		printerr("FocusSoundPlayer not found at /root/App/FocusSoundPlayer!")

func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()

func _input(event: InputEvent) -> void:
	if not self.has_focus() or ControllerManager.is_input_blocked():
		return
	
	if event.is_action_pressed("ui_page_down"):
		self.scroll_vertical += self.size.y
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_page_up"):
		self.scroll_vertical -= self.size.y
		get_viewport().set_input_as_handled()

func _on_focus_entered_visual():
	if _original_panel_style is StyleBoxFlat:
		var focused_style = _original_panel_style.duplicate() as StyleBoxFlat
		focused_style.border_color = focus_border_color
		focused_style.border_width_top = focus_border_width
		focused_style.border_width_left = focus_border_width
		focused_style.border_width_right = focus_border_width
		focused_style.border_width_bottom = focus_border_width
		self.add_theme_stylebox_override("panel", focused_style)
	else:
		printerr("Original panel style for ScrollContainer is not StyleBoxFlat, cannot add border reliably.")

func _on_focus_exited_visual():
	self.remove_theme_stylebox_override("panel")
