# extension_list_item.gd
extends PanelContainer

@onready var name_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionName
@onready var description_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionDescription
@onready var status_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionStatus
@onready var icon_texture: TextureRect = $MarginContainer/ExtensionContainer/Control/ExtensionIcon
@onready var install_button: Button = $MarginContainer/ExtensionContainer/ActionButtonsContainer/InstallButton
@onready var uninstall_button: Button = $MarginContainer/ExtensionContainer/ActionButtonsContainer/UninstallButton
@onready var update_button: Button = $MarginContainer/ExtensionContainer/ActionButtonsContainer/UpdateButton

# --- Constants ---
const EXTENSION_ICON_DIR = "res://extensions/icons/"

# --- Internal State ---
var _extension_id: String = ""
var _operation_in_progress: bool = false
var _update_available: bool = false
var _latest_version: String = ""


func _ready():
	install_button.pressed.connect(_on_install_button_pressed)
	uninstall_button.pressed.connect(_on_uninstall_button_pressed)
	update_button.pressed.connect(_on_update_button_pressed)
	
	# Connect to manager signals to know when to disable buttons and update status
	ExtensionsManager.extension_operation_started.connect(_on_operation_started)
	ExtensionsManager.extension_operation_finished.connect(_on_operation_finished)
	ExtensionsManager.extension_update_available.connect(_on_extension_update_available)


func _on_install_button_pressed():
	if _operation_in_progress: return
	print("INFO: Requesting install for ", _extension_id)
	ExtensionsManager.install_extension(_extension_id)

func _on_uninstall_button_pressed():
	if _operation_in_progress: return
	print("INFO: Requesting uninstall for ", _extension_id)
	ExtensionsManager.uninstall_extension(_extension_id)

func _on_update_button_pressed():
	if _operation_in_progress: return
	print("INFO: Requesting update for ", _extension_id)
	ExtensionsManager.update_extension(_extension_id)

func _on_operation_started(extension_id: String, operation: String):
	if extension_id == _extension_id:
		_operation_in_progress = true
		update_status(ExtensionsManager.get_extension_status(_extension_id)) # Re-render buttons

func _on_operation_finished(extension_id: String, operation: String):
	if extension_id == _extension_id:
		_operation_in_progress = false
		# The manager will emit 'extension_status_updated' which will trigger the final UI update
		# so we don't strictly need to call update_status here, but it can make the UI feel more responsive.
		update_status(ExtensionsManager.get_extension_status(_extension_id))

func _on_extension_update_available(extension_id: String, latest_version: String):
	if extension_id == _extension_id:
		_update_available = true
		_latest_version = latest_version
		update_status(ExtensionsManager.get_extension_status(_extension_id)) # Re-render buttons


# This function is called from extensions_view.gd to populate the data
func set_data(extension_data: Dictionary):
	_extension_id = extension_data.get("id", "unknown_id")
	name_label.text = extension_data.get("name", "Unknown Extension")
	description_label.text = extension_data.get("description", "No description available.")
	
	# Load icon from the predefined directory using just the filename from JSON
	var icon_filename = extension_data.get("icon", "")
	if not icon_filename.is_empty():
		var icon_path = EXTENSION_ICON_DIR.path_join(icon_filename)
		
		if FileAccess.file_exists(icon_path):
			var texture = load(icon_path) as Texture2D
			if texture:
				# Set the texture and configure scaling correctly.
				icon_texture.texture = texture
				# 1. Tell the TextureRect to fill its parent container's bounds
				icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE 
				# 2. Tell it HOW to fill those bounds (keep aspect ratio and center)
				icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			else:
				printerr("ExtensionListItem ERROR: Failed to load texture at: ", icon_path)
		else:
			printerr("ExtensionListItem ERROR: Icon file not found at constructed path: ", icon_path)
			icon_texture.texture = null # Clear any old texture

# This function is called via a signal from ExtensionsManager
func update_status(is_installed: bool):
	# Update status label
	if is_installed:
		if _update_available:
			status_label.text = "Update Available (v" + _latest_version + ")"
		else:
			status_label.text = "Installed"
	else:
		status_label.text = "Not Installed"
		
	# Update button visibility and state
	install_button.visible = not is_installed
	uninstall_button.visible = is_installed and not _update_available
	update_button.visible = is_installed and _update_available
	
	# Disable all buttons if an operation is running for this item
	install_button.disabled = _operation_in_progress
	uninstall_button.disabled = _operation_in_progress
	update_button.disabled = _operation_in_progress
	
	# Update button text to show activity
	if _operation_in_progress:
		if install_button.visible:
			install_button.text = "Installing..."
		elif uninstall_button.visible:
			uninstall_button.text = "Uninstalling..."
		elif update_button.visible:
			update_button.text = "Updating..."
	else:
		install_button.text = "Install"
		uninstall_button.text = "Uninstall"
		update_button.text = "Update"


# Getter to allow the parent node (ExtensionsView) to identify this item
func get_extension_id() -> String:
	return _extension_id
