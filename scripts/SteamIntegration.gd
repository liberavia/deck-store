# SteamIntegration.gd
extends Node

signal shortcut_action_completed(action: String, appid_tag: String, success: bool)

# Pfad zum Helfer-Skript im exportierten Spiel (relativ zur Projekt-Exe)
const HELPER_EXE_RES_PATH = "res://bin/steam_shortcut_manager"
# Pfad zu flatpak-spawn, falls die Godot-App selbst als Flatpak läuft
const FLATPAK_SPAWN_CMD = "/usr/bin/flatpak-spawn" 
var helper_exe_abs_path: String = ""

var _shortcut_thread: Thread = null

func _ready():
	# Konvertiere den res:// Pfad in einen absoluten Pfad beim Start
	helper_exe_abs_path = ProjectSettings.globalize_path(HELPER_EXE_RES_PATH)
	if helper_exe_abs_path.is_empty() or not FileAccess.file_exists(helper_exe_abs_path):
		printerr("SteamIntegration ERROR: Helfer-Executable nicht gefunden unter: ", HELPER_EXE_RES_PATH, " (Globalisiert: ", helper_exe_abs_path, ")")
		helper_exe_abs_path = "" # Ungültig setzen, um Fehler zu vermeiden

# Führt den steam_shortcut_manager in einem separaten Thread aus
func _execute_shortcut_manager_in_thread(args: Array):
	print("DEBUG SteamIntegration _execute_shortcut_manager_in_thread mit args: ", args)
	if helper_exe_abs_path.is_empty():
		printerr("SteamIntegration Thread ERROR: Pfad zur Helfer-Executable ist ungültig.")
		# Rufe Ergebnisverarbeitung mit Fehlercode auf
		call_deferred("_process_shortcut_manager_result", args, -99, PackedStringArray()) 
		return

	var command_to_run: String = ""
	var final_args: Array = []

	# Wenn flatpak-spawn existiert (Godot-App läuft wahrscheinlich als Flatpak),
	# verwende es, um das Helfer-Skript außerhalb der Sandbox auszuführen.
	if FileAccess.file_exists(FLATPAK_SPAWN_CMD):
		command_to_run = FLATPAK_SPAWN_CMD
		# Argumente für flatpak-spawn: --host <host_command> [host_args...]
		final_args = ["--host", helper_exe_abs_path] + args 
	else:
		command_to_run = helper_exe_abs_path
		final_args = args

	print("SteamIntegration Thread: Führe aus: '", command_to_run, "' mit Argumenten: ", final_args)

	var execute_output: PackedStringArray = [] # Array zum Sammeln der stdout-Ausgaben
	# Führe den Befehl blockierend im Thread aus
	var exit_code = OS.execute(command_to_run, final_args, execute_output, true, true) # true für blocking, true für read_stderr

	print("SteamIntegration Thread: Helfer-Skript beendet. Exit Code: ", exit_code)
	if exit_code != 0:
		print("SteamIntegration Thread: Ausgabe des Helfer-Skripts (stdout/stderr):")
		for line in execute_output:
			print("  ", line)
	
	# Ergebnis im Hauptthread verarbeiten
	call_deferred("_process_shortcut_manager_result", args, exit_code, execute_output)

