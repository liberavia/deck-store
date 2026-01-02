extends PanelContainer

@onready var name_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionName
@onready var description_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionDescription
@onready var status_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionStatus
@onready var icon_texture: TextureRect = $MarginContainer/ExtensionContainer/Control/ExtensionIcon
@onready var status_indicator: TextureRect = $MarginContainer/ExtensionContainer/Control/StatusIndicator

@onready var action_button: Button = $MarginContainer/ExtensionContainer/ActionContainer/ActionButton
@onready var progress_info: VBoxContainer = $MarginContainer/ExtensionContainer/ActionContainer/ProgressInfo
@onready var progress_label: Label = $MarginContainer/ExtensionContainer/ActionContainer/ProgressInfo/ProgressLabel
@onready var progress_bar: ProgressBar = $MarginContainer/ExtensionContainer/ActionContainer/ProgressInfo/ProgressBar

# --- Constants ---
const EXTENSION_ICON_DIR = "res://extensions/icons/"

# Colors matching ActionButton.gd
const COLOR_INSTALL = Color("#245322") # Greenish
const COLOR_REMOVE = Color("#5c0001")  # Reddish
const COLOR_BUSY = Color("#4a4a4a")    # Dark Gray
const COLOR_NORMAL = Color("#626262")  # Gray
const COLOR_PURPLE_BORDER = Color(0.627451, 0.12549, 0.941176, 1)

# --- Internal State ---
var _extension_id: String
var _operation_in_progress: bool = false
var _update_available: bool = false
var _latest_version: String = ""
var _pending_focus_grab: bool = false

# Styleboxes for the button
var stylebox_install: StyleBoxFlat
var stylebox_remove: StyleBoxFlat
var stylebox_busy: StyleBoxFlat
var stylebox_normal: StyleBoxFlat
var stylebox_focus: StyleBoxFlat

func get_extension_id() -> String:
	return _extension_id

func _ready():
	_setup_styles()
	action_button.pressed.connect(_on_action_button_pressed)
	
	ExtensionsManager.extension_operation_started.connect(_on_operation_started)
	ExtensionsManager.extension_operation_finished.connect(_on_operation_finished)
	ExtensionsManager.extension_update_available.connect(_on_extension_update_available)
	ExtensionsManager.extension_progress_updated.connect(_on_extension_progress_updated)

func _setup_styles():
	var base_stylebox = action_button.get_theme_stylebox("normal")
	if base_stylebox is StyleBoxFlat:
		stylebox_normal = base_stylebox.duplicate()
	else:
		stylebox_normal = StyleBoxFlat.new()
		stylebox_normal.set_corner_radius_all(4)
		stylebox_normal.content_margin_left = 10
		stylebox_normal.content_margin_right = 10
		stylebox_normal.content_margin_top = 5
		stylebox_normal.content_margin_bottom = 5
	
	stylebox_install = stylebox_normal.duplicate()
	stylebox_install.bg_color = COLOR_INSTALL
	
	stylebox_remove = stylebox_normal.duplicate()
	stylebox_remove.bg_color = COLOR_REMOVE
	
	stylebox_busy = stylebox_normal.duplicate()
	stylebox_busy.bg_color = COLOR_BUSY
	
	stylebox_normal.bg_color = COLOR_NORMAL
	
	# Setup focus style
	stylebox_focus = stylebox_normal.duplicate()
	stylebox_focus.draw_center = false
	stylebox_focus.border_width_left = 3
	stylebox_focus.border_width_top = 3
	stylebox_focus.border_width_right = 3
	stylebox_focus.border_width_bottom = 3
	stylebox_focus.border_color = COLOR_PURPLE_BORDER
	action_button.add_theme_stylebox_override("focus", stylebox_focus)

func _on_action_button_pressed():
	if _operation_in_progress: return
	
	var current_text = action_button.text
	if current_text == "Install" or current_text == "Update":
		# Check dependencies for Install
		var missing_deps = ExtensionsManager.get_missing_dependencies(_extension_id)
		if not missing_deps.is_empty():
			_show_dependency_popup("install", missing_deps)
			return

		print("INFO: Requesting install/update for ", _extension_id)
		_start_progress_display("Initializing..." if current_text == "Install" else "Updating...")
		if current_text == "Update":
			ExtensionsManager.update_extension(_extension_id)
		else:
			ExtensionsManager.install_extension(_extension_id)
			
	elif current_text == "Uninstall":
		# Check dependents for Uninstall
		var dependents = ExtensionsManager.get_installed_dependents(_extension_id)
		if not dependents.is_empty():
			_show_dependency_popup("uninstall", dependents)
			return

		print("INFO: Requesting uninstall for ", _extension_id)
		_start_progress_display("Uninstalling...")
		ExtensionsManager.uninstall_extension(_extension_id)

