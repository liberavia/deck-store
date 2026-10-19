extends CanvasLayer

signal confirmed(password: String)
signal cancelled

@onready var title_label: Label = $SudoPopup/MarginContainer/VBoxContainer/Title
@onready var message_label: Label = $SudoPopup/MarginContainer/VBoxContainer/Message
@onready var password_input: LineEdit = $SudoPopup/MarginContainer/VBoxContainer/PasswordInput
@onready var error_label: Label = $SudoPopup/MarginContainer/VBoxContainer/ErrorLabel
@onready var cancel_button: Button = $SudoPopup/MarginContainer/VBoxContainer/HBoxContainer/CancelButton
@onready var confirm_button: Button = $SudoPopup/MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton

var _previous_focus_owner: Control = null
var _typing_active: bool = false

func _ready():
	_previous_focus_owner = get_viewport().gui_get_focus_owner()
	error_label.visible = false
	password_input.virtual_keyboard_enabled = false

	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	password_input.text_submitted.connect(func(_t): _on_confirm_pressed())

	var focus_style = StyleBoxFlat.new()
	focus_style.draw_center = false
	focus_style.set_border_width_all(3)
	focus_style.border_color = Color(0.627, 0.125, 0.941, 1.0)
	focus_style.set_corner_radius_all(4)
	cancel_button.add_theme_stylebox_override("focus", focus_style)
	confirm_button.add_theme_stylebox_override("focus", focus_style)
	password_input.add_theme_stylebox_override("focus", focus_style)

	call_deferred("_grab_initial_focus")

func _grab_initial_focus():
	if is_instance_valid(password_input) and password_input.is_inside_tree():
		password_input.grab_focus()

func _restore_focus():
	if is_instance_valid(_previous_focus_owner):
		_previous_focus_owner.grab_focus()

func setup(extension_name: String):
	if is_instance_valid(title_label):
		title_label.text = "Administrator Access Required"
	if is_instance_valid(message_label):
		message_label.text = "'%s' requires system privileges (sudo/root).\nPlease enter your SteamOS / Linux sudo password:" % extension_name

func _set_typing_active(active: bool):
	if _typing_active == active:
		return
	_typing_active = active
	if _typing_active:
		var steam_int = get_node_or_null("/root/SteamIntegration")
		if is_instance_valid(steam_int) and steam_int.has_method("open_virtual_keyboard"):
			steam_int.open_virtual_keyboard(password_input.get_global_rect(), password_input.text)
		else:
			DisplayServer.virtual_keyboard_show(password_input.text)
	else:
		if Engine.has_singleton("Steam") and Steam.has_method("dismissFloatingGamepadTextInput"):
			Steam.dismissFloatingGamepadTextInput()
		DisplayServer.virtual_keyboard_hide()

func _input(event: InputEvent):
	if ControllerManager.is_input_blocked():
		return

	if _typing_active:
		if event.is_action_pressed("ui_cancel"):
			_set_typing_active(false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_set_typing_active(false)
				_on_confirm_pressed()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_BACKSPACE:
				if password_input.text.length() > 0:
					password_input.text = password_input.text.substr(0, password_input.text.length() - 1)
				get_viewport().set_input_as_handled()
				return
			elif event.unicode != 0:
				password_input.text += char(event.unicode)
				get_viewport().set_input_as_handled()
				return
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			return
		return

	if password_input.has_focus() and event.is_action_pressed("ui_accept"):
		_set_typing_active(true)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()

func _on_cancel_pressed():
	_set_typing_active(false)
	_restore_focus()
	emit_signal("cancelled")
	queue_free()

func _on_confirm_pressed():
	_set_typing_active(false)
	var pwd = password_input.text
	if pwd.is_empty():
		error_label.text = "Password cannot be empty."
		error_label.visible = true
		return

	confirm_button.disabled = true
	error_label.visible = false

	if ExtensionsManager.verify_sudo_password(pwd):
		_restore_focus()
		emit_signal("confirmed", pwd)
		queue_free()
	else:
		confirm_button.disabled = false
		error_label.text = "Invalid sudo password. Please try again."
		error_label.visible = true
		password_input.grab_focus()
