# SteamIntegration.gd
extends Node

signal shortcut_action_completed(action: String, appid_tag: String, success: bool)

# Pfad zu flatpak-spawn, falls die Godot-App selbst als Flatpak läuft
const FLATPAK_SPAWN_CMD = "/usr/bin/flatpak-spawn" 

var _shortcut_thread: Thread = null

func _ready():
	pass

# Führt den steam_shortcut_manager in einem separaten Thread aus
func _execute_shortcut_manager_in_thread(args: Array):
	print("DEBUG SteamIntegration _execute_shortcut_manager_in_thread mit args: ", args)
	
	var command_to_run: String = ""
	var final_args: Array = []
	
	# Check if the extension is installed
	if not ExtensionsManager.get_extension_status("steam_shortcut_manager_installer"):
		printerr("SteamIntegration Thread ERROR: Extension 'steam_shortcut_manager_installer' not installed.")
		call_deferred("_process_shortcut_manager_result", args, -99, PackedStringArray()) 
		return

	# Wenn flatpak-spawn existiert (Godot-App läuft wahrscheinlich als Flatpak),
	# verwende es, um das Helfer-Skript außerhalb der Sandbox auszuführen.
	if FileAccess.file_exists(FLATPAK_SPAWN_CMD):
		command_to_run = FLATPAK_SPAWN_CMD
		# flatpak-spawn --host flatpak run <appid> <args>
		final_args = ["--host", "flatpak", "run", "io.github.liberavia.steamshortcutmanager"] + args
	else:
		# Development/Host mode: just run 'flatpak run ...'
		command_to_run = "flatpak"
		final_args = ["run", "io.github.liberavia.steamshortcutmanager"] + args

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
	for i in range(args.size()):
		if args[i] == "--action" and i + 1 < args.size():
			action = args[i+1]
		elif args[i] == "--appid_tag" and i + 1 < args.size(): 
			appid_tag_value = args[i+1]
		if not action.is_empty() and not appid_tag_value.is_empty():
			break

	if appid_tag_value.is_empty():
		printerr("SteamIntegration ERROR: Konnte appid_tag nicht aus den Thread-Argumenten bestimmen.")
		emit_signal("shortcut_action_completed", action, "UNKNOWN_APPID_TAG", false)
		return

	match action:
		"add", "remove":
			success = (exit_code == 0)
			if success:
				print("SteamIntegration: Aktion '", action, "' für appid_tag '", appid_tag_value, "' erfolgreich.")
				_notify_steam_restart() 
			else:
				printerr("SteamIntegration ERROR: Aktion '", action, "' für appid_tag '", appid_tag_value, "' fehlgeschlagen mit Exit-Code: ", exit_code)
				if output_array.size() > 0: printerr("Ausgabe des Helfer-Skripts:\n", "\n".join(output_array))
		"check":
			success = (exit_code == 0) 
			if exit_code > 1 : 
				printerr("SteamIntegration ERROR: Aktion 'check' für appid_tag '", appid_tag_value, "' fehlgeschlagen mit unerwartetem Exit-Code: ", exit_code)
				if output_array.size() > 0: printerr("Ausgabe des Helfer-Skripts:\n", "\n".join(output_array))
				success = false 
		_:
			printerr("SteamIntegration ERROR: Unbekannte Aktion '", action, "' bei Ergebnisverarbeitung.")
			success = false

	print("SteamIntegration: Signal shortcut_action_completed wird gesendet: action=", action, ", appid_tag=", appid_tag_value, ", success=", success)
	emit_signal("shortcut_action_completed", action, appid_tag_value, success)

## Fügt einen Shortcut zu Steam hinzu.
func add_to_steam(appid_tag: String, name: String, exe_path: String, launch_params: String, icon_path_abs: String) -> bool:
	if _shortcut_thread != null and _shortcut_thread.is_started() and _shortcut_thread.is_alive():
		printerr("SteamIntegration WARN: Eine andere Shortcut-Operation läuft bereits.")
		return false 

	if appid_tag.is_empty() or name.is_empty() or exe_path.is_empty() or launch_params.is_empty():
		printerr("SteamIntegration ERROR (add): appid_tag, name, exe_path und launch_params sind erforderlich.")
		return false
	
	if icon_path_abs.is_empty(): 
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
		"--icon", icon_path_abs 
	]

	_shortcut_thread = Thread.new()
	var callable_func = func(): _execute_shortcut_manager_in_thread(args)
	var err = _shortcut_thread.start(callable_func)

	if err != OK:
		printerr("SteamIntegration ERROR: Thread für 'add'-Aktion konnte nicht gestartet werden! Code: ", err)
		_shortcut_thread = null 
		return false 

	print("SteamIntegration: Thread für 'add'-Aktion gestartet.")
	return true 

## Entfernt einen Shortcut aus Steam.
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
		"--appid_tag", appid_tag 
	]
	
	_shortcut_thread = Thread.new()
	var callable_func = func(): _execute_shortcut_manager_in_thread(args)
	var err = _shortcut_thread.start(callable_func)

	if err != OK:
		printerr("SteamIntegration ERROR: Thread für 'remove'-Aktion konnte nicht gestartet werden! Code: ", err)
		_shortcut_thread = null
		return false

	print("SteamIntegration: Thread für 'remove'-Aktion gestartet.")
	return true

## Überprüft asynchron, ob ein Shortcut in Steam existiert.
func check_in_steam_async(appid_tag: String) -> bool:
	if _shortcut_thread != null and _shortcut_thread.is_started() and _shortcut_thread.is_alive():
		printerr("SteamIntegration WARN: Eine andere Shortcut-Operation läuft bereits.")
		return false

	if appid_tag.is_empty():
		printerr("SteamIntegration ERROR (check): appid_tag ist erforderlich.")
		return false
		
	var args = [
		"--action", "check",
		"--appid_tag", appid_tag 
	]
	
	_shortcut_thread = Thread.new()
	var callable_func = func(): _execute_shortcut_manager_in_thread(args)
	var err = _shortcut_thread.start(callable_func)
	
	if err != OK:
		printerr("SteamIntegration ERROR: Thread für 'check'-Aktion konnte nicht gestartet werden! Code: ", err)
		_shortcut_thread = null
		return false
		
	print("SteamIntegration: Thread für 'check'-Aktion gestartet.")
	return true

# Platzhalter für eine Benachrichtigung an den Benutzer
func _notify_steam_restart():
	print("SteamIntegration HINWEIS: Bitte starte Steam neu, damit Shortcut-Änderungen wirksam werden.")
