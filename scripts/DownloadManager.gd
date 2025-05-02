extends Node

# Signale, die von der UI genutzt werden können
signal task_added(operation_id, app_id, operation_type)
signal task_updated(operation_id, status_data) # status_data ist das Dictionary aus JSON/Parsing
signal task_finished(operation_id, final_status, operation_type) # "completed", "failed", "cancelled"

# Pfad zu flatpak-spawn
const FLATPAK_SPAWN_CMD = "/usr/bin/flatpak-spawn"
# Verzeichnis für temporäre Ausgabedateien
const OUTPUT_DIR = "user://flatpak_logs"

# Interne Datenstrukturen
var task_queue: Array[Dictionary] = [] # Queue für wartende Tasks
var running_tasks: Dictionary = {}    # Aktuell laufende/überwachte Tasks nach operation_id
var current_task_processing: bool = false # Flag, ob gerade ein Task aktiv abgearbeitet wird

# Variablen für den _aktuell_ laufenden Prozess
var current_op_id: String = ""
var current_pid: int = -1
var current_output_file: String = ""
var current_file_access: FileAccess = null
var last_read_pos: int = 0

# Regex-Objekte (einmal erstellen)
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

	# ALT: _regex_progress.compile("^Installing\\?\\s+\\?+\\s+([0-9]+)%")
	# NEU: Berücksichtigt optionales " X/Y" nach Installing
	# Erklärung:
	# ^Installing             - Beginnt mit "Installing"
	# (?:\\s[0-9]+\\/[0-9]+)? - Optional (?:...)?: Ein Leerzeichen \s, Zahlen [0-9]+, ein Slash \/, Zahlen [0-9]+
	# \\?                     - Das literale Fragezeichen nach Installing oder Installing X/Y
	# \\s+                    - Ein oder mehrere Leerzeichen
	# \\?+                    - Ein oder mehrere Fragezeichen (Fortschrittsbalken)
	# \\s+                    - Ein oder mehrere Leerzeichen
	# ([0-9]+)%               - Erfasst die Prozentzahl in Gruppe 1
	_regex_progress.compile("^Installing(?:\\s[0-9]+\\/[0-9]+)?\\?\\s+\\?+\\s+([0-9]+)%")	# Gruppe 1: Speed-Wert (Zahl+Einheit, ? optional) - Escaped für GDScript RegEx
	_regex_speed.compile("([0-9.,]+\\??\\s*(?:k|M|G)i?B\\/s)") # Beachte doppeltes \\ für \ in GDScript Strings und \\/ für /
	# Gruppe 1: ETA (HH:MM:SS oder HH:MM am Zeilenende)
	_regex_eta.compile("([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?)$")
	# Gruppe 1: Installation oder Uninstall
	_regex_complete.compile("^(Installation|Uninstall) complete\\.?")
	# Gruppe 1: Fehlermeldung nach Error: oder error:
	_regex_error.compile("(?:Error:|error:)\\s*(.*)")
	# "Uninstalling?" am Zeilenanfang
	_regex_uninstalling.compile("^Uninstalling\\?")


# --- Öffentliche API ---

func queue_install(app_id: String) -> String:
	return _add_task("install", app_id)

func queue_uninstall(app_id: String) -> String:
	return _add_task("uninstall", app_id)

func cancel_operation(operation_id: String):
	if running_tasks.has(operation_id):
		var task = running_tasks[operation_id]
		if task.operation_id == current_op_id and current_pid > 0:
			var err = OS.kill(current_pid)
			if err == OK:
				print("Attempting to cancel process PID: ", current_pid)
			else:
				printerr("Failed to kill process PID: ", current_pid, " Error: ", err)
				_finish_task(operation_id, -1, true) # Force finish as cancelled
		elif task.status_data.status == "queued":
			for i in range(task_queue.size()):
				if task_queue[i].operation_id == operation_id:
					task_queue.remove_at(i)
					running_tasks.erase(operation_id) # Auch aus der Überwachung entfernen
					emit_signal("task_finished", operation_id, "cancelled")
					print("Cancelled queued task: ", operation_id)
					return
		else:
			printerr("Cannot cancel task ", operation_id, " - not currently running or queued.")
	else:
		printerr("Cannot cancel task ", operation_id, " - not found.")


func get_task_status(app_id: String) -> Dictionary:
	# Finde den neuesten Task für diese App ID (laufend oder in Queue)
	# Gehe rückwärts durch die Keys, um evtl. neuere Einträge zuerst zu finden
	var task_keys = running_tasks.keys()
	for i in range(task_keys.size() - 1, -1, -1):
		var op_id = task_keys[i]
		if running_tasks[op_id].app_id == app_id:
			return running_tasks[op_id].status_data
	return {} # Kein Task gefunden


