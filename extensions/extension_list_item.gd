# extension_list_item.gd
extends PanelContainer

@onready var name_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionName
@onready var description_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionDescription
@onready var status_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionStatus
@onready var icon_texture: TextureRect = $MarginContainer/ExtensionContainer/Control/ExtensionIcon

# --- Constants ---
const EXTENSION_ICON_DIR = "res://extensions/icons/"

# --- Internal State ---
var _extension_id: String = ""

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
	if is_installed:
		status_label.text = "Installed"
	else:
		status_label.text = "Not Installed"

# Getter to allow the parent node (ExtensionsView) to identify this item
func get_extension_id() -> String:
	return _extension_id
