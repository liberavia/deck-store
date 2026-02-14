extends Node

signal task_added(operation_id, app_id, operation_type)
signal task_updated(operation_id, status_data)
signal task_finished(operation_id, final_status, operation_type)

const FLATPAK_SPAWN_CMD = "/usr/bin/flatpak-spawn"
const OUTPUT_DIR = "user://flatpak_logs"

# Standardpfad für die Flatpak-Executable
const DEFAULT_FLATPAK_EXE_PATH = "/usr/bin/flatpak"

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

	_regex_progress.compile("^(?:Installing|Updating)(?:\\s+([0-9]+)\\/([0-9]+))?\\s+.*?\\s+([0-9]+)%")
	_regex_speed.compile("([0-9.,]+\\s*(?:k|M|G)i?B\\/s)")
	_regex_eta.compile("([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?)$")
	_regex_complete.compile("^(?:Installation|Uninstall|Update) complete\\.?")
	_regex_error.compile("(?:Error:|error:)\\s*(.*)")
	_regex_uninstalling.compile("^Uninstalling")


func queue_install(app_id: String, app_data: Dictionary = {}) -> String:
	return _add_task("install", app_id, app_data)

func queue_update(app_id: String, app_data: Dictionary = {}) -> String:
	return _add_task("update", app_id, app_data)

func queue_uninstall(app_id: String, app_data: Dictionary = {}) -> String:
	print("INFO DownloadManager: Queueing Uninstall for ", app_id)

	# Versuche, den Shortcut aus Steam zu entfernen, wenn die Deinstallation gestartet wird
	if ProjectSettings.has_setting("autoload/SteamIntegration"):
		var steam_integration_node = get_node_or_null("/root/SteamIntegration") # Sicherer Zugriff
		if is_instance_valid(steam_integration_node):
			if steam_integration_node.has_method("remove_from_steam"):
				print("INFO DownloadManager: Triggering SteamIntegration.remove_from_steam for ", app_id)
				var _started = steam_integration_node.remove_from_steam(app_id)
				if not _started: printerr("DownloadManager WARN: Could not start remove_from_steam thread.")
			else: printerr("DownloadManager ERROR: SteamIntegration node missing 'remove_from_steam' method!")
		else: printerr("DownloadManager: SteamIntegration Autoload node not found or invalid.")
	else: printerr("DownloadManager: SteamIntegration Autoload setting not found.")

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
					running_tasks.erase(operation_id) # Entferne auch aus running_tasks, da es nie gestartet wurde
					emit_signal("task_finished", operation_id, "cancelled", op_type)
					print("Cancelled queued task: ", operation_id)
					return
		else:
			printerr("Cannot cancel task ", operation_id, " - not currently running or queued.")
	else:
		printerr("Cannot cancel task ", operation_id, " - not found.")


func get_task_status(app_id: String) -> Dictionary:
	var task_keys = running_tasks.keys()
	for i in range(task_keys.size() - 1, -1, -1): # Rückwärts iterieren ist sicherer, falls Elemente entfernt werden (hier nicht der Fall)
		var op_id = task_keys[i]
		if running_tasks.has(op_id) and running_tasks[op_id].app_id == app_id:
			return running_tasks[op_id].status_data
	return {}


func get_all_tasks() -> Array[Dictionary]:
	var tasks_for_ui: Array[Dictionary] = []
	# Aktuell laufenden Task zuerst hinzufügen, falls vorhanden
	if current_task_processing and running_tasks.has(current_op_id):
		tasks_for_ui.append(running_tasks[current_op_id])
	# Dann die Tasks aus der Warteschlange hinzufügen (ohne den aktuell laufenden, falls er noch in der queue wäre)
	for task_in_queue in task_queue:
		if task_in_queue.operation_id != current_op_id: # Dopplungen vermeiden
			tasks_for_ui.append(task_in_queue)
	return tasks_for_ui