# Verarbeitet das Ergebnis des Thread-Aufrufs im Hauptthread
func _process_shortcut_manager_result(args: Array, exit_code: int, output_array: PackedStringArray):
	print("SteamIntegration MainThread: Verarbeite Ergebnis für args: ", args, ", ExitCode: ", exit_code)
	_shortcut_thread = null # Thread als beendet markieren

	var action: String = ""
	var appid_tag_value: String = "" # Wird den Wert von --appid_tag speichern
	var success: bool = false

	# Extrahiere Aktion und appid_tag aus den ursprünglichen Argumenten
	# Dies ist etwas fehleranfällig, wenn die Argumentstruktur stark variiert,
	# aber für unsere definierten Aufrufe sollte es funktionieren.
	for i in range(args.size()):
		if args[i] == "--action" and i + 1 < args.size():
			action = args[i+1]
		elif args[i] == "--appid_tag" and i + 1 < args.size(): # Geändert von --appid
			appid_tag_value = args[i+1]
			# Wir können hier breaken, wenn wir annehmen, dass appid_tag immer nach action kommt
			# oder wenn wir beide haben. Sicherer ist es, durchzulaufen, falls die Reihenfolge nicht garantiert ist.
			# Für unsere Zwecke sollte es reichen, wenn beide einmal gefunden wurden.
		if not action.is_empty() and not appid_tag_value.is_empty():
			break

	if appid_tag_value.is_empty():
		printerr("SteamIntegration ERROR: Konnte appid_tag nicht aus den Thread-Argumenten bestimmen.")
		# Optional: Versuche, aus dem Output zu parsen, falls das Skript es ausgibt
		emit_signal("shortcut_action_completed", action, "UNKNOWN_APPID_TAG", false)
		return

	match action:
		"add", "remove":
			success = (exit_code == 0)
			if success:
				print("SteamIntegration: Aktion '", action, "' für appid_tag '", appid_tag_value, "' erfolgreich.")
				_notify_steam_restart() # Benachrichtige über notwendigen Steam-Neustart
			else:
				printerr("SteamIntegration ERROR: Aktion '", action, "' für appid_tag '", appid_tag_value, "' fehlgeschlagen mit Exit-Code: ", exit_code)
				if output_array.size() > 0: printerr("Ausgabe des Helfer-Skripts:\n", "\n".join(output_array))
		"check":
			# Exit-Code 0 bedeutet "gefunden", Exit-Code 1 bedeutet "nicht gefunden" (gemäß Python-Skript)
			success = (exit_code == 0) 
			if exit_code > 1 : # Jeder andere Exit-Code > 1 ist ein Fehler
				printerr("SteamIntegration ERROR: Aktion 'check' für appid_tag '", appid_tag_value, "' fehlgeschlagen mit unerwartetem Exit-Code: ", exit_code)
				if output_array.size() > 0: printerr("Ausgabe des Helfer-Skripts:\n", "\n".join(output_array))
				success = false # Explizit auf false setzen bei unerwartetem Fehler
		_:
			printerr("SteamIntegration ERROR: Unbekannte Aktion '", action, "' bei Ergebnisverarbeitung.")
			success = false

	print("SteamIntegration: Signal shortcut_action_completed wird gesendet: action=", action, ", appid_tag=", appid_tag_value, ", success=", success)
	emit_signal("shortcut_action_completed", action, appid_tag_value, success)

## Fügt einen Shortcut zu Steam hinzu.
## appid_tag: Eindeutige ID der Anwendung (z.B. Flatpak App ID).
## name: Anzeigename in Steam.
## exe_path: Pfad zur auszuführenden Datei (z.B. "/usr/bin/flatpak").
## launch_params: Startparameter für die exe (z.B. "run com.beispiel.App").
## icon_path_abs: Absoluter Pfad zur Icon-Datei für das Artwork.
func add_to_steam(appid_tag: String, name: String, exe_path: String, launch_params: String, icon_path_abs: String) -> bool:
	if _shortcut_thread != null and _shortcut_thread.is_started() and _shortcut_thread.is_alive():
		printerr("SteamIntegration WARN: Eine andere Shortcut-Operation läuft bereits.")
		return false 

	if appid_tag.is_empty() or name.is_empty() or exe_path.is_empty() or launch_params.is_empty():
		printerr("SteamIntegration ERROR (add): appid_tag, name, exe_path und launch_params sind erforderlich.")
		return false
	
	if icon_path_abs.is_empty(): # Icon ist jetzt auch erforderlich laut Python-Skript für 'add'
		printerr("SteamIntegration ERROR (add): icon_path_abs ist erforderlich.")
		return false
	if not FileAccess.file_exists(icon_path_abs):
		printerr("SteamIntegration ERROR (add): Icon-Datei nicht gefunden unter: ", icon_path_abs)
		return false

	var args = [
		"--action", "add",
		"--appid_tag", appid_tag,
		"--name", name,
		"--exe", exe_path,
		"--params", launch_params,
		"--icon", icon_path_abs # Muss ein absoluter Pfad sein
	]

	_shortcut_thread = Thread.new()
	# Verwende eine Lambda-Funktion (oder bind), um Argumente an die Thread-Funktion zu übergeben
	var callable_func = func(): _execute_shortcut_manager_in_thread(args)
	var err = _shortcut_thread.start(callable_func)

	if err != OK:
		printerr("SteamIntegration ERROR: Thread für 'add'-Aktion konnte nicht gestartet werden! Code: ", err)
		_shortcut_thread = null # Zurücksetzen, damit neue Operationen möglich sind
		return false 

	print("SteamIntegration: Thread für 'add'-Aktion gestartet. OpID (intern): ", _shortcut_thread.get_id())
	return true 

