extends Node

signal task_added(operation_id, app_id, operation_type)
signal task_updated(operation_id, status_data)
signal task_finished(operation_id, final_status, operation_type)

const FLATPAK_SPAWN_CMD = "/usr/bin/flatpak-spawn"
const OUTPUT_DIR = "user://flatpak_logs"

var task_queue: Array[Dictionary] = [] 
var running_tasks: Dictionary = {}
var current_task_processing: bool = false

var current_op_id: String = ""
var current_pid: int = -1
var current_output_file: String = ""
var current_file_access: FileAccess = null
var last_read_pos: int = 0

var _regex_progress := RegEx.new()
var _regex_speed := RegEx.new()
var _regex_eta := RegEx.new()
var _regex_complete := RegEx.new()
var _regex_error := RegEx.new()
var _regex_uninstalling := RegEx.new()

func _ready():
	randomize()
	DirAccess.make_dir_absolute(OUTPUT_DIR)
	_cleanup_old_logs()

	_regex_progress.compile("^Installing(?:\\s[0-9]+\\/[0-9]+)?\\?\\s+\\?+\\s+([0-9]+)%")
	_regex_speed.compile("([0-9.,]+\\??\\s*(?:k|M|G)i?B\\/s)")
	_regex_eta.compile("([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?)$")
	_regex_complete.compile("^(Installation|Uninstall) complete\\.?")
	_regex_error.compile("(?:Error:|error:)\\s*(.*)")
	_regex_uninstalling.compile("^Uninstalling\\?")


func queue_install(app_id: String, app_data: Dictionary = {}) -> String:
	return _add_task("install", app_id, app_data)

func queue_uninstall(app_id: String, app_data: Dictionary = {}) -> String:
	print("INFO DownloadManager: Queueing Uninstall for ", app_id)

	if ProjectSettings.has_setting("autoload/SteamIntegration"):
		if SteamIntegration.has_method("remove_from_steam"):
			print("INFO DownloadManager: Triggering SteamIntegration.remove_from_steam for ", app_id)
			var _started = SteamIntegration.remove_from_steam(app_id)
			if not _started: printerr("DownloadManager WARN: Could not start remove_from_steam thread.")
		else: printerr("DownloadManager ERROR: SteamIntegration node missing 'remove_from_steam' method!")
	else: printerr("DownloadManager: SteamIntegration Autoload not found.")

	return _add_task("uninstall", app_id, app_data)

func cancel_operation(operation_id: String):
	if running_tasks.has(operation_id):
		var task = running_tasks[operation_id]
		var op_type = task.get("operation_type", "unknown")
		if task.operation_id == current_op_id and current_pid > 0:
			var err = OS.kill(current_pid)
			if err == OK: print("Attempting to cancel process PID: ", current_pid)
			else: 
				printerr("Failed to kill process PID: ", current_pid, " Error: ", err)
				_finish_task(operation_id, -1, true, "Failed to kill process")
		elif task.status_data.get("status") == "queued":
			for i in range(task_queue.size()):
				if task_queue[i].operation_id == operation_id:
					task_queue.remove_at(i)
					running_tasks.erase(operation_id)
					emit_signal("task_finished", operation_id, "cancelled", op_type)
					print("Cancelled queued task: ", operation_id)
					return
		else: 
			printerr("Cannot cancel task ", operation_id, " - not currently running or queued.")
	else: 
		printerr("Cannot cancel task ", operation_id, " - not found.")


func get_task_status(app_id: String) -> Dictionary:
	var task_keys = running_tasks.keys()
	for i in range(task_keys.size() - 1, -1, -1): 
		var op_id = task_keys[i]
		if running_tasks.has(op_id) and running_tasks[op_id].app_id == app_id: 
			return running_tasks[op_id].status_data
	return {}


func get_all_tasks() -> Array[Dictionary]:
	var tasks_for_ui: Array[Dictionary] = []
	if current_task_processing and running_tasks.has(current_op_id): 
		tasks_for_ui.append(running_tasks[current_op_id])
	tasks_for_ui.append_array(task_queue)
	return tasks_for_ui

