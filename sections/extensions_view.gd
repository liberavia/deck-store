# extensions_view.gd
extends Control

@export var extension_list_item_scene: PackedScene

@onready var list_container: VBoxContainer = $MarginContainer/ScrollContainer/VBoxContainer

func _ready():
	# Check if the scene was assigned in the editor.
	if not extension_list_item_scene:
		printerr("ExtensionsView ERROR: 'Extension List Item Scene' has not been assigned in the Inspector!")
		return

	# Use the corrected Autoload name 'ExtensionsManager'
	if not ProjectSettings.has_setting("autoload/ExtensionsManager"):
		printerr("ExtensionsView ERROR: ExtensionsManager autoload not found! Check the name in Project Settings.")
		return

	# Connect to the signal from ExtensionsManager
	if ExtensionsManager.has_signal("extension_status_updated"):
		ExtensionsManager.extension_status_updated.connect(_on_extension_status_updated)
	
	# Populate the list initially
	_populate_list()

# Fills the list with items based on data from ExtensionsManager
func _populate_list():
	# Clear existing items
	for child in list_container.get_children():
		child.queue_free()
		
	var all_extensions = ExtensionsManager.get_all_extensions()
	print("INFO ExtensionsView: Populating list with %d extensions." % all_extensions.size())
	
	for ext_data in all_extensions:
		if not extension_list_item_scene:
			printerr("ExtensionsView CRITICAL: Cannot instantiate item, extension_list_item_scene is null.")
			continue # Skip this item
			
		var item_instance = extension_list_item_scene.instantiate()
		list_container.add_child(item_instance)
		
		if item_instance.has_method("set_data"):
			item_instance.set_data(ext_data)
			
		# Set the initial status from the manager's cache
		if item_instance.has_method("update_status"):
			var extension_id = ext_data.get("id", "")
			var is_installed = ExtensionsManager.get_extension_status(extension_id)
			item_instance.update_status(is_installed)

# Called when an extension's status has been updated by the manager
func _on_extension_status_updated(extension_id: String, is_installed: bool):
	print("INFO ExtensionsView: Received status update for ", extension_id, ", Installed: ", is_installed)
	
	var children = list_container.get_children()
	print("DEBUG ExtensionsView: Checking ", children.size(), " items in list.")
	
	# Find the list item corresponding to the extension_id and update its UI
	for item in children:
		if not is_instance_valid(item):
			continue
			
		var item_id = ""
		if item.has_method("get_extension_id"):
			item_id = item.get_extension_id()
		
		print("DEBUG ExtensionsView: Item ", item.name, " (Instance: ", item.get_instance_id(), ") has ID: '", item_id, "'")
		
		if item_id == extension_id:
			if item.has_method("update_status"):
				print("DEBUG ExtensionsView: Calling update_status on item.")
				item.update_status(is_installed)
				break # Found and updated, no need to continue loop
