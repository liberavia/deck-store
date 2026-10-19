extends CanvasLayer

signal closed

@onready var close_button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseButton
@onready var settings_container = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/SettingsMargin/VBoxContainer

var _previous_focus_owner: Control = null
var _update_status_label: Label = null
var _update_action_button: Button = null

func _ready():
	hide()
	close_button.pressed.connect(close_modal)
	
	$ColorRect.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_modal()
	)
	
	if get_node_or_null("/root/SelfUpdateManager"):
		var sum = get_node("/root/SelfUpdateManager")
		sum.update_check_completed.connect(_on_self_update_check_completed)
		sum.update_download_progress.connect(_on_self_update_progress)
		sum.update_ready_to_restart.connect(_on_self_update_ready)
		sum.update_failed.connect(_on_self_update_failed)
	
	_populate_settings()

func _populate_settings():
	for child in settings_container.get_children():
		child.queue_free()
		
	_create_option_setting(tr("SETTINGS_LANGUAGE"), "language", ["auto", "en", "de", "fr", "es", "it", "pl", "uk"], ["Auto", "English", "Deutsch", "Français", "Español", "Italiano", "Polski", "Українська"])
	_create_check_setting(tr("SETTINGS_UI_SOUNDS"), "play_ui_sounds")
	_create_check_setting(tr("SETTINGS_AUTO_REFRESH"), "auto_refresh_installed")
	_create_check_setting(tr("SETTINGS_AUTO_ADD_STEAM"), "auto_add_to_steam")
	_create_check_setting(tr("SETTINGS_STEAM_WARNING"), "show_steam_restart_warning")
	_create_self_update_section()

func _create_self_update_section():
	var sep = HSeparator.new()
	settings_container.add_child(sep)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var sum = get_node_or_null("/root/SelfUpdateManager")
	var ver_str = sum.current_version if is_instance_valid(sum) else "v0.0.0"

	_update_status_label = Label.new()
	_update_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_status_label.text = "DeckStore Version: %s" % ver_str
	hbox.add_child(_update_status_label)

	_update_action_button = Button.new()
	_update_action_button.focus_entered.connect(func(): if SettingsManager.get_setting("play_ui_sounds", true): get_node("/root/App/FocusSoundPlayer").play())
	_update_action_button.pressed.connect(_on_update_action_button_pressed)
	hbox.add_child(_update_action_button)

	settings_container.add_child(hbox)
	_refresh_self_update_ui()

func _refresh_self_update_ui():
	if not is_instance_valid(_update_status_label) or not is_instance_valid(_update_action_button):
		return
	var sum = get_node_or_null("/root/SelfUpdateManager")
	if not is_instance_valid(sum):
		_update_action_button.visible = false
		return

	if sum.is_update_staged:
		_update_status_label.text = "Update %s ready!" % sum.latest_version
		_update_action_button.text = "Restart & Apply"
		_update_action_button.disabled = false
	elif sum.is_downloading:
		_update_action_button.text = "Updating..."
		_update_action_button.disabled = true
	elif sum.is_update_available:
		_update_status_label.text = "Update available: %s" % sum.latest_version
		_update_action_button.text = "Install Update"
		_update_action_button.disabled = false
	else:
		_update_status_label.text = "DeckStore Version: %s" % sum.current_version
		_update_action_button.text = "Check for Updates"
		_update_action_button.disabled = false

func _on_update_action_button_pressed():
	if SettingsManager.get_setting("play_ui_sounds", true):
		get_node("/root/App/ButtonSoundPlayer").play()
	var sum = get_node_or_null("/root/SelfUpdateManager")
	if not is_instance_valid(sum):
		return
	if sum.is_update_staged:
		sum.apply_and_restart()
	elif sum.is_update_available:
		sum.start_self_update()
		_refresh_self_update_ui()
	else:
		_update_status_label.text = "Checking for updates..."
		_update_action_button.disabled = true
		sum.check_for_self_update()

func _on_self_update_check_completed(is_available: bool, latest_ver: String):
	if not is_instance_valid(_update_status_label):
		return
	_refresh_self_update_ui()
	if not is_available and is_instance_valid(_update_status_label):
		_update_status_label.text = "Up to date (%s)" % latest_ver

func _on_self_update_progress(_percent: int, status_text: String):
	if is_instance_valid(_update_status_label):
		_update_status_label.text = status_text
	if is_instance_valid(_update_action_button):
		_update_action_button.disabled = true
		_update_action_button.text = "Updating..."

func _on_self_update_ready(_version: String):
	_refresh_self_update_ui()

func _on_self_update_failed(error_message: String):
	if is_instance_valid(_update_status_label):
		_update_status_label.text = "Error: " + error_message
	if is_instance_valid(_update_action_button):
		_update_action_button.disabled = false
		_update_action_button.text = "Retry Update"

func _create_check_setting(label_text: String, setting_key: String):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	
	var check = CheckButton.new()
	check.button_pressed = SettingsManager.get_setting(setting_key, true)
	check.toggled.connect(func(toggled_on): SettingsManager.set_setting(setting_key, toggled_on))
	
	check.focus_entered.connect(func(): if SettingsManager.get_setting("play_ui_sounds", true): get_node("/root/App/FocusSoundPlayer").play())
	check.pressed.connect(func(): if SettingsManager.get_setting("play_ui_sounds", true): get_node("/root/App/ButtonSoundPlayer").play())
	
	hbox.add_child(check)
	settings_container.add_child(hbox)

func _create_option_setting(label_text: String, setting_key: String, options: Array, display_names: Array = []):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	
	var option_btn = OptionButton.new()
	for i in range(options.size()):
		if i < display_names.size():
			option_btn.add_item(display_names[i])
		else:
			option_btn.add_item(options[i].capitalize())
	
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