func _add_task(op_type: String, app_id: String, app_data: Dictionary = {}) -> String:
	var timestamp_sec = Time.get_unix_time_from_system()
	var timestamp_usec = Time.get_ticks_usec() # Für höhere Eindeutigkeit
	var random_num = randi() # Zusätzliche Zufälligkeit
	var operation_id = "%s-%s-%s" % [timestamp_sec, timestamp_usec, random_num]
	
	var initial_status_data = {
		"status": "queued", "app_id": app_id, "operation_id": operation_id,
		"progress": 0, "speed": null, "eta": null, "error": null,
		"name": app_data.get("name", app_id), # Name aus app_data oder app_id als Fallback
		"icon_url": app_data.get("icon_url", "") # Icon URL aus app_data
	}
	
	var task_data = {
		"operation_id": operation_id, "app_id": app_id, "operation_type": op_type,
		"pid": -1, "output_file": "", "status_data": initial_status_data,
		"app_data": app_data
	}
	
	task_queue.append(task_data)
	running_tasks[operation_id] = task_data # Task auch in running_tasks mit initialem Status aufnehmen
	
	if op_type != "uninstall": # Für Deinstallationen ggf. kein "task_added" Signal, oder anpassen
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
	# Update status_data for the task in running_tasks
	var new_status_data = task_data.status_data.duplicate(true)
	new_status_data.status = "preparing"
	task_data.status_data = new_status_data
	running_tasks[current_op_id] = task_data # Stelle sicher, dass running_tasks aktualisiert wird
	
	emit_signal("task_updated", current_op_id, task_data.status_data)

	var da := DirAccess.open(OUTPUT_DIR)
	if da and FileAccess.file_exists(current_output_file):
		da.remove(current_output_file.get_file()) # Entferne altes Logfile, falls vorhanden

	var installation = task_data.get("app_data", {}).get("installation", "user")
	var host_command = "flatpak"
	var host_args = [task_data.operation_type, "--" + installation, "--assumeyes", task_data.app_id]
	
	var global_log_path = ProjectSettings.globalize_path(current_output_file)
	
	# Baue den Shell-Befehl sicher zusammen, um Probleme mit Sonderzeichen in Pfaden/Argumenten zu vermeiden
	var host_shell_command = "LC_ALL=C " + host_command # Setze Locale für konsistente Ausgabe
	for arg in host_args:
		host_shell_command += " '%s'" % arg.replace("'", "'\\''") # Quote jedes Argument
	
	# Leite stdout und stderr in dieselbe Logdatei um
	host_shell_command += " > '%s' 2>&1" % global_log_path.replace("'", "'\\''")

	var spawn_args = ["--host", "sh", "-c", host_shell_command]
	
	print("Attempting OS.create_process:")
	print("  Command: ", FLATPAK_SPAWN_CMD)
	print("  Arguments: ", spawn_args)
	
	var pid = OS.create_process(FLATPAK_SPAWN_CMD, spawn_args)
	if pid <= 0: # OS.create_process gibt bei Fehler 0 oder -1 zurück
		printerr("Failed to start flatpak-spawn process for ", task_data.app_id)
		_finish_task(current_op_id, -1, false, "Failed to start flatpak-spawn")
		return
		
	current_pid = pid
	task_data.pid = pid
	running_tasks[current_op_id] = task_data # Stelle sicher, dass PID in running_tasks gespeichert wird
	print("Started flatpak-spawn process PID: ", current_pid, " for OpID: ", current_op_id)


func _process(_delta):
	if not current_task_processing or current_op_id.is_empty():
		return
	if not running_tasks.has(current_op_id): # Task könnte abgebrochen und entfernt worden sein
		# printerr("DownloadManager _process: Current task %s not found in running_tasks." % current_op_id)
		current_task_processing = false # Verhindere Endlosschleife, falls Task extern entfernt wurde
		_check_start_next_task() # Versuche, den nächsten Task zu starten
		return
		
	var task = running_tasks[current_op_id]
	var process_is_running = OS.is_process_running(current_pid)
	
	var read_ok = _read_and_parse_log_update(task)
	if not read_ok: # Fehler beim Lesen des Logs, Task wurde bereits beendet
		return 
		
	if not process_is_running:
		print("Process finished detected in _process (PID %d) AFTER final read attempt, calling finish..." % current_pid)
		var final_exit_code = 0 # Annahme: Erfolg, wenn nicht als 'failed' markiert
		if task.status_data.get("status") == "failed":
			final_exit_code = 1 # Setze Fehlercode, wenn Status 'failed' ist
		_finish_task(current_op_id, final_exit_code)
		return

