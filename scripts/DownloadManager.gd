extends Node

# Signale
signal task_added(operation_id, app_id, operation_type)
signal task_updated(operation_id, status_data)
signal task_finished(operation_id, final_status)

const SCRIPT_PATH = "res://installer/flatpak/flatpak_install.sh"
const OUTPUT_DIR = "user://flatpak_logs"

var task_queue: Array[Dictionary] = []
var running_tasks: Dictionary = {}
var current_task_processing: bool = false

var current_op_id: String = ""
var current_pid: int = -1
var current_output_file: String = ""
var current_file_access: FileAccess = null
var last_read_pos: int = 0 # Korrigiert zu int (war vorher nicht explizit typisiert)

func _ready():
	randomize()
	DirAccess.make_dir_absolute(OUTPUT_DIR)
	_cleanup_old_logs()

# --- Öffentliche API ---

func queue_install(app_id: String) -> String:
	return _add_task("install", app_id)

func queue_uninstall(app_id: String) -> String:
	return _add_task("uninstall", app_id)

func cancel_operation(operation_id: String):
	if running_tasks.has(operation_id):
		var task = running_tasks[operation_id]
		if task.operation_id == current_op_id and current_pid > 0:
			var err = OS.kill(current_pid) # OS.kill gibt einen Error-Code zurück, nicht OK direkt
			if err == OK:
				print("Attempting to cancel process PID: ", current_pid)
			else:
				printerr("Failed to kill process PID: ", current_pid, " Error: ", err)
				# Task manuell als cancelled beenden
				_finish_task(operation_id, -1, true) # -1 als Platzhalter für unbekannten Exit Code
		elif task.status_data.status == "queued":
			for i in range(task_queue.size()):
				if task_queue[i].operation_id == operation_id:
					task_queue.remove_at(i)
					running_tasks.erase(operation_id)
					emit_signal("task_finished", operation_id, "cancelled")
					print("Cancelled queued task: ", operation_id)
					return
		else:
			printerr("Cannot cancel task ", operation_id, " - not the currently running process or not queued.")
	else:
		printerr("Cannot cancel task ", operation_id, " - not found.")


func get_task_status(app_id: String) -> Dictionary:
	for op_id in running_tasks:
		if running_tasks[op_id].app_id == app_id:
			return running_tasks[op_id].status_data
	return {}


func get_all_tasks() -> Array[Dictionary]:
	var all_tasks: Array[Dictionary] = []
	for op_id in running_tasks:
		all_tasks.append(running_tasks[op_id])
	return all_tasks

# --- Interne Logik ---

func _add_task(op_type: String, app_id: String) -> String:
	var timestamp_sec = Time.get_unix_time_from_system()
	var timestamp_usec = Time.get_ticks_usec() # Mikrosekunden seit Engine-Start
	var random_num = randi() # Zufällige Ganzzahl
	var operation_id = "%s-%s-%s" % [timestamp_sec, timestamp_usec, random_num]	
	var task_data = {
		"operation_id": operation_id,
		"app_id": app_id,
		"operation_type": op_type,
		"pid": -1,
		"output_file": "",
		"status_data": {"status": "queued", "app_id": app_id, "operation_id": operation_id}
	}
	task_queue.append(task_data)
	running_tasks[operation_id] = task_data
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
	print("Executing task: ", task_data.operation_id)
	current_op_id = task_data.operation_id
	current_output_file = OUTPUT_DIR.path_join("flatpak_output_%s.log" % current_op_id)
	last_read_pos = 0

	task_data.output_file = current_output_file
	task_data.status_data = {"status": "preparing", "app_id": task_data.app_id, "operation_id": current_op_id}
	running_tasks[current_op_id] = task_data
	emit_signal("task_updated", current_op_id, task_data.status_data)

	var da := DirAccess.open(OUTPUT_DIR)
	if da and FileAccess.file_exists(current_output_file):
		print("Removing old log file: ", current_output_file)
		da.remove(current_output_file.get_file())

	var command = SCRIPT_PATH
	var arguments = [task_data.operation_type, task_data.app_id, ProjectSettings.globalize_path(current_output_file)]
	# Kein 'pipe' Argument mehr für stdout nötig bei OS.create_process in Godot 4
	var pid = OS.create_process(command, arguments)

	if pid <= 0: # Check auf <= 0 oder == -1 je nach OS Verhalten
		printerr("Failed to start script for ", task_data.app_id)
		_finish_task(current_op_id, -1) # Verwende -1 als Fehlercode
		return

	current_pid = pid
	task_data.pid = pid
	running_tasks[current_op_id] = task_data
	print("Started process PID: ", current_pid, " for OpID: ", current_op_id)


