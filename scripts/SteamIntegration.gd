extends Node

signal shortcut_action_completed(action: String, appid_tag: String, success: bool)
signal overlay_toggled(active: bool)


var _shortcut_thread: Thread = null

var is_steam_initialized: bool = false

func _ready():
	_initialize_steam()

func _initialize_steam():
	if OS.has_feature("editor"):
		print("SteamIntegration: Running in editor. Skipping Steam initialization to prevent sandbox crashes.")
		return
		
	if Engine.has_singleton("Steam"):
		var INIT: Dictionary = Steam.steamInitEx()
		print("Steamworks Initialized: ", INIT)
		if INIT["status"] == 0:
			is_steam_initialized = true
			if Steam.has_signal("overlay_toggled") and not Steam.overlay_toggled.is_connected(_on_steam_overlay_toggled):
				Steam.overlay_toggled.connect(_on_steam_overlay_toggled)
	else:
		print("GodotSteam singleton not found!")

func _on_steam_overlay_toggled(active: bool, _user_initiated: bool = false, _app_id: int = 0):
	print("SteamIntegration: Steam Overlay toggled: ", active)
	emit_signal("overlay_toggled", active)
	if Engine.has_singleton("ControllerManager") or get_node_or_null("/root/ControllerManager"):
		var cm = get_node_or_null("/root/ControllerManager")
		if cm and cm.has_method("set_overlay_active"):
			cm.set_overlay_active(active)

func open_virtual_keyboard(target_rect: Rect2 = Rect2(), current_text: String = "") -> bool:
	if is_steam_initialized and Engine.has_singleton("Steam") and Steam.has_method("showFloatingGamepadTextInput"):
		var shown = Steam.showFloatingGamepadTextInput(
			Steam.FLOATING_GAMEPAD_TEXT_INPUT_MODE_SINGLE_LINE,
			int(target_rect.position.x),
			int(target_rect.position.y),
			int(target_rect.size.x),
			int(target_rect.size.y)
		)
		if shown:
			return true
	var cmd = SystemUtils.get_host_sh_cmd()
	var args = SystemUtils.get_host_sh_args("steam -ifrunning steam://open/keyboard >/dev/null 2>&1 &")
	OS.create_process(cmd, args)
	DisplayServer.virtual_keyboard_show(current_text)
	return true

func _process(_delta):
	if is_steam_initialized and Engine.has_singleton("Steam"):
		Steam.run_callbacks()

func open_url(url: String):
	if is_steam_initialized and Engine.has_singleton("Steam") and Steam.has_method("activateGameOverlayToWebPage"):
		print("SteamIntegration: Opening URL in Steam Overlay: ", url)
		Steam.activateGameOverlayToWebPage(url)
	else:
		print("SteamIntegration: Steam Overlay not available, using OS.shell_open for: ", url)
		OS.shell_open(url)

func _execute_shortcut_manager_in_thread(args: Array):
	print("DEBUG SteamIntegration _execute_shortcut_manager_in_thread mit args: ", args)
	
	var command_to_run: String = ""
	var final_args: Array = []
	
	if not ExtensionsManager.get_extension_status("steam_shortcut_manager_installer"):
		printerr("SteamIntegration Thread ERROR: Extension 'steam_shortcut_manager_installer' not installed.")
		call_deferred("_process_shortcut_manager_result", args, -99, PackedStringArray()) 
		return

	command_to_run = SystemUtils.get_host_sh_cmd()
	var run_args = ["run", "io.github.liberavia.steamshortcutmanager"] + args
	final_args = []
	if SystemUtils._is_flatpak_container:
		final_args = ["--host", "flatpak"] + run_args
	else:
		command_to_run = "flatpak"
		final_args = run_args

	print("SteamIntegration Thread: Führe aus: '", command_to_run, "' mit Argumenten: ", final_args)

	var execute_output: PackedStringArray = []
	var exit_code = OS.execute(command_to_run, final_args, execute_output, true, false)

	print("SteamIntegration Thread: Helfer-Skript beendet. Exit Code: ", exit_code)
	if exit_code != 0:
		print("SteamIntegration Thread: Ausgabe des Helfer-Skripts (stdout/stderr):")
		for line in execute_output:
			print("  ", line)
	
	call_deferred("_process_shortcut_manager_result", args, exit_code, execute_output)

func _process_shortcut_manager_result(args: Array, exit_code: int, output_array: PackedStringArray):
	print("SteamIntegration MainThread: Verarbeite Ergebnis für args: ", args, ", ExitCode: ", exit_code)
	if _shortcut_thread != null and _shortcut_thread.is_started():
		_shortcut_thread.wait_to_finish()
	_shortcut_thread = null

	var action: String = ""
	var appid_tag_value: String = ""
	var success: bool = false

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

func add_to_steam(appid_tag: String, name: String, exe_path: String, launch_params: String, icon_path_abs: String) -> bool:
	if _shortcut_thread != null:
		if _shortcut_thread.is_alive():
			printerr("SteamIntegration WARN: Eine andere Shortcut-Operation läuft bereits.")
			return false 
		elif _shortcut_thread.is_started():
			_shortcut_thread.wait_to_finish()
		_shortcut_thread = null

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

func remove_from_steam(appid_tag: String) -> bool:
	print("DEBUG SteamIntegration: Entferne Shortcut aus Steam mit appid_tag: ", appid_tag)
	if _shortcut_thread != null:
		if _shortcut_thread.is_alive():
			printerr("SteamIntegration WARN: Eine andere Shortcut-Operation läuft bereits.")
			return false
		elif _shortcut_thread.is_started():
			_shortcut_thread.wait_to_finish()
		_shortcut_thread = null

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

func check_in_steam_async(appid_tag: String) -> bool:
	if _shortcut_thread != null:
		if _shortcut_thread.is_alive():
			printerr("SteamIntegration WARN: Eine andere Shortcut-Operation läuft bereits.")
			return false
		elif _shortcut_thread.is_started():
			_shortcut_thread.wait_to_finish()
		_shortcut_thread = null

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

func _notify_steam_restart():
	print("SteamIntegration HINWEIS: Bitte starte Steam neu, damit Shortcut-Änderungen wirksam werden.")