func _read_and_parse_log_update(task: Dictionary) -> bool:
	if current_file_access == null: # Versuche, die Log-Datei zu öffnen
		if FileAccess.file_exists(task.output_file):
			current_file_access = FileAccess.open(task.output_file, FileAccess.READ)
			if current_file_access == null:
				var err = FileAccess.get_open_error()
				printerr("Failed to open output file: ", task.output_file, " Error: ", err)
				_finish_task(task.operation_id, -1, false, "Failed to open output file: %d" % err)
				return false # Signalisiert, dass der Task beendet wurde
			current_file_access.seek(last_read_pos) # Gehe zur letzten Leseposition
		else:
			# Log-Datei existiert (noch) nicht, warte
			return true # Signalisiert, dass weitergelesen werden kann/soll

	# Überprüfe, ob FileAccess noch gültig ist (könnte durch Fehler ungültig geworden sein)
	if not is_instance_valid(current_file_access) or not current_file_access.is_open():
		# print("DEBUG: Log file access became invalid or closed unexpectedly.")
		current_file_access = null # Zurücksetzen, damit es neu geöffnet werden kann
		return true # Erlaube weiteren Verarbeitungszyklus

	var file_len = current_file_access.get_length()
	if current_file_access.get_position() >= file_len and OS.is_process_running(task.pid):
		# Am Ende der Datei, aber Prozess läuft noch, nichts Neues zu lesen
		return true

	var something_was_updated_in_this_cycle = false
	# Wichtig: .duplicate(true) für tiefe Kopie, um nicht direkt task.status_data zu ändern
	var status_data_in_progress = task.status_data.duplicate(true) 

	while current_file_access.get_position() < file_len:
		var line = current_file_access.get_line().strip_edges()
		var current_read_pos = current_file_access.get_position()

		if line.is_empty():
			last_read_pos = current_read_pos # Aktualisiere Leseposition auch für leere Zeilen
			continue

		# print("DEBUG Log Line: ", line) # Für detailliertes Debugging einkommentieren

		var line_status = null
		var line_progress = -1
		var line_speed = null
		var line_eta = null
		var line_error = null
		var line_matched = false

		# Parsing Logik für "install" und "update"
		if task.operation_type == "install" or task.operation_type == "update":
			var error_match = _regex_error.search(line)
			if error_match:
				line_matched = true
				line_status = "failed"
				line_error = error_match.get_string(1).strip_edges()
				print("DEBUG: Matched Error: ", line_error)
			else:
				var complete_match = _regex_complete.search(line)
				if complete_match:
					line_matched = true
					line_status = "completed"
					line_progress = 100 # Sicherstellen, dass bei Abschluss 100% erreicht wird
					print("DEBUG: Matched completion: ", line)
				else:
					var progress_match = _regex_progress.search(line)
					if progress_match:
						line_matched = true
						var current_pct = progress_match.get_string(3).to_int()
						var current_idx = progress_match.get_string(1).to_int()
						var total_idx = progress_match.get_string(2).to_int()
						
						if total_idx > 0:
							line_progress = int(((current_idx - 1) * 100.0 + current_pct) / total_idx)
						else:
							line_progress = current_pct
							
						line_status = "installing" # Standardstatus bei Fortschritt

						var speed_match = _regex_speed.search(line)
						if speed_match:
							line_speed = speed_match.get_string(1).replace("?", "").strip_edges()
							line_status = "downloading" # Genauerer Status, wenn Geschwindigkeit erkannt wird

						var eta_match = _regex_eta.search(line)
						if eta_match:
							line_eta = eta_match.get_string(1).strip_edges()
						
						# Wenn Download abgeschlossen, aber Installation läuft noch
						if line_progress >= 100 and line_status == "downloading":
							line_status = "installing" 
		
		# Parsing Logik für "uninstall"
		elif task.operation_type == "uninstall":
			var error_match = _regex_error.search(line)
			if error_match:
				line_matched = true
				line_status = "failed"
				line_error = error_match.get_string(1).strip_edges()
				print("DEBUG: Matched Error: ", line_error)
			else:
				var complete_match = _regex_complete.search(line)
				if complete_match and complete_match.get_string(1) == "Uninstall":
					line_matched = true
					line_status = "completed"
					line_progress = 100 # Sicherstellen, dass bei Abschluss 100% erreicht wird
					print("DEBUG: Matched Uninstall complete")
				else:
					if _regex_uninstalling.search(line): # Einfache Prüfung auf "Uninstalling…"
						line_matched = true
						line_status = "removing"
						print("DEBUG: Matched Uninstalling…")
		
		# Wenn ein relevanter Teil der Zeile gematcht wurde
		if line_matched:
			var changed_locally = false
			if line_status != null and status_data_in_progress.get("status") != line_status:
				status_data_in_progress.status = line_status
				changed_locally = true
			if line_progress != -1:
				var current_p = status_data_in_progress.get("progress")
				if current_p == null or line_progress > current_p:
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

			# Speed und ETA nur anzeigen, wenn Status "downloading" ist
			if status_data_in_progress.status != "downloading":
				if status_data_in_progress.get("speed") != null: 
					status_data_in_progress.speed = null
					changed_locally = true
				if status_data_in_progress.get("eta") != null: 
					status_data_in_progress.eta = null
					changed_locally = true
			
			if changed_locally:
				something_was_updated_in_this_cycle = true
				
		last_read_pos = current_read_pos # Aktualisiere die Leseposition

	# Wenn es in diesem Zyklus Aktualisierungen gab und der Task noch existiert
	if something_was_updated_in_this_cycle and running_tasks.has(task.operation_id):
		# Nur aktualisieren und Signal senden, wenn sich tatsächlich etwas geändert hat
		if task.status_data != status_data_in_progress: 
			running_tasks[task.operation_id].status_data = status_data_in_progress 
			print("INFO: Emitting task_updated (changes detected): ", status_data_in_progress)
			emit_signal("task_updated", task.operation_id, status_data_in_progress)

	return true # Signalisiert, dass das Lesen normal verlief