func _add_task(op_type: String, app_id: String, app_data: Dictionary = {}) -> String:
	var timestamp_sec = Time.get_unix_time_from_system()
	var timestamp_usec = Time.get_ticks_usec()
	var random_num = randi()
	var operation_id = "%s-%s-%s" % [timestamp_sec, timestamp_usec, random_num]
	var initial_status_data = {
		"status": "queued", "app_id": app_id, "operation_id": operation_id,
		"progress": null, "speed": null, "eta": null, "error": null,
		"name": app_data.get("name", app_id),
		"icon_url": app_data.get("icon_url", "")
	}
	var task_data = {
		"operation_id": operation_id, "app_id": app_id, "operation_type": op_type,
		"pid": -1, "output_file": "", "status_data": initial_status_data }
	task_queue.append(task_data)
	running_tasks[operation_id] = task_data
	if op_type != "uninstall": 
		emit_signal("task_added", operation_id, app_id, op_type)
	print("Task added to queue: ", task_data)
	_check_start_next_task()
	return operation_id

func _check_start_next_task():
	if not current_task_processing and not task_queue.is_empty():
		current_task_processing = true
		var next_task = task_queue.pop_front()
		_execute_task(next_task)

func _execute_task(task_data: Dictionary):
	print("Executing task via flatpak-spawn: ", task_data.operation_id)
	current_op_id = task_data.operation_id
	current_output_file = OUTPUT_DIR.path_join("flatpak_output_%s.log" % current_op_id)
	last_read_pos = 0
	if not FileAccess.file_exists(FLATPAK_SPAWN_CMD): 
		printerr("FEHLER: flatpak-spawn not found: ", FLATPAK_SPAWN_CMD)
		_finish_task(current_op_id, -1, false, "flatpak-spawn not found")
		return
	task_data.output_file = current_output_file
	task_data.status_data = { "status": "preparing", "app_id": task_data.app_id, "operation_id": current_op_id, "progress": null, "speed": null, "eta": null, "error": null, "name": task_data.status_data.get("name"), "icon_url": task_data.status_data.get("icon_url")}
	running_tasks[current_op_id] = task_data
	emit_signal("task_updated", current_op_id, task_data.status_data)
	var da := DirAccess.open(OUTPUT_DIR)
	if da and FileAccess.file_exists(current_output_file): 
		da.remove(current_output_file.get_file())
	var host_command = "flatpak"
	var host_args = [task_data.operation_type, "--user", "--assumeyes", task_data.app_id]
	var global_log_path = ProjectSettings.globalize_path(current_output_file)
	var host_shell_command = "LC_ALL=C " + host_command
	for arg in host_args: 
		host_shell_command += " '%s'" % arg.replace("'", "'\\''")
		host_shell_command += " > '%s' 2>&1" % global_log_path.replace("'", "'\\''")
	var spawn_args = ["--host", "sh", "-c", host_shell_command]
	print("Attempting OS.create_process:")
	print("  Command: ", FLATPAK_SPAWN_CMD)
	print("  Arguments: ", spawn_args)
	var pid = OS.create_process(FLATPAK_SPAWN_CMD, spawn_args)
	if pid <= 0: 
		printerr("Failed to start flatpak-spawn process for ", task_data.app_id)
		_finish_task(current_op_id, -1, false, "Failed to start flatpak-spawn")
		return
	current_pid = pid
	task_data.pid = pid
	running_tasks[current_op_id] = task_data
	print("Started flatpak-spawn process PID: ", current_pid, " for OpID: ", current_op_id)


func _process(_delta):
	if not current_task_processing or current_op_id.is_empty(): 
		return
	if not running_tasks.has(current_op_id): 
		current_task_processing = false
		return
	var task = running_tasks[current_op_id]
	var process_is_running = OS.is_process_running(current_pid)
	var read_ok = _read_and_parse_log_update(task)
	if not read_ok: 
		return
	if not process_is_running:
		print("Process finished detected in _process (PID %d) AFTER final read attempt, calling finish..." % current_pid)
		var final_exit_code = 0
		if task.status_data.get("status") == "failed": 
			final_exit_code = 1
		_finish_task(current_op_id, final_exit_code)
		return