func _process(_delta):
	if not current_task_processing or current_op_id.is_empty():
		return

	# Prozess beendet?
	if not OS.is_process_running(current_pid):
		print("Process finished: ", current_pid)
		# Beende den Task hier, wenn der Prozess nicht mehr läuft
		# Der Exit-Code ist in Godot 4 über OS.execute/create_process nicht direkt abfragbar,
		# das Shell-Skript sollte ihn selbst signalisieren (z.B. durch eine letzte JSON-Zeile oder eine Exit-Code-Datei).
		# Vereinfachung: Wir nehmen Erfolg an, wenn der Task nicht schon als 'failed' markiert ist.
		var final_exit_code = 0 # Annahme: Erfolg
		if running_tasks.has(current_op_id) and running_tasks[current_op_id].status_data.has("status") and running_tasks[current_op_id].status_data.status == "failed":
			final_exit_code = 1 # Annahme: Fehler, wenn letzter Status 'failed' war
		_finish_task(current_op_id, final_exit_code)
		return

	# Neue Ausgabe lesen
	if current_file_access == null:
		if FileAccess.file_exists(current_output_file):
			current_file_access = FileAccess.open(current_output_file, FileAccess.READ)
			if current_file_access == null:
				printerr("Failed to open output file: ", current_output_file, " Error: ", FileAccess.get_open_error())
				_finish_task(current_op_id, -1) # Fehlercode -1
				return
			current_file_access.seek(last_read_pos)
		else:
			return

	while not current_file_access.eof_reached():
		var line = current_file_access.get_line()
		last_read_pos = current_file_access.get_position()

		if line.is_empty(): continue

		# KORRIGIERT: JSON.parse_string() verwenden (Godot 4+)
		var data = JSON.parse_string(line)
		if data != null: # parse_string gibt null bei Fehler zurück
			if data.has("operation_id") and data.operation_id == current_op_id:
				if running_tasks.has(current_op_id):
					running_tasks[current_op_id].status_data = data
					emit_signal("task_updated", current_op_id, data)
				else:
					printerr("Received update for unknown task: ", current_op_id)
			else:
				printerr("Received JSON for wrong/missing operation_id: ", line)
		else:
			printerr("Failed to parse JSON line: ", line)


func _finish_task(op_id: String, exit_code: int, cancelled: bool = false):
	print("Finishing task: ", op_id, " ExitCode: ", exit_code, " Cancelled: ", cancelled)

	if current_file_access:
		current_file_access.close()
		current_file_access = null

	var final_status = "unknown"
	if running_tasks.has(op_id):
		var task = running_tasks[op_id]

		if cancelled:
			final_status = "cancelled"
		# KORRIGIERT: Prüfe auf exit_code == 0 für Erfolg
		elif exit_code == 0:
			if task.status_data.has("status") and task.status_data.status == "failed":
				final_status = "failed"
			else:
				final_status = "completed"
		else: # exit_code != 0
			final_status = "failed"
			if not task.status_data.has("error") or task.status_data.error == null:
				task.status_data.error = "Process exited with code: %d" % exit_code

		task.status_data.status = final_status
		if final_status == "completed" or final_status == "failed":
			task.status_data.progress = 100
		task.status_data.erase("speed")
		task.status_data.erase("eta")

		emit_signal("task_updated", op_id, task.status_data)
		emit_signal("task_finished", op_id, final_status)

		var da := DirAccess.open(OUTPUT_DIR)
		if da and FileAccess.file_exists(task.output_file):
			da.remove(task.output_file.get_file())

	else:
		printerr("Tried to finish unknown task: ", op_id)

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
			if not dir.current_is_dir() and file_name.get_extension() == "log":
				print("Cleaning up old log: ", file_name)
				dir.remove(OUTPUT_DIR.path_join(file_name)) # Korrigiert: remove braucht vollen Pfad
			file_name = dir.get_next()
		# list_dir_end() wird nicht mehr benötigt in Godot 4
	else:
		printerr("Failed to open output directory for cleanup: ", OUTPUT_DIR, " Error: ", DirAccess.get_open_error())