func _finish_task(op_id: String, exit_code: int, cancelled: bool = false, error_msg: String = ""):
	if not running_tasks.has(op_id):
		printerr("DownloadManager _finish_task: Task %s nicht mehr in running_tasks. Wurde möglicherweise bereits beendet." % op_id)
		if op_id == current_op_id: # Wenn es der aktuelle Task war, trotzdem aufräumen
			current_task_processing = false
			current_op_id = ""
			current_pid = -1
			if is_instance_valid(current_file_access) and current_file_access.is_open():
				current_file_access.close()
			current_file_access = null
			_check_start_next_task() # Versuche, den nächsten Task zu starten
		return

	var was_current = (op_id == current_op_id)
	print("Finishing task: ", op_id, " ExitCode: ", exit_code, " Cancelled: ", cancelled, " ErrorMsg: ", error_msg)

	if was_current and is_instance_valid(current_file_access) and current_file_access.is_open():
		current_file_access.close()
		current_file_access = null # Wichtig, damit es für den nächsten Task neu geöffnet wird

	var task = running_tasks[op_id]
	var final_status_data = task.status_data.duplicate(true) # Kopie für finale Änderungen
	var op_type = task.get("operation_type", "unknown")
	var final_status = final_status_data.get("status", "unknown") # Nimm den aktuellen Status als Basis

	if cancelled:
		final_status = "cancelled"
	elif not error_msg.is_empty(): # Wenn eine explizite Fehlermeldung übergeben wurde
		final_status = "failed"
		final_status_data.error = error_msg
	elif exit_code != 0: # Wenn der Prozess mit einem Fehlercode beendet wurde
		final_status = "failed"
		# Behalte existierende Fehlermeldung (z.B. von Regex), sonst generische Meldung
		final_status_data.error = final_status_data.error if final_status_data.error else "Process exited with code: %d" % exit_code
	elif final_status != "failed": # Wenn kein Fehler vorliegt und Status nicht schon "failed" ist
		final_status = "completed" # Setze auf "completed", wenn alles gut ging

	final_status_data.status = final_status
	# Bei Abschluss oder Fehler, setze Fortschritt auf 100% und lösche Speed/ETA
	if final_status == "completed" or final_status == "failed":
		final_status_data.progress = 100
		final_status_data.erase("speed") # Entferne Schlüssel, wenn nicht mehr relevant
		final_status_data.erase("eta")

	running_tasks[op_id].status_data = final_status_data # Aktualisiere den Task in der Hauptliste
	emit_signal("task_updated", op_id, final_status_data) # Sende letztes Update
	emit_signal("task_finished", op_id, final_status, op_type) # Sende finales Signal

	# Steam-Integration nach erfolgreicher Installation
	if final_status == "completed" and op_type == "install":
		var app_id = task.app_id # Dies ist die Flatpak App ID
		var app_name = final_status_data.get("name")
		var icon_url = final_status_data.get("icon_url", "")

		print("DEBUG DownloadManager: Task completed, attempting Steam integration. AppName='%s', AppID (Flatpak)='%s'" % [app_name, app_id])

		var icon_cache_path = _get_cached_icon_path_for_app(app_id, icon_url)
		var global_icon_path_abs = "" # Muss ein absoluter Pfad sein
		if not icon_cache_path.is_empty():
			global_icon_path_abs = ProjectSettings.globalize_path(icon_cache_path)
			if not FileAccess.file_exists(global_icon_path_abs):
				printerr("WARN DownloadManager: Globalized icon path does not exist: ", global_icon_path_abs)
				global_icon_path_abs = "" # Ungültig setzen, wenn nicht gefunden
			else:
				print("INFO DownloadManager: Found cached icon at (absolute): ", global_icon_path_abs)
		else:
			print("WARN DownloadManager: No cached icon found for ", app_id, ". Proceeding without specific icon for Steam.")
			# Optional: Fallback-Icon verwenden oder leer lassen, wenn kein Icon kritisch ist.
			# Für SteamIntegration.add_to_steam ist ein Icon-Pfad jetzt aber erforderlich.
			# Wenn kein Icon vorhanden ist, sollte add_to_steam nicht aufgerufen werden oder einen Fehler werfen.

		# Sicherstellen, dass SteamIntegration vorhanden ist und die Methode existiert
		if ProjectSettings.has_setting("autoload/SteamIntegration"):
			var steam_integration_node = get_node_or_null("/root/SteamIntegration")
			if is_instance_valid(steam_integration_node):
				if op_type == "install": # Nur für Installationen
					if not app_name or app_name == app_id: 
						printerr("DownloadManager ERROR: Cannot add to Steam: App name is missing or same as app_id for ", app_id)
					elif global_icon_path_abs.is_empty(): # Prüfen, ob ein gültiger Icon-Pfad vorhanden ist
						printerr("DownloadManager ERROR: Cannot add to Steam: Icon path is missing for ", app_id)
					elif steam_integration_node.has_method("add_to_steam"):
						# Definiere exe_path und launch_params für Flatpak
						var flatpak_exe = DEFAULT_FLATPAK_EXE_PATH
						var flatpak_params = "run %s" % app_id # z.B. "run com.discordapp.Discord"
						
						print("INFO DownloadManager: Calling SteamIntegration.add_to_steam with:")
						print("  appid_tag: ", app_id)
						print("  name: ", app_name)
						print("  exe_path: ", flatpak_exe)
						print("  launch_params: ", flatpak_params)
						print("  icon_path_abs: ", global_icon_path_abs)
						
						# Aufruf mit allen 5 erforderlichen Argumenten
						steam_integration_node.add_to_steam(app_id, app_name, flatpak_exe, flatpak_params, global_icon_path_abs)
					else:
						printerr("DownloadManager ERROR: SteamIntegration node missing 'add_to_steam' method!")
				# Die remove_from_steam Logik wurde bereits in queue_uninstall verschoben.
			else:
				printerr("DownloadManager ERROR: SteamIntegration Autoload node not found or invalid.")
		else:
			printerr("DownloadManager: SteamIntegration Autoload setting not found!")
			
	# Logdatei entfernen, nachdem sie nicht mehr benötigt wird
	var da := DirAccess.open(OUTPUT_DIR)
	if da and FileAccess.file_exists(task.output_file):
		print("INFO DownloadManager: Removing log file: ", task.output_file)
		da.remove(task.output_file.get_file())

		var main_node = get_node_or_null("/root/App")
		if is_instance_valid(main_node) and main_node.has_method("refresh_installed_apps_list"):
			main_node.refresh_installed_apps_list()
		else:
			printerr("DownloadManager: Could not call refresh_installed_apps_list on Main node.")

	# Aufräumen und nächsten Task starten, falls vorhanden
	if was_current:
		current_op_id = ""
		current_pid = -1
		current_output_file = ""
		last_read_pos = 0
		current_task_processing = false
		running_tasks.erase(op_id) # Entferne den beendeten Task aus running_tasks
		_check_start_next_task()
	else: # Sollte nicht passieren, wenn Logik korrekt ist, aber als Sicherheitsnetz
		running_tasks.erase(op_id)