func _read_and_parse_log_update(task: Dictionary) -> bool:
	if current_file_access == null:
		if FileAccess.file_exists(task.output_file):
			current_file_access = FileAccess.open(task.output_file, FileAccess.READ)
			if current_file_access == null:
				var err = FileAccess.get_open_error()
				printerr("Failed to open output file: ", task.output_file, " Error: ", err)
				_finish_task(task.operation_id, -1, false, "Failed to open output file: %d" % err)
				return false
			current_file_access.seek(last_read_pos)
		else:
			return true

	if not is_instance_valid(current_file_access) or not current_file_access.is_open():
		current_file_access = null
		return true

	var file_len = current_file_access.get_length()
	if current_file_access.get_position() >= file_len:
		return true

	var something_was_updated_in_this_cycle = false
	var status_data_in_progress = task.status_data.duplicate(true)

	while current_file_access.get_position() < file_len:
		var line = current_file_access.get_line().strip_edges()
		var current_read_pos = current_file_access.get_position()

		if line.is_empty():
			last_read_pos = current_read_pos
			continue

		var line_status = null
		var line_progress = -1
		var line_speed = null
		var line_eta = null
		var line_error = null
		var line_matched = false

		if task.operation_type == "install":
			var error_match = _regex_error.search(line)
			if error_match:
				line_matched = true
				line_status = "failed"
				line_error = error_match.get_string(1)
				print("DEBUG: Matched Error: ", line_error)
			else:
				var complete_match = _regex_complete.search(line)
				if complete_match and complete_match.get_string(1) == "Installation":
					line_matched = true
					line_status = "completed"
					line_progress = 100
					print("DEBUG: Matched Installation complete")
				else:
					var progress_match = _regex_progress.search(line)
					if progress_match:
						line_matched = true
						line_progress = progress_match.get_string(1).to_int()
						line_status = "installing"

						var speed_match = _regex_speed.search(line)
						if speed_match:
							line_speed = speed_match.get_string(1).replace("?", "")
							line_status = "downloading"

						var eta_match = _regex_eta.search(line)
						if eta_match:
							line_eta = eta_match.get_string(1)

						if line_progress == 100 and line_status == "downloading":
							line_status = "installing"

		elif task.operation_type == "uninstall":
			var error_match = _regex_error.search(line)
			if error_match:
				line_matched = true
				line_status = "failed"
				line_error = error_match.get_string(1)
				print("DEBUG: Matched Error: ", line_error)
			else:
				var complete_match = _regex_complete.search(line)
				if complete_match and complete_match.get_string(1) == "Uninstall":
					line_matched = true
					line_status = "completed"
					line_progress = 100
					print("DEBUG: Matched Uninstall complete")
				else:
					if _regex_uninstalling.search(line):
						line_matched = true
						line_status = "removing"
						print("DEBUG: Matched Uninstalling?")
		if line_matched:
			var changed_locally = false
			if line_status != null and status_data_in_progress.get("status") != line_status:
				status_data_in_progress.status = line_status
				changed_locally = true
			if line_progress != -1 and status_data_in_progress.get("progress") != line_progress:
				status_data_in_progress.progress = line_progress
				changed_locally = true
			if line_speed != null and status_data_in_progress.get("speed") != line_speed:
				status_data_in_progress.speed = line_speed
				changed_locally = true
			if line_eta != null and status_data_in_progress.get("eta") != line_eta:
				status_data_in_progress.eta = line_eta
				changed_locally = true
			if line_error != null and status_data_in_progress.get("error") != line_error:
				status_data_in_progress.error = line_error
				changed_locally = true

			if status_data_in_progress.status != "downloading":
				if status_data_in_progress.get("speed") != null: 
					status_data_in_progress.speed = null
					changed_locally = true
				if status_data_in_progress.get("eta") != null: 
					status_data_in_progress.eta = null
					changed_locally = true

			if changed_locally:
				something_was_updated_in_this_cycle = true
		last_read_pos = current_read_pos

	if something_was_updated_in_this_cycle and running_tasks.has(task.operation_id):
		if task.status_data != status_data_in_progress:
			running_tasks[task.operation_id].status_data = status_data_in_progress 
			print("INFO: Emitting task_updated (changes detected): ", status_data_in_progress)
			emit_signal("task_updated", task.operation_id, status_data_in_progress)

	return true

