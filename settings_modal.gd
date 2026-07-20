extends CanvasLayer

signal closed

@onready var close_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseButton

var _previous_focus_owner: Control = null

func _ready():
	hide()
	close_button.pressed.connect(close_modal)
	
	# Close when clicking outside
	$ColorRect.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_modal()
	)

func open_modal():
	_previous_focus_owner = get_viewport().gui_get_focus_owner()
	show()
	close_button.grab_focus()

func close_modal():
	hide()
	if is_instance_valid(_previous_focus_owner):
		_previous_focus_owner.grab_focus()
	emit_signal("closed")

func _unhandled_input(event):
	if visible and event.is_action_pressed("ui_cancel"):
		close_modal()
		get_viewport().set_input_as_handled()
