# extension_list_item.gd
extends PanelContainer

@onready var name_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionName
@onready var description_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionDescription
@onready var status_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionStatus
@onready var icon_texture: TextureRect = $MarginContainer/ExtensionContainer/Control/ExtensionIcon

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

# --- Internal State ---
var _extension_id: String
var _operation_in_progress: bool = false
var _update_available: bool = false
var _latest_version: String = ""
var _pending_focus_grab: bool = false
var _last_known_id: String = "INITIAL_UNSET"

# Styleboxes for the button
var stylebox_install: StyleBoxFlat
var stylebox_remove: StyleBoxFlat
var stylebox_busy: StyleBoxFlat
var stylebox_normal: StyleBoxFlat

func _process(delta):
	if _extension_id != _last_known_id:
		print("DEBUG WATCHDOG: _extension_id changed from '", _last_known_id, "' to '", _extension_id, "' on instance ", get_instance_id())
		_last_known_id = _extension_id

func get_extension_id() -> String:
	print("DEBUG ExtensionListItem: get_extension_id called on instance ", get_instance_id(), ". Returning: '", _extension_id, "'")
	return _extension_id

func _ready():
	_setup_styles()
	action_button.pressed.connect(_on_action_button_pressed)
	
	ExtensionsManager.extension_operation_started.connect(_on_operation_started)
	ExtensionsManager.extension_operation_finished.connect(_on_operation_finished)
	ExtensionsManager.extension_update_available.connect(_on_extension_update_available)

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

func _on_action_button_pressed():
	if _operation_in_progress: return
	
	var current_text = action_button.text
	if current_text == "Install" or current_text == "Update":
		print("INFO: Requesting install/update for ", _extension_id)
		# Trigger fake progress
		_start_fake_progress("Installing..." if current_text == "Install" else "Updating...")
		if current_text == "Update":
			ExtensionsManager.update_extension(_extension_id)
		else:
			ExtensionsManager.install_extension(_extension_id)
	elif current_text == "Uninstall":
		print("INFO: Requesting uninstall for ", _extension_id)
		_start_fake_progress("Uninstalling...")
		ExtensionsManager.uninstall_extension(_extension_id)

func _start_fake_progress(label_text: String):
	progress_info.visible = true
	progress_label.text = label_text
	progress_bar.value = 0
	
	# Simple tween to simulate progress since we don't have real feedback
	var tween = create_tween()
	tween.tween_property(progress_bar, "value", 90.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_operation_started(extension_id: String, operation: String):
	if extension_id == _extension_id:
		print("DEBUG ExtensionListItem: Operation started for ", extension_id)
		_operation_in_progress = true
		update_status(ExtensionsManager.get_extension_status(_extension_id))

func _on_operation_finished(extension_id: String, operation: String):
	if extension_id == _extension_id:
		print("DEBUG ExtensionListItem: Operation finished for ", extension_id)
		_operation_in_progress = false
		_pending_focus_grab = true
		progress_bar.value = 100
		
		# Force a status update here if needed, but usually we wait for the signal.
		# However, if the operation failed (exit code != 0), the status might NOT change,
		# and thus 'extension_status_updated' might NOT be emitted if the value is same?
		# ExtensionsManager emits 'extension_status_updated' inside '_process_check_result'.
		# It does: `_extensions_status[extension_id] = is_installed`.
		# And `emit_signal("extension_status_updated", extension_id, is_installed)`.
		# It emits it UNCONDITIONALLY. So we should be good.
		
		# Give a moment to see 100%
		get_tree().create_timer(0.5).timeout.connect(func():
			progress_info.visible = false
			# If for some reason update_status wasn't called (e.g. signal missed),
			# we might want to ensure consistent state. 
			# But calling update_status here might use stale data if check isn't done.
			# Let's rely on the flow for now, the debug prints will tell us more.
		)

func _grab_appropriate_focus():
	if action_button.visible and not action_button.disabled:
		action_button.grab_focus()

func _on_extension_update_available(extension_id: String, latest_version: String):
	if extension_id == _extension_id:
		_update_available = true
		_latest_version = latest_version
		update_status(ExtensionsManager.get_extension_status(_extension_id))

func _init():
	print("DEBUG ExtensionListItem: _init ", get_instance_id())

func _exit_tree():
	print("DEBUG ExtensionListItem: _exit_tree ", get_instance_id())

func set_data(extension_data: Dictionary):
	print("DEBUG ExtensionListItem: set_data called on ", get_instance_id(), " with data: ", extension_data)
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
	print("DEBUG ExtensionListItem: update_status called for ", _extension_id, ". Installed: ", is_installed, ", OpInProgress: ", _operation_in_progress)
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
