extends Node

signal extension_status_updated(extension_id, is_installed)
signal extension_operation_started(extension_id, operation)
signal extension_operation_finished(extension_id, operation)
signal extension_update_available(extension_id, latest_version)
signal extension_progress_updated(extension_id, percent, message)

const EXTENSIONS_ROOT_DIR = "res://extensions/"
const TMP_LOG_FILE = "user://tmp_ext_log.txt"

var _extensions_data: Array[Dictionary] = []
var _extensions_status: Dictionary = {} 
var _extensions_update_available: Dictionary = {}

var _check_thread: Thread = null
var _check_queue: Array[Dictionary] = []
var _is_checking: bool = false
var _update_check_queue: Array[Dictionary] = []
var _is_checking_updates: bool = false 

# Transaction Queue
var _transaction_queue: Array[Dictionary] = []
var _transaction_active: bool = false

# Progress Monitoring
var _progress_timer: Timer
var _monitored_extensions: Array[String] = []
var _progress_base_path: String = ""

func _ready():
	_setup_paths()
	_setup_timer()
	_load_extensions()
	check_all_extensions_status()

func _setup_paths():
	var home = OS.get_environment("HOME")
	if home.is_empty():
		home = "user://" # Fallback
	_progress_base_path = home.path_join(".deck-store/tmp/progress/extensions")

func _setup_timer():
	_progress_timer = Timer.new()
	_progress_timer.wait_time = 0.1 # Check every 100ms
	_progress_timer.one_shot = false
	_progress_timer.timeout.connect(_check_progress_files)
	add_child(_progress_timer)

func _check_progress_files():
	for ext_id in _monitored_extensions:
		var file_path = _progress_base_path.path_join(ext_id + ".txt")
		if FileAccess.file_exists(file_path):
			var file = FileAccess.open(file_path, FileAccess.READ)
			if file:
				var content = file.get_as_text().strip_edges()
				file.close()
				if not content.is_empty():
					var parts = content.split("|", true, 1) 
					if parts.size() >= 2:
						var percent_str = parts[0]
						var message = parts[1]
						if percent_str.is_valid_int():
							emit_signal("extension_progress_updated", ext_id, int(percent_str), message)

# --- Public API ---

func get_all_extensions() -> Array[Dictionary]:
	return _extensions_data

func get_extension_status(extension_id: String) -> bool:
	return _extensions_status.get(extension_id, false)

func get_update_status(extension_id: String) -> String:
	return _extensions_update_available.get(extension_id, "") 

func get_extension_data(extension_id: String) -> Dictionary:
	for ext in _extensions_data:
		if ext.get("id") == extension_id:
			return ext
	return {}

# Returns a list of extension IDs that are required by `extension_id` but NOT currently installed.
# Recursively checks dependencies. Returns ordered list (Leaf -> Root).
func get_missing_dependencies(extension_id: String) -> Array[String]:
	var missing: Array[String] = []
	var visited: Array[String] = [] # To prevent infinite loops
	_collect_missing_dependencies_recursive(extension_id, missing, visited)
	return missing

func _collect_missing_dependencies_recursive(current_id: String, missing_list: Array[String], visited: Array[String]):
	if visited.has(current_id):
		return
	visited.append(current_id)
	
	var data = get_extension_data(current_id)
	var dependencies = data.get("dependencies", [])
	
	if dependencies is Array:
		for dep_id in dependencies:
			# Check sub-dependencies first (Depth-First)
			_collect_missing_dependencies_recursive(dep_id, missing_list, visited)
			
			# If this dependency is missing and not already in our list, add it
			if not get_extension_status(dep_id) and not missing_list.has(dep_id):
				missing_list.append(dep_id)

# Returns a list of extension IDs that are installed and depend on `extension_id`.
# Recursively checks dependents. Returns ordered list for removal (Leaf dependents first).
func get_installed_dependents(extension_id: String) -> Array[String]:
	var dependents: Array[String] = []
	var visited: Array[String] = []
	_collect_installed_dependents_recursive(extension_id, dependents, visited)
	return dependents