## Entfernt einen Shortcut aus Steam.
## appid_tag: Eindeutige ID der Anwendung (z.B. Flatpak App ID).
func remove_from_steam(appid_tag: String) -> bool:
	print("DEBUG SteamIntegration: Entferne Shortcut aus Steam mit appid_tag: ", appid_tag)
	if _shortcut_thread != null and _shortcut_thread.is_started() and _shortcut_thread.is_alive():
		printerr("SteamIntegration WARN: Eine andere Shortcut-Operation läuft bereits.")
		return false

	if appid_tag.is_empty():
		printerr("SteamIntegration ERROR (remove): appid_tag ist erforderlich.")
		return false

	var args = [
		"--action", "remove",
		"--appid_tag", appid_tag # Geändert von --appid
	]
	
	_shortcut_thread = Thread.new()
	var callable_func = func(): _execute_shortcut_manager_in_thread(args)
	var err = _shortcut_thread.start(callable_func)

	if err != OK:
		printerr("SteamIntegration ERROR: Thread für 'remove'-Aktion konnte nicht gestartet werden! Code: ", err)
		_shortcut_thread = null
		return false

	print("SteamIntegration: Thread für 'remove'-Aktion gestartet. OpID (intern): ", _shortcut_thread.get_id())
	return true

## Überprüft asynchron, ob ein Shortcut in Steam existiert.
## Das Ergebnis wird über das Signal 'shortcut_action_completed' mit action="check" zurückgegeben.
## appid_tag: Eindeutige ID der Anwendung (z.B. Flatpak App ID).
func check_in_steam_async(appid_tag: String) -> bool:
	if _shortcut_thread != null and _shortcut_thread.is_started() and _shortcut_thread.is_alive():
		printerr("SteamIntegration WARN: Eine andere Shortcut-Operation läuft bereits.")
		return false

	if appid_tag.is_empty():
		printerr("SteamIntegration ERROR (check): appid_tag ist erforderlich.")
		return false
		
	var args = [
		"--action", "check",
		"--appid_tag", appid_tag # Geändert von --appid
	]
	
	_shortcut_thread = Thread.new()
	var callable_func = func(): _execute_shortcut_manager_in_thread(args)
	var err = _shortcut_thread.start(callable_func)
	
	if err != OK:
		printerr("SteamIntegration ERROR: Thread für 'check'-Aktion konnte nicht gestartet werden! Code: ", err)
		_shortcut_thread = null
		return false
		
	print("SteamIntegration: Thread für 'check'-Aktion gestartet. OpID (intern): ", _shortcut_thread.get_id())
	return true

# Platzhalter für eine Benachrichtigung an den Benutzer
func _notify_steam_restart():
	print("SteamIntegration HINWEIS: Bitte starte Steam neu, damit Shortcut-Änderungen wirksam werden.")
	# Hier könntest du ein globales Signal senden, das die UI aktualisiert
	# oder eine Benachrichtigung anzeigt.
	# z.B. emit_signal("steam_restart_notification_requested")