func _finish_task(op_id: String, exit_code: int, cancelled: bool = false, error_msg: String = ""):
	if not running_tasks.has(op_id):
		if op_id == current_op_id: 
			current_task_processing = false
			current_op_id = ""
			current_pid = -1
			_check_start_next_task()
		return

	var was_current = (op_id == current_op_id)
	print("Finishing task: ", op_id, " ExitCode: ", exit_code, " Cancelled: ", cancelled, " ErrorMsg: ", error_msg)

	if was_current and is_instance_valid(current_file_access) and current_file_access.is_open():
		current_file_access.close()
		current_file_access = null

	var task = running_tasks[op_id]
	var final_status_data = task.status_data.duplicate(true)
	var op_type = task.get("operation_type", "unknown")
	var final_status = final_status_data.get("status", "unknown")

	if cancelled: final_status = "cancelled"
	elif not error_msg.is_empty(): 
		final_status = "failed"
		final_status_data.error = error_msg
	elif exit_code != 0: 
		final_status = "failed"
		final_status_data.error = final_status_data.error if final_status_data.error else "Process exited with code: %d" % exit_code
	elif final_status != "failed": final_status = "completed"

	final_status_data.status = final_status
	if final_status == "completed" or final_status == "failed": 
		final_status_data.progress = 100
		final_status_data.erase("speed")
		final_status_data.erase("eta")

	running_tasks[op_id].status_data = final_status_data
	emit_signal("task_updated", op_id, final_status_data)
	emit_signal("task_finished", op_id, final_status, op_type)

	if final_status == "completed":
		var app_id = task.app_id
		var app_name = final_status_data.get("name")
		var icon_url = final_status_data.get("icon_url", "")

		print("DEBUG DownloadManager: Task completed, attempting Steam integration. AppName='%s'" % app_name)

		var icon_cache_path = _get_cached_icon_path_for_app(app_id, icon_url)
		var global_icon_path = ""
		if not icon_cache_path.is_empty():
			global_icon_path = ProjectSettings.globalize_path(icon_cache_path)
			print("INFO DownloadManager: Found cached icon at: ", global_icon_path)
		else:
			print("WARN DownloadManager: No cached icon found for ", app_id, ". Proceeding without icon.")

		print("DEBUG Trying to add app to steam")
		if ProjectSettings.has_setting("autoload/SteamIntegration"):
			print("DEBUG SteamIntegration available. op_type is:", op_type)
			if op_type == "install":
				if not app_name or app_name == app_id: 
					printerr("Cannot add to Steam: App name missing...")
				elif SteamIntegration.has_method("add_to_steam"):
					SteamIntegration.add_to_steam(app_id, app_name, global_icon_path)
			elif op_type == "remove":
				if SteamIntegration.has_method("remove_from_steam"):
					SteamIntegration.remove_from_steam(app_id)
		else:
			printerr("DownloadManager: SteamIntegration Autoload not found!")
	var da := DirAccess.open(OUTPUT_DIR)
	if da and FileAccess.file_exists(task.output_file):
		print("INFO DownloadManager: Removing log file: ", task.output_file)
		da.remove(task.output_file.get_file())

	if was_current:
		current_op_id = ""
		current_pid = -1
		current_output_file = ""
		last_read_pos = 0
		current_task_processing = false
		_check_start_next_task()

func _cleanup_old_logs():
	var dir = DirAccess.open(OUTPUT_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and (file_name.begins_with("flatpak_output_") and file_name.ends_with(".log")):
				print("Cleaning up old log: ", file_name)
				var err = dir.remove(file_name)
				if err != OK: printerr("Failed to remove old log file: ", file_name, " Error code: ", err)
			file_name = dir.get_next()
	else: printerr("Failed to open output directory for cleanup: ", OUTPUT_DIR, " Error: ", DirAccess.get_open_error())

func _get_cached_icon_path_for_app(app_id: String, icon_url: String) -> String:
	if icon_url.is_empty(): 
		print("WARN DownloadManager: No icon URL provided for ", app_id)
		return ""

	var main_node = get_node_or_null("/root/App")
	if not main_node: 
		printerr("DownloadManager ERROR: Cannot access main node '/root/App'")
		return ""

	var image_cache_dir = ""
	if main_node.has_meta("IMAGE_CACHE_DIR"): 
		image_cache_dir = main_node.IMAGE_CACHE_DIR
	elif main_node.has_method("get_image_cache_dir"): 
		image_cache_dir = main_node.get_image_cache_dir()
	else: 
		printerr("DownloadManager ERROR: Cannot determine IMAGE_CACHE_DIR from main node.")
		return ""

	var url_hash = icon_url.md5_text()
	var path_png = image_cache_dir.path_join(url_hash + ".png")
	var path_webp = image_cache_dir.path_join(url_hash + ".webp")

	if FileAccess.file_exists(path_png): return path_png
	elif FileAccess.file_exists(path_webp): return path_webp
	else: 
		print("WARN DownloadManager: Icon for ", app_id, " not found in cache (URL: ", icon_url, ")")
		return ""