func _collect_installed_dependents_recursive(target_id: String, dependents_list: Array[String], visited: Array[String]):
	if visited.has(target_id):
		return
	visited.append(target_id)
	
	# Find direct dependents
	var direct_dependents = []
	for ext in _extensions_data:
		var ext_id = ext.get("id")
		# Only consider installed extensions
		if get_extension_status(ext_id):
			var deps = ext.get("dependencies", [])
			if deps is Array and deps.has(target_id):
				direct_dependents.append(ext_id)
	
	# For each direct dependent, collect IT'S dependents first (recursion)
	for dep_id in direct_dependents:
		_collect_installed_dependents_recursive(dep_id, dependents_list, visited)
		
		# Add to list if not present
		if not dependents_list.has(dep_id):
			dependents_list.append(dep_id)

# Starts a batch transaction.
func execute_transaction(ids: Array, operation: String):
	if _transaction_active:
		printerr("ExtensionsManager: Transaction already active. Cannot start new one.")
		return
	
	if ids.is_empty():
		return
		
	print("INFO ExtensionManager: Starting transaction '", operation, "' for: ", ids)
	_transaction_queue.clear()
	for id in ids:
		_transaction_queue.append({ "id": id, "op": operation })
	
	_transaction_active = true
	_process_next_transaction_item()

func install_extension(extension_id: String):
	execute_transaction([extension_id], "install")

func uninstall_extension(extension_id: String):
	execute_transaction([extension_id], "remove")

func update_extension(extension_id: String):
	execute_transaction([extension_id], "update")


# --- Internal Logic ---

func _process_next_transaction_item():
	if _transaction_queue.is_empty():
		_transaction_active = false
		print("INFO ExtensionManager: Transaction completed.")
		return

	var item = _transaction_queue.pop_front()
	var ext_id = item["id"]
	var op = item["op"]
	
	_execute_operation(ext_id, op)

func _execute_operation(extension_id: String, operation: String):
	var extension_data = get_extension_data(extension_id)
	
	if extension_data.is_empty():
		printerr("ExtensionManager ERROR: Could not find extension data for id: ", extension_id)
		if _transaction_active:
			_process_next_transaction_item()
		return

	emit_signal("extension_operation_started", extension_id, operation)
	
	if not _monitored_extensions.has(extension_id):
		_monitored_extensions.append(extension_id)
	if _progress_timer.is_stopped():
		_progress_timer.start()
	
	var operation_thread = Thread.new()
	var callable_func = func():
		_execute_operation_script_in_thread(extension_data, operation)
	operation_thread.start(callable_func)


func _execute_operation_script_in_thread(extension_data: Dictionary, operation: String):
	var script_name = extension_data.get("script_name", "")
	var internal_path = extension_data.get("internal_path", "") # Added internal path
	
	if script_name.is_empty() or internal_path.is_empty():
		printerr("ExtensionManager ERROR: Missing script name or internal path for ", extension_data.get("id"))
		call_deferred("_process_operation_result", extension_data, operation, -1)
		return

	var script_path = ProjectSettings.globalize_path(internal_path.path_join(script_name))
	var log_file_path = ProjectSettings.globalize_path(TMP_LOG_FILE)
	
	if FileAccess.file_exists(log_file_path):
		DirAccess.remove_absolute(log_file_path)

	var exit_code = OS.execute("sh", [script_path, operation, log_file_path], [], true, true)
	
	if FileAccess.file_exists(log_file_path):
		var file = FileAccess.open(log_file_path, FileAccess.READ)
		print("INFO ExtensionManager: --- Script Output ---")
		while not file.eof_reached():
			var line = file.get_line()
			if not line.is_empty():
				print("  ", line)
		print("INFO ExtensionManager: --- End Script Output ---")
		file.close()
		DirAccess.remove_absolute(log_file_path)
	
	call_deferred("_process_operation_result", extension_data, operation, exit_code)


