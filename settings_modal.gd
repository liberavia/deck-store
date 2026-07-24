extends CanvasLayer

signal closed

@onready var close_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseButton
@onready var settings_container = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/SettingsMargin/VBoxContainer

var _previous_focus_owner: Control = null

func _ready():
	hide()
	close_button.pressed.connect(close_modal)
	
	# Close when clicking outside
	$ColorRect.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_modal()
	)
	
	_populate_settings()

func _populate_settings():
	# Clear placeholder
	for child in settings_container.get_children():
		child.queue_free()
		
	_create_check_setting("Play UI Sounds", "play_ui_sounds")
	_create_check_setting("Auto Refresh Installed Apps", "auto_refresh_installed")
	_create_check_setting("Add installed Apps automatically to Steam", "auto_add_to_steam")
	_create_check_setting("Show Steam Restart Warning", "show_steam_restart_warning")

func _create_check_setting(label_text: String, setting_key: String):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	
	var check = CheckButton.new()
	check.button_pressed = SettingsManager.get_setting(setting_key, true)
	check.toggled.connect(func(toggled_on): SettingsManager.set_setting(setting_key, toggled_on))
	
	# Add sound feedback when toggled (if enabled)
	check.focus_entered.connect(func(): if SettingsManager.get_setting("play_ui_sounds", true): get_node("/root/App/FocusSoundPlayer").play())
	check.pressed.connect(func(): if SettingsManager.get_setting("play_ui_sounds", true): get_node("/root/App/ButtonSoundPlayer").play())
	
	hbox.add_child(check)
	settings_container.add_child(hbox)

func _create_option_setting(label_text: String, setting_key: String, options: Array):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	
	var option_btn = OptionButton.new()
	for opt in options:
		option_btn.add_item(opt.capitalize())
	
	var current_val = SettingsManager.get_setting(setting_key, options[0])
	var idx = options.find(current_val)
	if idx >= 0:
		option_btn.select(idx)
		
	option_btn.item_selected.connect(func(index): SettingsManager.set_setting(setting_key, options[index]))
	
	option_btn.focus_entered.connect(func(): if SettingsManager.get_setting("play_ui_sounds", true): get_node("/root/App/FocusSoundPlayer").play())
	option_btn.pressed.connect(func(): if SettingsManager.get_setting("play_ui_sounds", true): get_node("/root/App/ButtonSoundPlayer").play())
	
	hbox.add_child(option_btn)
	settings_container.add_child(hbox)

func open_modal():
	_populate_settings()
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
