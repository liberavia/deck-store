extends CanvasLayer

signal confirmed(password: String)
signal cancelled

@onready var title_label: Label = $SudoPopup/MarginContainer/VBoxContainer/Title
@onready var message_label: Label = $SudoPopup/MarginContainer/VBoxContainer/Message
@onready var password_input: LineEdit = $SudoPopup/MarginContainer/VBoxContainer/PasswordInput
@onready var confirm_password_input: LineEdit = $SudoPopup/MarginContainer/VBoxContainer/ConfirmPasswordInput
@onready var error_label: Label = $SudoPopup/MarginContainer/VBoxContainer/ErrorLabel
@onready var cancel_button: Button = $SudoPopup/MarginContainer/VBoxContainer/HBoxContainer/CancelButton
@onready var confirm_button: Button = $SudoPopup/MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton

var _previous_focus_owner: Control = null
var _typing_active: bool = false
var _active_input: LineEdit = null
var _create_password_mode: bool = false

func _ready():
	_previous_focus_owner = get_viewport().gui_get_focus_owner()
	error_label.visible = false
	password_input.virtual_keyboard_enabled = false
	confirm_password_input.virtual_keyboard_enabled = false

	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	password_input.text_submitted.connect(func(_t): _on_confirm_pressed())
	confirm_password_input.text_submitted.connect(func(_t): _on_confirm_pressed())

	var focus_style = StyleBoxFlat.new()
	focus_style.draw_center = false
	focus_style.set_border_width_all(3)
	focus_style.border_color = Color(0.627, 0.125, 0.941, 1.0)
	focus_style.set_corner_radius_all(4)
	cancel_button.add_theme_stylebox_override("focus", focus_style)
	confirm_button.add_theme_stylebox_override("focus", focus_style)
	password_input.add_theme_stylebox_override("focus", focus_style)
	confirm_password_input.add_theme_stylebox_override("focus", focus_style)

	call_deferred("_grab_initial_focus")

func _grab_initial_focus():
	if is_instance_valid(password_input) and password_input.is_inside_tree():
		password_input.grab_focus()

func _restore_focus():
	if is_instance_valid(_previous_focus_owner):
		_previous_focus_owner.grab_focus()

func setup(extension_name: String, create_new_password: bool = false):
	_create_password_mode = create_new_password
	if _create_password_mode:
		title_label.text = "Set SteamOS Sudo Password"
		message_label.text = "No sudo password is set on this device yet.\nPlease create a password to install '%s':" % extension_name
		password_input.placeholder_text = "Press A to enter new password..."
		confirm_password_input.visible = true
		confirm_button.text = "Set & Continue"
	else:
		title_label.text = "Administrator Access Required"
		message_label.text = "'%s' requires system privileges (sudo/root).\nPlease enter your SteamOS / Linux sudo password:" % extension_name
		password_input.placeholder_text = "Press A to enter sudo password..."
		confirm_password_input.visible = false

func _set_typing_active(active: bool, target_input: LineEdit = null):
	if _typing_active == active:
		return
	_typing_active = active
	if _typing_active:
		_active_input = target_input if is_instance_valid(target_input) else password_input
		var steam_int = get_node_or_null("/root/SteamIntegration")
		if is_instance_valid(steam_int) and steam_int.has_method("open_virtual_keyboard"):
			steam_int.open_virtual_keyboard(_active_input.get_global_rect(), _active_input.text)
		else:
			DisplayServer.virtual_keyboard_show(_active_input.text)
	else:
		_active_input = null
		if Engine.has_singleton("Steam") and Steam.has_method("dismissFloatingGamepadTextInput"):
			Steam.dismissFloatingGamepadTextInput()
		DisplayServer.virtual_keyboard_hide()

func _input(event: InputEvent):
	if ControllerManager.is_input_blocked():
		return

	if _typing_active:
		var field = _active_input if is_instance_valid(_active_input) else password_input
		if event.is_action_pressed("ui_cancel"):
			_set_typing_active(false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_set_typing_active(false)
				if _create_password_mode and field == password_input and confirm_password_input.text.is_empty():
					confirm_password_input.grab_focus()
				else:
					_on_confirm_pressed()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_BACKSPACE:
				if field.text.length() > 0:
					field.text = field.text.substr(0, field.text.length() - 1)
				get_viewport().set_input_as_handled()
				return
			elif event.unicode != 0:
				field.text += char(event.unicode)
				get_viewport().set_input_as_handled()
				return
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			return
		return

	if password_input.has_focus() and event.is_action_pressed("ui_accept"):
		_set_typing_active(true, password_input)
		get_viewport().set_input_as_handled()
		return

	if confirm_password_input.visible and confirm_password_input.has_focus() and event.is_action_pressed("ui_accept"):
		_set_typing_active(true, confirm_password_input)
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

	if _create_password_mode:
		if pwd != confirm_password_input.text:
			error_label.text = "Passwords do not match."
			error_label.visible = true
			confirm_password_input.grab_focus()
			return

	confirm_button.disabled = true
	error_label.visible = false

	if _create_password_mode:
		if not ExtensionsManager.set_initial_user_password(pwd):
			confirm_button.disabled = false
			error_label.text = "Failed to set system password."
			error_label.visible = true
			return

	if ExtensionsManager.verify_sudo_password(pwd):
		_restore_focus()
		emit_signal("confirmed", pwd)
		queue_free()
	else:
		confirm_button.disabled = false
		error_label.text = "Invalid sudo password. Please try again."
		error_label.visible = true
		password_input.grab_focus()
