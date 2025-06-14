# ExtensionsManager.gd
extends Node

signal extension_status_updated(extension_id, is_installed)

const EXTENSIONS_JSON_PATH = "res://extensions/extensions.json"
const EXTENSION_SCRIPTS_DIR = "res://extensions/scripts/"

var _extensions_data: Array[Dictionary] = []
var _extensions_status: Dictionary = {} # Stores the current installation status, e.g., {"steam_shortcut_manager_installer": true}

var _check_thread: Thread = null
var _check_queue: Array[Dictionary] = []
var _is_checking: bool = false

func _ready():
	_load_extensions_from_json()
	check_all_extensions_status()

# --- Public API ---

func get_all_extensions() -> Array[Dictionary]:
	return _extensions_data

func get_extension_status(extension_id: String) -> bool:
	return _extensions_status.get(extension_id, false)

# --- Internal Logic ---

# Loads the list of available extensions from the JSON file.
func _load_extensions_from_json():
	if not FileAccess.file_exists(EXTENSIONS_JSON_PATH):
		printerr("ExtensionManager ERROR: extensions.json not found at ", EXTENSIONS_JSON_PATH)
		return

	var file = FileAccess.open(EXTENSIONS_JSON_PATH, FileAccess.READ)
	if not file:
		printerr("ExtensionManager ERROR: Could not open extensions.json for reading.")
		return
	var json_string = file.get_as_text()
	file.close() # Close the file immediately after reading
	
	var parse_result = JSON.parse_string(json_string)

	# CORRECTED: Instead of casting, manually build the typed array.
	if parse_result is Array:
		var parsed_array = parse_result as Array
		var temp_extensions_data: Array[Dictionary] = [] # Create a new, correctly typed array
		
		for item in parsed_array:
			if item is Dictionary:
				temp_extensions_data.append(item)
			else:
				printerr("ExtensionManager WARNING: Found a non-Dictionary item in extensions.json, skipping it. Item: ", item)
		
		_extensions_data = temp_extensions_data # Assign the newly built, type-safe array
		print("INFO ExtensionManager: Successfully loaded %d extensions." % _extensions_data.size())
	else:
		printerr("ExtensionManager ERROR: Failed to parse extensions.json. Content is not a valid JSON array.")

# Queues up all extensions to have their installation status checked.
func check_all_extensions_status():
	if _is_checking:
		print("INFO ExtensionManager: A check is already in progress.")
		return
	
	print("INFO ExtensionManager: Queuing all extensions for status check.")
	for ext_data in _extensions_data:
		_check_queue.append(ext_data)
	
	_start_next_check()

func _start_next_check():
	if _is_checking or _check_queue.is_empty():
		return
		
	_is_checking = true
	var extension_to_check = _check_queue.pop_front()
	
	if _check_thread != null and _check_thread.is_alive():
		_check_thread.wait_to_finish()
	
	_check_thread = Thread.new()
	var callable_func = func(): _execute_check_script_in_thread(extension_to_check)
	_check_thread.start(callable_func)

func _execute_check_script_in_thread(extension_data: Dictionary):
	var script_name = extension_data.get("script_name", "")
	if script_name.is_empty():
		call_deferred("_process_check_result", extension_data, -1)
		return
		
	var script_path = ProjectSettings.globalize_path(EXTENSION_SCRIPTS_DIR.path_join(script_name))
	
	var output_array: PackedStringArray = []
	# The script needs to be executed via 'sh' as it's a bash script
	var exit_code = OS.execute("sh", [script_path, "check"], output_array, true, true)
	
	call_deferred("_process_check_result", extension_data, exit_code)

func _process_check_result(extension_data: Dictionary, exit_code: int):
	var extension_id = extension_data.get("id", "")
	if extension_id.is_empty():
		printerr("ExtensionManager ERROR: Processed a check for an extension without an ID.")
	else:
		var is_installed = (exit_code == 0) # Bash script exits 0 if installed, 1 if not
		_extensions_status[extension_id] = is_installed
		print("INFO ExtensionManager: Status for '", extension_id, "' is Installed=", is_installed)
		emit_signal("extension_status_updated", extension_id, is_installed)
	
	_is_checking = false
	_start_next_check() # Check if there are more extensions in the queue