func _show_dependency_popup(mode: String, dependency_ids: Array):
	var popup_scene = load("res://sections/dependency_popup.tscn")
	var popup = popup_scene.instantiate()
	
	# Add directly to root to ensure it exists and is independent of UI structure
	get_tree().root.add_child(popup)
	
	popup.setup(mode, name_label.text, dependency_ids)
	
	popup.confirmed.connect(func():
		if mode == "install":
			# Order: Dependencies first, then target
			var install_list = dependency_ids.duplicate()
			install_list.append(_extension_id)
			print("INFO: Batch install confirmed: ", install_list)
			
			# We need to trigger progress display on OUR item, but the manager handles the sequence.
			# The manager will emit operation_started for each item.
			ExtensionsManager.execute_transaction(install_list, "install")
			
		elif mode == "uninstall":
			# Order: Dependents first, then target
			var remove_list = dependency_ids.duplicate()
			remove_list.append(_extension_id)
			print("INFO: Batch remove confirmed: ", remove_list)
			ExtensionsManager.execute_transaction(remove_list, "remove")
	)

func _start_progress_display(label_text: String):
	progress_info.visible = true
	progress_label.text = label_text
	progress_bar.value = 0
	
func _on_extension_progress_updated(extension_id: String, percent: int, message: String):
	if extension_id == _extension_id:
		progress_info.visible = true
		progress_bar.value = percent
		progress_label.text = message

func _on_operation_started(extension_id: String, operation: String):
	if extension_id == _extension_id:
		_operation_in_progress = true
		update_status(ExtensionsManager.get_extension_status(_extension_id))

func _on_operation_finished(extension_id: String, operation: String):
	if extension_id == _extension_id:
		_operation_in_progress = false
		_pending_focus_grab = true
		progress_bar.value = 100
		
		get_tree().create_timer(0.5).timeout.connect(func():
			progress_info.visible = false
		)

func _grab_appropriate_focus():
	if action_button.visible and not action_button.disabled:
		action_button.grab_focus()

func _on_extension_update_available(extension_id: String, latest_version: String):
	if extension_id == _extension_id:
		_update_available = true
		_latest_version = latest_version
		update_status(ExtensionsManager.get_extension_status(_extension_id))

func set_data(extension_data: Dictionary):
	_extension_id = extension_data.get("id", "unknown_id")
	name_label.text = extension_data.get("name", "Unknown Extension")
	description_label.text = extension_data.get("description", "No description available.")
	
	var icon_filename = extension_data.get("icon", "")
	if not icon_filename.is_empty():
		var icon_path = EXTENSION_ICON_DIR.path_join(icon_filename)
		if FileAccess.file_exists(icon_path):
			var texture = load(icon_path) as Texture2D
			if texture:
				icon_texture.texture = texture
				icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE 
				icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			else:
				icon_texture.texture = null
		else:
			icon_texture.texture = null

func update_status(is_installed: bool):
	status_indicator.visible = is_installed
	
	if is_installed:
		if _update_available:
			status_label.text = "Update Available (v" + _latest_version + ")"
			action_button.text = "Update"
			action_button.add_theme_stylebox_override("normal", stylebox_install) # Update is like install
		else:
			status_label.text = "Installed"
			action_button.text = "Uninstall"
			action_button.add_theme_stylebox_override("normal", stylebox_remove)
	else:
		status_label.text = "Not Installed"
		action_button.text = "Install"
		action_button.add_theme_stylebox_override("normal", stylebox_install)
	
	if _operation_in_progress:
		action_button.disabled = true
		action_button.text = "Please Wait..."
		action_button.add_theme_stylebox_override("normal", stylebox_busy)
		# Progress bar handles the detailed text
	else:
		action_button.disabled = false
		progress_info.visible = false # Ensure hidden if not busy

	if _pending_focus_grab:
		_grab_appropriate_focus.call_deferred()
		_pending_focus_grab = false