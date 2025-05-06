# product_box.gd
extends Control

@onready var panel: Panel = $Panel
@onready var status_indicator: Control = $Panel/StatusIndicator

signal move_to_details_view(app_id: String, installed: bool)

var _original_panel_style: StyleBox
var _focus_sound_player: AudioStreamPlayer
var app_id: String = ""
var is_installed: bool = false

func _ready():
	if panel: _original_panel_style = panel.get_theme_stylebox("panel")
	else: printerr("Panel node not found in ProductBox!")

	self.focus_entered.connect(_on_focus_entered_visual)
	self.focus_exited.connect(_on_focus_exited_visual)
	self.focus_entered.connect(_on_focus_entered_sound)
	self.focus_mode = Control.FOCUS_ALL

	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	if not _focus_sound_player:
		printerr("FocusSoundPlayer not found at /root/App/FocusSoundPlayer!")

func set_app_id(assinged_id: String):
	app_id = assinged_id
		
func set_installed_status(installed_status: bool):
	is_installed = installed_status
	if is_instance_valid(status_indicator):
		status_indicator.visible = is_installed

func _unhandled_input(event: InputEvent):
	if not has_focus():
		return
		
	if event.is_action_pressed("ui_accept"):
		emit_signal("move_to_details_view", app_id, is_installed)

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
	panel.add_theme_stylebox_override("panel", _original_panel_style)

func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()
