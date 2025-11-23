# ExtensionsManager.gd
extends Node

signal extension_status_updated(extension_id, is_installed)
signal extension_operation_started(extension_id, operation)
signal extension_operation_finished(extension_id, operation)
signal extension_update_available(extension_id, latest_version)

const EXTENSIONS_JSON_PATH = "res://extensions/extensions.json"
const EXTENSION_SCRIPTS_DIR = "res://extensions/scripts/"

var _extensions_data: Array[Dictionary] = []
var _extensions_status: Dictionary = {} # Stores the current installation status, e.g., {"steam_shortcut_manager_installer": true}
var _extensions_update_available: Dictionary = {} # Stores which extensions have an update available, {"extension_id": "latest_version"}

var _check_thread: Thread = null
var _check_queue: Array[Dictionary] = []
var _is_checking: bool = false
var _update_check_queue: Array[Dictionary] = [] # Queue for update checks
var _is_checking_updates: bool = false # Flag to prevent concurrent update checks

func _ready():
	_load_extensions_from_json()
	check_all_extensions_status()

# --- Public API ---

func get_all_extensions() -> Array[Dictionary]:
	return _extensions_data

func get_extension_status(extension_id: String) -> bool:
	return _extensions_status.get(extension_id, false)

func get_update_status(extension_id: String) -> String:
	return _extensions_update_available.get(extension_id, "") # Returns latest_version string if update available, else empty

func install_extension(extension_id: String):
	_execute_operation(extension_id, "install")

func uninstall_extension(extension_id: String):
	_execute_operation(extension_id, "remove")

func update_extension(extension_id: String):
	_execute_operation(extension_id, "update")


# --- Internal Logic ---

func _execute_operation(extension_id: String, operation: String):
	var extension_data: Dictionary
	for ext in _extensions_data:
		if ext.get("id") == extension_id:
			extension_data = ext
			break
	
	if extension_data.is_empty():
		printerr("ExtensionManager ERROR: Could not find extension data for id: ", extension_id)
		return

	emit_signal("extension_operation_started", extension_id, operation)
	
	# Create and start a new thread for the operation
	var operation_thread = Thread.new()
	var callable_func = func():
		_execute_operation_script_in_thread(extension_data, operation)
	operation_thread.start(callable_func)


func _execute_operation_script_in_thread(extension_data: Dictionary, operation: String):
	var script_name = extension_data.get("script_name", "")
	if script_name.is_empty():
		call_deferred("_process_operation_result", extension_data, operation, -1)
		return

	var script_path = ProjectSettings.globalize_path(EXTENSION_SCRIPTS_DIR.path_join(script_name))
	var output: PackedStringArray = []
	var exit_code = OS.execute("sh", [script_path, operation], output, true, true)
	
	call_deferred("_process_operation_result", extension_data, operation, exit_code)


func _process_operation_result(extension_data: Dictionary, operation: String, exit_code: int):
	var extension_id = extension_data.get("id", "")
	print("INFO ExtensionManager: Operation '", operation, "' for '", extension_id, "' finished with exit code ", exit_code)

	# After install/remove/update, we need to re-check the status and updates
	check_all_extensions_status() # This will eventually trigger update checks
	emit_signal("extension_operation_finished", extension_id, operation)


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
	_check_queue.clear() # Clear existing queue
	for ext_data in _extensions_data:
		_check_queue.append(ext_data)
	
	_start_next_check()

func _start_next_check():
	if _is_checking or _check_queue.is_empty():
		_is_checking = false # Reset flag if queue is empty
		check_for_updates_for_all_installed_extensions() # Trigger update checks after all status checks are done
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


# --- Update Check Logic ---

func check_for_updates_for_all_installed_extensions():
	if _is_checking_updates:
		print("INFO ExtensionManager: Update check is already in progress.")
		return
	
	print("INFO ExtensionManager: Starting update check for installed extensions.")
	_extensions_update_available.clear() # Clear previous update info

	_update_check_queue.clear()
	for ext_data in _extensions_data:
		if _extensions_status.get(ext_data.get("id"), false): # Only check installed extensions
			_update_check_queue.append(ext_data)
	
	_start_next_update_check()

