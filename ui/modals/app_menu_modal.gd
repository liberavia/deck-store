extends CanvasLayer

signal closed

@onready var close_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseButton
@onready var settings_container = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/AppMenuMargin/VBoxContainer

var _previous_focus_owner: Control = null

func _ready():
	hide()
	close_button.pressed.connect(close_modal)
	
	$ColorRect.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_modal()
	)
	
	_populate_menu()

func _populate_menu():
	for child in settings_container.get_children():
		child.queue_free()
		
	var quit_btn = Button.new()
	quit_btn.text = tr("BTN_QUIT_APP")
	quit_btn.custom_minimum_size = Vector2(0, 50)
	quit_btn.add_theme_font_size_override("font_size", 24)
	quit_btn.pressed.connect(func():
		if SettingsManager.get_setting("play_ui_sounds", true):
			get_node("/root/App/ButtonSoundPlayer").play()
		get_tree().quit()
	)
	quit_btn.focus_entered.connect(func():
		if SettingsManager.get_setting("play_ui_sounds", true):
			get_node("/root/App/FocusSoundPlayer").play()
	)
	settings_container.add_child(quit_btn)

func open_modal():
	if visible: return
	_previous_focus_owner = get_viewport().gui_get_focus_owner()
	show()
	
	if settings_container.get_child_count() > 0:
		settings_container.get_child(0).grab_focus()
	else:
		close_button.grab_focus()

func close_modal():
	if not visible: return
	hide()
	if is_instance_valid(_previous_focus_owner):
		_previous_focus_owner.grab_focus()
	emit_signal("closed")

func _unhandled_input(event: InputEvent):
	if visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_app_menu"):
			close_modal()
			get_viewport().set_input_as_handled()