func get_all_tasks() -> Array[Dictionary]:
	# Gibt eine Kopie aller bekannten Tasks zurück (laufende + queued)
	# Vielleicht nur die aus der Queue + den aktuell laufenden? Hängt von der UI ab.
	var tasks_for_ui: Array[Dictionary] = []
	if current_task_processing and running_tasks.has(current_op_id):
		tasks_for_ui.append(running_tasks[current_op_id])
	tasks_for_ui.append_array(task_queue) # Hänge die wartenden an
	return tasks_for_ui


# --- Interne Logik ---

func _add_task(op_type: String, app_id: String) -> String:
	# Erzeuge eine "eindeutige" ID mit Zeit und Zufallszahl
	var timestamp_sec = Time.get_unix_time_from_system()
	var timestamp_usec = Time.get_ticks_usec()
	var random_num = randi()
	var operation_id = "%s-%s-%s" % [timestamp_sec, timestamp_usec, random_num]

	var task_data = {
		"operation_id": operation_id,
		"app_id": app_id,
		"operation_type": op_type,
		"pid": -1,
		"output_file": "",
		# Wichtig: status_data enthält immer app_id und operation_id für die UI
		"status_data": {"status": "queued", "app_id": app_id, "operation_id": operation_id, "progress": null, "speed": null, "eta": null, "error": null}
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
	print("Executing task via flatpak-spawn: ", task_data.operation_id)
	current_op_id = task_data.operation_id
	current_output_file = OUTPUT_DIR.path_join("flatpak_output_%s.log" % current_op_id)
	last_read_pos = 0

	if not FileAccess.file_exists(FLATPAK_SPAWN_CMD):
		printerr("FEHLER: flatpak-spawn nicht gefunden unter: ", FLATPAK_SPAWN_CMD)
		_finish_task(current_op_id, -1, false, "flatpak-spawn not found")
		return

	task_data.output_file = current_output_file
	# Setze initialen Status auf 'preparing' und sende Update
	task_data.status_data = {
		"status": "preparing", "app_id": task_data.app_id, "operation_id": current_op_id,
		"progress": null, "speed": null, "eta": null, "error": null
		}
	running_tasks[current_op_id] = task_data
	emit_signal("task_updated", current_op_id, task_data.status_data)

	var da := DirAccess.open(OUTPUT_DIR)
	if da and FileAccess.file_exists(current_output_file):
		da.remove(current_output_file.get_file())

	var host_command = "flatpak"
	var host_args = [
		task_data.operation_type,
		"--user",
		"--assumeyes",
		task_data.app_id
	]
	var global_log_path = ProjectSettings.globalize_path(current_output_file)

	# Shell-Befehl mit LC_ALL=C und Umleitung bauen
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
	# Nur ausführen, wenn ein Task aktiv ist
	if not current_task_processing or current_op_id.is_empty():
		return

	# Prüfen ob Task noch in Verwaltung ist
	if not running_tasks.has(current_op_id):
		# Wurde möglicherweise bereits durch einen Fehler in _read_and_parse beendet
		# print("DEBUG: _process: Current op_id %s not in running_tasks." % current_op_id)
		current_task_processing = false # Zur Sicherheit zurücksetzen
		return

	var task = running_tasks[current_op_id]
	var process_is_running = OS.is_process_running(current_pid)

	# --- NEUE LOGIK ---
	# 1. IMMER versuchen, neue Log-Einträge zu lesen und zu parsen
	var read_ok = _read_and_parse_log_update(task)
	# Wenn beim Lesen ein kritischer Fehler auftrat (z.B. Datei nicht mehr lesbar),
	# wurde _finish_task bereits aufgerufen und read_ok ist false.
	if not read_ok:
		return # _finish_task hat schon aufgeräumt

	# 2. ERST JETZT prüfen, ob der Prozess (noch) läuft.
	if not process_is_running:
		# Prozess ist beendet. Wir haben gerade eben noch versucht zu lesen (_read_ok war true).
		# Jetzt können wir den Task sicher beenden.
		print("Process finished detected in _process (PID %d) AFTER final read attempt, calling finish..." % current_pid)
		# Exit Code 0 als Annahme, _finish_task prüft ggf. letzten bekannten Status
		var final_exit_code = 0
		if task.status_data.get("status") == "failed":
			final_exit_code = 1
		_finish_task(current_op_id, final_exit_code)
		# Wichtig: Schleife hier beenden, da Task fertig ist
		return
	# --- ENDE NEUE LOGIK ---

	# Wenn wir hier ankommen, läuft der Prozess noch und das Lesen war ok.
	# Nichts weiter zu tun in diesem Frame.

func _read_and_parse_log_update(task: Dictionary) -> bool:
	# Gibt true zurück, wenn Lesen/Parsen ok war (auch wenn nichts Neues da war),
	# gibt false zurück bei kritischem Fehler (z.B. Datei nicht lesbar).

	# print("DEBUG: _read_and_parse_log_update called for ", task.operation_id) # Weniger Output

	if current_file_access == null:
		if FileAccess.file_exists(task.output_file):
			# print("DEBUG: Opening log file: ", task.output_file) # Weniger Output
			current_file_access = FileAccess.open(task.output_file, FileAccess.READ)
			if current_file_access == null:
				var err = FileAccess.get_open_error()
				printerr("Failed to open output file in _read_and_parse: ", task.output_file, " Error: ", err)
				_finish_task(task.operation_id, -1, false, "Failed to open output file: %d" % err)
				return false # Kritischer Fehler
			# print("DEBUG: File opened. Seeking to: ", last_read_pos) # Weniger Output
			current_file_access.seek(last_read_pos)
		else:
			return true # Warten, bis Datei existiert

	if not is_instance_valid(current_file_access) or not current_file_access.is_open():
		# print("DEBUG: FileAccess is no longer valid or open.") # Weniger Output
		current_file_access = null
		return true

	var file_len = current_file_access.get_length()
	# print("DEBUG: Current Position: ", last_read_pos, " File Length: ", file_len) # Weniger Output

	# --- Geänderte Leseschleife ---
	# Lese, solange die aktuelle Position kleiner als die Dateilänge ist
	var updated = false
	var read_something_this_cycle = false
	# Kopiere aktuellen Status, um Änderungen zu erkennen und nur einmal zu senden
	var current_status_data = task.status_data.duplicate(true)

	while current_file_access.get_position() < file_len:
		read_something_this_cycle = true
		var line = current_file_access.get_line().strip_edges()
		var current_read_pos = current_file_access.get_position() # Position NACH dem Lesen merken
		print("DEBUG: Read line: [", line, "] - New Position: ", current_read_pos, " / ", file_len) # DEBUG

		if line.is_empty():
			last_read_pos = current_read_pos # Wichtig: Position auch bei leeren Zeilen aktualisieren
			continue

		# Reset Variablen für diese Zeile
		var line_progress = -1; var line_speed = null; var line_eta = null;
		var line_status = null; var line_error = null; var matched_this_line = false

		# --- Parsing Logik (wie zuvor) ---
		if task.operation_type == "install":
			var progress_match = _regex_progress.search(line)
			if progress_match:
				matched_this_line = true; line_progress = progress_match.get_string(1).to_int(); line_status = "installing"
				var speed_match = _regex_speed.search(line); if speed_match: line_speed = speed_match.get_string(1).replace("?", ""); line_status = "downloading"
				var eta_match = _regex_eta.search(line); if eta_match: line_eta = eta_match.get_string(1)
				if line_progress == 100 and line_status == "downloading": line_status = "installing"
				# print("DEBUG: Matched Install Progress: P=%s, S=%s, E=%s" % [line_progress, line_speed, line_eta])

			var complete_match = _regex_complete.search(line); if complete_match and complete_match.get_string(1) == "Installation": matched_this_line = true; line_status = "completed"; line_progress = 100; print("DEBUG: Matched Installation complete")
			var error_match = _regex_error.search(line); if error_match: matched_this_line = true; line_status = "failed"; line_error = error_match.get_string(1); print("DEBUG: Matched Error: ", line_error)

		elif task.operation_type == "uninstall":
			if _regex_uninstalling.search(line): matched_this_line = true; line_status = "removing"; print("DEBUG: Matched Uninstalling?")
			var complete_match = _regex_complete.search(line); if complete_match and complete_match.get_string(1) == "Uninstall": matched_this_line = true; line_status = "completed"; line_progress = 100; print("DEBUG: Matched Uninstall complete")
			var error_match = _regex_error.search(line); if error_match: matched_this_line = true; line_status = "failed"; line_error = error_match.get_string(1); print("DEBUG: Matched Error: ", line_error)
		# --- Ende Parsing Logik ---

		# Aktualisiere das Dictionary, wenn die Zeile relevant war und sich was geändert hat
		if matched_this_line:
			var changed = false
			if line_status != null and current_status_data.status != line_status: current_status_data.status = line_status; changed = true
			if line_progress != -1 and current_status_data.progress != line_progress: current_status_data.progress = line_progress; changed = true
			if line_speed != null and current_status_data.speed != line_speed: current_status_data.speed = line_speed; changed = true
			if line_eta != null and current_status_data.eta != line_eta: current_status_data.eta = line_eta; changed = true
			if line_error != null and current_status_data.error != line_error: current_status_data.error = line_error; changed = true

			if changed: updated = true # Markieren, dass *irgendein* Update stattfand

			# Speed/ETA entfernen, wenn nicht mehr downloading/relevant?
			if current_status_data.status != "downloading":
				if current_status_data.speed != null: current_status_data.speed = null; updated = true # Geändert -> Update senden
				if current_status_data.eta != null: current_status_data.eta = null; updated = true # Geändert -> Update senden


		# Position für nächsten Lesedurchlauf merken (wird jetzt hier gesetzt)
		last_read_pos = current_read_pos

	# Wenn in dieser Runde der Verarbeitung etwas relevantes gelesen UND geändert wurde, sende das Signal
	if updated and running_tasks.has(task.operation_id):
		# Nur senden, wenn sich der Status tatsächlich vom gespeicherten unterscheidet
		if task.status_data != current_status_data:
			running_tasks[task.operation_id].status_data = current_status_data # Update im Haupt-Dictionary
			print("INFO: Emitting task_updated: ", current_status_data) # DEBUG
			emit_signal("task_updated", task.operation_id, current_status_data)
		#else: # DEBUG
			#print("DEBUG: Status dictionary unchanged, not emitting signal.") # DEBUG

	# Prüfe EOF nochmal explizit nach der Schleife
	# print("DEBUG: Finished reading cycle. EOF reached: ", current_file_access.eof_reached())

	return true # Leseversuch war okay

func _finish_task(op_id: String, exit_code: int, cancelled: bool = false, error_msg: String = ""):
	# Verhindert doppeltes Beenden
	if op_id != current_op_id and not running_tasks.has(op_id):
		# Wenn Task schon beendet wurde oder unbekannt ist, nichts tun
		if not running_tasks.has(op_id):
			printerr("Tried to finish unknown or already finished task: ", op_id)
		return

	# Stelle sicher, dass current_op_id auf den zu beendenden Task zeigt, falls nötig
	var was_current = false
	if op_id == current_op_id:
		was_current = true
	elif running_tasks.has(op_id): # Beende einen Task, der nicht mehr aktiv lief (z.B. Cancelled Queued)
		pass
	else:
		printerr("Cannot finish unknown task: ", op_id)
		return

	print("Finishing task: ", op_id, " ExitCode: ", exit_code, " Cancelled: ", cancelled, " ErrorMsg: ", error_msg)

	# Schließe die Datei, falls noch offen
	if was_current and current_file_access:
		current_file_access.close()
		current_file_access = null

	var final_status = "unknown"
	var task = running_tasks[op_id] # Hole den Task direkt
	var last_known_status = task.status_data.get("status", "unknown")
	var op_type = task.get("operation_type", "unknown") # Hole den Typ aus dem Task-Dictionary

	if cancelled:
		final_status = "cancelled"
	elif not error_msg.is_empty(): # Wenn eine spezifische Fehlermeldung übergeben wurde
		final_status = "failed"
		task.status_data.error = error_msg
	elif exit_code == 0:
		# Prozess war erfolgreich, aber war der letzte Status 'failed'?
		if last_known_status == "failed":
			final_status = "failed" # Behalte 'failed' bei
		else:
			final_status = "completed"
	else: # exit_code != 0
		final_status = "failed"
		if not task.status_data.has("error") or task.status_data.error == null:
			task.status_data.error = "Process exited with code: %d" % exit_code

	# Letztes Statusupdate vorbereiten und senden
	task.status_data.status = final_status
	if final_status == "completed" or final_status == "failed":
		task.status_data.progress = 100 # Setze 100% bei Ende
	# Speed/ETA sicherheitshalber entfernen
	task.status_data.erase("speed")
	task.status_data.erase("eta")

	# Stelle sicher, dass das finale Dictionary immer noch im Haupt-Dictionary ist
	if running_tasks.has(op_id):
		running_tasks[op_id].status_data = task.status_data
		emit_signal("task_updated", op_id, task.status_data) # Letztes Update
		emit_signal("task_finished", op_id, final_status, op_type)
	else:
		# Task wurde vielleicht schon entfernt (z.B. cancelled queue), sende nur finished
		emit_signal("task_finished", op_id, final_status, op_type)


	# Log-Datei löschen (Jetzt wieder aktivieren?)
	# Du kannst das Auskommentieren entfernen, wenn alles funktioniert.
	#var da := DirAccess.open(OUTPUT_DIR)
	#if da and FileAccess.file_exists(task.output_file):
	#	print("Removing log file: ", task.output_file)
	#	da.remove(task.output_file.get_file())

	# Reset nur, wenn der *aktuelle* Task beendet wurde
	if was_current:
		current_op_id = ""
		current_pid = -1
		current_output_file = ""
		last_read_pos = 0
		current_task_processing = false
		# Nächsten Task starten, falls vorhanden
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
				if err != OK:
					printerr("Failed to remove old log file: ", file_name, " Error code: ", err)
			file_name = dir.get_next()
	else:
		printerr("Failed to open output directory for cleanup: ", OUTPUT_DIR, " Error: ", DirAccess.get_open_error())