func _start_next_update_check():
	if _is_checking_updates or _update_check_queue.is_empty():
		_is_checking_updates = false # Reset flag if queue is empty
		print("INFO ExtensionManager: All update checks completed.")
		return
	
	_is_checking_updates = true
	var extension_to_check = _update_check_queue.pop_front()
	
	var repository_url = extension_to_check.get("repository_url", "")
	if repository_url.is_empty() or not repository_url.begins_with("https://github.com/"):
		printerr("ExtensionManager ERROR: Missing or invalid repository_url for update check for '", extension_to_check.get("id"), "'.")
		_is_checking_updates = false
		_start_next_update_check()
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(func(result, response_code, headers, body):
		_on_github_release_request_completed(extension_to_check, result, response_code, headers, body)
	)
	
	var api_url = repository_url.replace("https://github.com/", "https://api.github.com/repos/") + "/releases/latest"
	print("INFO ExtensionManager: Requesting latest release info for '", extension_to_check.get("id"), "' from ", api_url)
	
	# GitHub API best practices: User-Agent header is often required
	var headers = ["User-Agent: GodotDeckStore/1.0", "Accept: application/vnd.github.v3+json"]
	http_request.request(api_url, headers)

func _on_github_release_request_completed(extension_data: Dictionary, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var http_request_node = get_children().filter(func(child): return child is HTTPRequest && child.is_connected("request_completed", func(r,c,h,b): _on_github_release_request_completed(extension_data, r,c,h,b))).front()
	if http_request_node:
		http_request_node.queue_free() # Clean up the HTTPRequest node
	
	var extension_id = extension_data.get("id", "")
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		printerr("ExtensionManager ERROR: Failed to fetch latest release for '", extension_id, "'. Result: ", result, ", Code: ", response_code)
		_is_checking_updates = false
		_start_next_update_check()
		return

	var json_string = body.get_string_from_utf8()
	var parse_result = JSON.parse_string(json_string)

	if not parse_result is Dictionary:
		printerr("ExtensionManager ERROR: Invalid JSON response for GitHub release for '", extension_id, "'.")
		_is_checking_updates = false
		_start_next_update_check()
		return
	
	var latest_tag_name = parse_result.get("tag_name", "")
	if latest_tag_name.is_empty():
		printerr("ExtensionManager WARNING: 'tag_name' not found in GitHub release response for '", extension_id, "'. Assuming no version info.")
		_is_checking_updates = false
		_start_next_update_check()
		return
	
	# Clean version string (e.g., remove 'v' prefix)
	var latest_version = latest_tag_name.lstrip("v")
	
	# Get currently installed version by executing the script
	var script_name = extension_data.get("script_name", "")
	if script_name.is_empty():
		printerr("ExtensionManager ERROR: Script name missing for '", extension_id, "' to get current version.")
		_is_checking_updates = false
		_start_next_update_check()
		return
	
	var script_path = ProjectSettings.globalize_path(EXTENSION_SCRIPTS_DIR.path_join(script_name))
	var output_array: PackedStringArray = []
	var exit_code = OS.execute("sh", [script_path, "version"], output_array, true, true)
	
	var current_version = "0.0.0"
	if exit_code == 0 && output_array.size() > 0:
		current_version = output_array[0].strip_edges()
	
	print("INFO ExtensionManager: '", extension_id, "' - Current: ", current_version, ", Latest: ", latest_version)

	if _compare_versions(current_version, latest_version) < 0: # current < latest
		_extensions_update_available[extension_id] = latest_version
		emit_signal("extension_update_available", extension_id, latest_version)
		print("INFO ExtensionManager: Update available for '", extension_id, "' to version ", latest_version)
	else:
		_extensions_update_available.erase(extension_id) # No update needed
	
	_is_checking_updates = false
	_start_next_update_check()


func _compare_versions(version1: String, version2: String) -> int:
	# Returns -1 if version1 < version2, 0 if version1 == version2, 1 if version1 > version2
	var v1_parts = version1.split(".")
	var v2_parts = version2.split(".")

	for i in range(max(v1_parts.size(), v2_parts.size())):
		var p1 = 0
		if i < v1_parts.size():
			p1 = int(v1_parts[i])
		
		var p2 = 0
		if i < v2_parts.size():
			p2 = int(v2_parts[i])
		
		if p1 < p2:
			return -1
		if p1 > p2:
			return 1
			
	return 0