func _process_operation_result(extension_data: Dictionary, operation: String, exit_code: int):
	var extension_id = extension_data.get("id", "")
	print("INFO ExtensionManager: Operation '", operation, "' for '", extension_id, "' finished with exit code ", exit_code)

	if _monitored_extensions.has(extension_id):
		_monitored_extensions.erase(extension_id)
	
	var progress_file = _progress_base_path.path_join(extension_id + ".txt")
	if FileAccess.file_exists(progress_file):
		DirAccess.remove_absolute(progress_file)
	
	if _monitored_extensions.is_empty():
		_progress_timer.stop()

	check_all_extensions_status() 
	
	# If update was successful, clear the update flag immediately
	if operation == "update" and exit_code == 0:
		if _extensions_update_available.has(extension_id):
			_extensions_update_available.erase(extension_id)
			
	emit_signal("extension_operation_finished", extension_id, operation)
	
	if _transaction_active:
		if exit_code != 0:
			print("ERROR ExtensionManager: Transaction aborted due to failure in step: ", extension_id)
			_transaction_active = false
			_transaction_queue.clear()
		else:
			_process_next_transaction_item()


# Scans the extensions folder for extension.json files.
func _load_extensions():
	_extensions_data.clear()
	var dir = DirAccess.open(EXTENSIONS_ROOT_DIR)
	if not dir:
		printerr("ExtensionManager ERROR: Could not open extensions root directory: ", EXTENSIONS_ROOT_DIR)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			var extension_dir_path = EXTENSIONS_ROOT_DIR.path_join(file_name)
			var json_path = extension_dir_path.path_join("extension.json")
			
			if FileAccess.file_exists(json_path):
				_load_single_extension(json_path, extension_dir_path)
				
		file_name = dir.get_next()
	
	print("INFO ExtensionManager: Successfully loaded %d extensions." % _extensions_data.size())

func _load_single_extension(json_path: String, dir_path: String):
	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return
	var json_string = file.get_as_text()
	file.close()
	
	var parse_result = JSON.parse_string(json_string)
	if parse_result is Dictionary:
		var ext_data = parse_result as Dictionary
		# Inject the internal path so we know where assets are located
		ext_data["internal_path"] = dir_path
		_extensions_data.append(ext_data)
	else:
		printerr("ExtensionManager WARNING: Invalid JSON in ", json_path)


# Queues up all extensions to have their installation status checked.
func check_all_extensions_status():
	if _is_checking:
		print("INFO ExtensionManager: A check is already in progress.")
		return
	
	print("INFO ExtensionManager: Queuing all extensions for status check.")
	_check_queue.clear()
	for ext_data in _extensions_data:
		_check_queue.append(ext_data)
	
	_start_next_check()

func _start_next_check():
	if _check_queue.is_empty():
		_is_checking = false
		check_for_updates_for_all_installed_extensions()
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
	var internal_path = extension_data.get("internal_path", "")
	
	if script_name.is_empty() or internal_path.is_empty():
		call_deferred("_process_check_result", extension_data, -1)
		return
		
	var script_path = ProjectSettings.globalize_path(internal_path.path_join(script_name))
	var log_file_path = ProjectSettings.globalize_path(TMP_LOG_FILE)
	
	if FileAccess.file_exists(log_file_path):
		DirAccess.remove_absolute(log_file_path)
		
	var exit_code = OS.execute("sh", [script_path, "check", log_file_path], [], true, true)
	
	if FileAccess.file_exists(log_file_path):
		DirAccess.remove_absolute(log_file_path)
	
	call_deferred("_process_check_result", extension_data, exit_code)

func _process_check_result(extension_data: Dictionary, exit_code: int):
	var extension_id = extension_data.get("id", "")
	if not extension_id.is_empty():
		var is_installed = (exit_code == 0)
		_extensions_status[extension_id] = is_installed
		emit_signal("extension_status_updated", extension_id, is_installed)
	
	# We don't set _is_checking to false here, _start_next_check handles it
	_start_next_check()