func _cleanup_old_logs():
	var dir = DirAccess.open(OUTPUT_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and (file_name.begins_with("flatpak_output_") and file_name.ends_with(".log")):
				print("Cleaning up old log: ", file_name)
				var err = dir.remove(OUTPUT_DIR.path_join(file_name)) # Korrekter Pfad für remove
				if err != OK: printerr("Failed to remove old log file: ", file_name, " Error code: ", err)
			file_name = dir.get_next()
		# dir.list_dir_end() # Nicht unbedingt nötig, da DirAccess beim Verlassen des Scopes geschlossen wird
	else:
		printerr("Failed to open output directory for cleanup: ", OUTPUT_DIR, " Error: ", DirAccess.get_open_error())

func _get_cached_icon_path_for_app(app_id: String, icon_url: String) -> String:
	if icon_url.is_empty():
		print("WARN DownloadManager: No icon URL provided for ", app_id)
		return ""

	# Sicherer Zugriff auf Main Node und Cache-Verzeichnis
	var main_node = get_node_or_null("/root/App") # Passe dies an, falls dein Hauptknoten anders heißt
	if not is_instance_valid(main_node):
		printerr("DownloadManager ERROR: Cannot access main node '/root/App' (or it's invalid).")
		return ""

	var image_cache_dir: String = ""
	# Versuche, das Cache-Verzeichnis auf verschiedene Weisen zu bekommen
	if main_node.has_meta("IMAGE_CACHE_DIR"):
		image_cache_dir = main_node.get_meta("IMAGE_CACHE_DIR")
	elif main_node.has_method("get_image_cache_dir"):
		image_cache_dir = main_node.get_image_cache_dir()
	else:
		# Fallback, falls nicht anders definiert (anpassen, falls nötig)
		image_cache_dir = "user://image_cache" 
		printerr("DownloadManager WARN: Cannot determine IMAGE_CACHE_DIR from main node. Using fallback: ", image_cache_dir)
		# Stelle sicher, dass das Fallback-Verzeichnis existiert
		var dir_access = DirAccess.open("user://")
		if dir_access and not dir_access.dir_exists(image_cache_dir.replace("user://", "")):
			dir_access.make_dir_recursive(image_cache_dir)


	var url_hash = icon_url.md5_text()
	var path_png = image_cache_dir.path_join(url_hash + ".png")
	var path_webp = image_cache_dir.path_join(url_hash + ".webp")

	# Prüfe, ob die globalisierten Pfade existieren
	if FileAccess.file_exists(ProjectSettings.globalize_path(path_png)):
		return path_png # Gib den user:// Pfad zurück, Globalisierung erfolgt später
	elif FileAccess.file_exists(ProjectSettings.globalize_path(path_webp)):
		return path_webp # Gib den user:// Pfad zurück
	else:
		print("WARN DownloadManager: Icon for ", app_id, " not found in cache (URL: ", icon_url, ", Searched PNG: ", path_png, ", Searched WEBP: ", path_webp,")")
		return ""
