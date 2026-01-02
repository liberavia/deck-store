extends CanvasLayer

signal confirmed
signal cancelled

# Pfade angepasst auf neue Struktur
@onready var title_label: Label = $DependencyPopup/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $DependencyPopup/MarginContainer/VBoxContainer/MessageLabel
@onready var extensions_list: VBoxContainer = $DependencyPopup/MarginContainer/VBoxContainer/ScrollContainer/ExtensionsList
@onready var confirm_button: Button = $DependencyPopup/MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_button: Button = $DependencyPopup/MarginContainer/VBoxContainer/HBoxContainer/CancelButton

var _previous_focus_owner: Control = null

func _ready():
	# Store previous focus
	_previous_focus_owner = get_viewport().gui_get_focus_owner()
	
	confirm_button.pressed.connect(func():
		_restore_focus()
		emit_signal("confirmed")
		queue_free()
	)
	cancel_button.pressed.connect(func():
		_restore_focus()
		emit_signal("cancelled")
		queue_free()
	)
	
	# Grab focus deferred to ensure everything is ready
	call_deferred("_grab_initial_focus")

func _grab_initial_focus():
	if cancel_button and cancel_button.is_inside_tree():
		cancel_button.grab_focus()

func _restore_focus():
	if _previous_focus_owner and is_instance_valid(_previous_focus_owner):
		_previous_focus_owner.grab_focus()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		_restore_focus()
		emit_signal("cancelled")
		queue_free()
		get_viewport().set_input_as_handled()

# Mode: "install" or "uninstall"
func setup(mode: String, target_extension_name: String, dependency_ids: Array):
	_clear_list()
	
	if mode == "install":
		title_label.text = "Additional Components Required"
		message_label.text = "Installing '%s' requires the following additional components:" % target_extension_name
		confirm_button.text = "Install All"
		confirm_button.modulate = Color(0.5, 1.0, 0.5)
	
	elif mode == "uninstall":
		title_label.text = "⚠️ Warning: Dependency Conflict"
		message_label.text = "Uninstalling '%s' will break the following extensions. They will also be removed:" % target_extension_name
		confirm_button.text = "Yes, Remove All"
		confirm_button.modulate = Color(1.0, 0.5, 0.5)
	
	for dep_id in dependency_ids:
		_add_extension_item(dep_id)

func _clear_list():
	for child in extensions_list.get_children():
		child.queue_free()

func _add_extension_item(extension_id: String):
	var data = ExtensionsManager.get_extension_data(extension_id)
	if data.is_empty():
		return
		
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	
	# Icon
	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(32, 32)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	var icon_filename = data.get("icon", "")
	var internal_path = data.get("internal_path", "")
	
	if not icon_filename.is_empty() and not internal_path.is_empty():
		var icon_path = internal_path.path_join(icon_filename)
		if FileAccess.file_exists(icon_path):
			icon_rect.texture = load(icon_path)
	
	hbox.add_child(icon_rect)
	
	# Name
	var name_lbl = Label.new()
	name_lbl.text = data.get("name", extension_id)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)
	
	extensions_list.add_child(hbox)