# --- Update Check Logic ---

func check_for_updates_for_all_installed_extensions():
	if _is_checking_updates:
		print("INFO ExtensionManager: Update check is already in progress.")
		return
	
	print("INFO ExtensionManager: Starting update check for installed extensions.")
	# We don't clear all updates here, only when a check succeeds we update the status.
	# Actually, clearing is fine if we check everything.

	_update_check_queue.clear()
	for ext_data in _extensions_data:
		var ext_id = ext_data.get("id")
		var is_installed = _extensions_status.get(ext_id, false)
		if is_installed:
			_update_check_queue.append(ext_data)
	
	if _update_check_queue.is_empty():
		print("INFO ExtensionManager: No installed extensions to check for updates.")
		return

	_start_next_update_check()

func _start_next_update_check():
	if _update_check_queue.is_empty():
		_is_checking_updates = false
		print("INFO ExtensionManager: All update checks completed.")
		return
	
	_is_checking_updates = true
	var extension_to_check = _update_check_queue.pop_front()
	var ext_id = extension_to_check.get("id", "unknown")
	
	var repository_url = extension_to_check.get("repository_url", "")
	
	if repository_url.is_empty() or not repository_url.begins_with("https://github.com/"):
		_start_next_update_check()
		return
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(func(result, response_code, headers, body):
		_on_github_release_request_completed(extension_to_check, result, response_code, headers, body)
	)
	
	var api_url = repository_url.replace("https://github.com/", "https://api.github.com/repos/") + "/releases/latest"
	var headers = ["User-Agent: GodotDeckStore/1.0", "Accept: application/vnd.github.v3+json"]
	http_request.request(api_url, headers)

func _on_github_release_request_completed(extension_data: Dictionary, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	# Request cleanup handled via queue_free in a safer way
	
	var extension_id = extension_data.get("id", "")
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_start_next_update_check()
		return

	var json_string = body.get_string_from_utf8()
	var parse_result = JSON.parse_string(json_string)

	if not parse_result is Dictionary:
		_start_next_update_check()
		return
	
	var latest_tag_name = parse_result.get("tag_name", "")
	if latest_tag_name.is_empty():
		_start_next_update_check()
		return
	
	var latest_version = latest_tag_name.lstrip("v")
	var script_name = extension_data.get("script_name", "")
	var internal_path = extension_data.get("internal_path", "")
	
	var script_path = ProjectSettings.globalize_path(internal_path.path_join(script_name))
	var log_file_path = ProjectSettings.globalize_path(TMP_LOG_FILE)
	
	var exit_code = OS.execute("sh", [script_path, "version", log_file_path], [], true, true)
	
	var current_version = "0.0.0"
	if exit_code == 0:
		if FileAccess.file_exists(log_file_path):
			var file = FileAccess.open(log_file_path, FileAccess.READ)
			var version_from_file = file.get_as_text().strip_edges()
			if not version_from_file.is_empty():
				current_version = version_from_file
			file.close()
			DirAccess.remove_absolute(log_file_path)

	if _compare_versions(current_version, latest_version) < 0:
		_extensions_update_available[extension_id] = latest_version
		emit_signal("extension_update_available", extension_id, latest_version)
		print("INFO ExtensionManager: Update available for '", extension_id, "' to version ", latest_version)
	else:
		_extensions_update_available.erase(extension_id)
	
	_start_next_update_check()


func _compare_versions(version1: String, version2: String) -> int:
	var v1_parts = version1.split(".")
	var v2_parts = version2.split(".")

	for i in range(max(v1_parts.size(), v2_parts.size())):
		var p1 = 0
		if i < v1_parts.size() and v1_parts[i].is_valid_int():
			p1 = int(v1_parts[i])
		
		var p2 = 0
		if i < v2_parts.size() and v2_parts[i].is_valid_int():
			p2 = int(v2_parts[i])
		
		if p1 < p2:
			return -1
		if p1 > p2:
			return 1
			
	return 0
