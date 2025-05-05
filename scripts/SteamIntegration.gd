# SteamIntegration.gd
extends Node

signal shortcut_action_completed(action, app_id, success)

const HELPER_EXE_RES_PATH = "res://bin/steam_shortcut_manager"
const FLATPAK_SPAWN_CMD = "/usr/bin/flatpak-spawn"
var helper_exe_abs_path: String = ""

var _shortcut_thread: Thread = null

func _ready():
	helper_exe_abs_path = ProjectSettings.globalize_path(HELPER_EXE_RES_PATH)
	if helper_exe_abs_path.is_empty() or not FileAccess.file_exists(helper_exe_abs_path):
		printerr("SteamIntegration ERROR: Helper executable not found at: ", helper_exe_abs_path)
		helper_exe_abs_path = ""

func _execute_shortcut_manager_in_thread(args: Array):
	print("DEBUG SteamIntegration _execute_shortcut_manager_in_thread with args: ", args)
	if helper_exe_abs_path.is_empty():
		printerr("SteamIntegration Thread ERROR: Helper executable path is invalid.")
		call_deferred("_process_shortcut_manager_result", args, -99, PackedStringArray())
		return

	var command_to_run = ""
	var final_args = []

	if FileAccess.file_exists(FLATPAK_SPAWN_CMD):
		command_to_run = FLATPAK_SPAWN_CMD
		final_args = ["--host", helper_exe_abs_path] + args
	else:
		command_to_run = helper_exe_abs_path
		final_args = args

	print("SteamIntegration Thread: Executing: ", command_to_run, " with args: ", final_args)

	var execute_output: PackedStringArray = []
	var exit_code = OS.execute(command_to_run, final_args, execute_output, true)

	print("SteamIntegration Thread: Helper script finished. Exit Code: ", exit_code)

	call_deferred("_process_shortcut_manager_result", args, exit_code, execute_output)


func _process_shortcut_manager_result(args: Array, exit_code: int, output_array: PackedStringArray):
	print("SteamIntegration MainThread: Processing result for args: ", args, ", ExitCode: ", exit_code)
	_shortcut_thread = null

	var action = ""
	var app_id = ""
	var success = false

	var next_is_appid = false
	for i in range(args.size()):
		if args[i] == "--action" and i + 1 < args.size():
			action = args[i+1]
		elif args[i] == "--appid" and i + 1 < args.size():
			app_id = args[i+1]
			break

	if app_id.is_empty():
		printerr("SteamIntegration ERROR: Could not determine app_id from thread result args.")
		return

	match action:
		"add", "remove":
			success = (exit_code == 0)
			if success:
				_notify_steam_restart()
			else:
				printerr("SteamIntegration ERROR: Action '", action, "' failed for ", app_id, " with exit code: ", exit_code)
				if output_array.size() > 0: printerr("Output: ", "\n".join(output_array))
		"check":
			success = (exit_code == 0) 
			if exit_code > 1 :
				printerr("SteamIntegration ERROR: Action 'check' failed for ", app_id, " with unexpected exit code: ", exit_code)
				if output_array.size() > 0: printerr("Output: ", "\n".join(output_array))
		_:
			printerr("SteamIntegration ERROR: Unknown action '", action, "' in result processing.")

	print("SteamIntegration: Emitting shortcut_action_completed: action=", action, ", app_id=", app_id, ", success=", success)
	emit_signal("shortcut_action_completed", action, app_id, success)


func add_to_steam(app_id: String, name: String, icon_path: String) -> bool:
	if _shortcut_thread != null and _shortcut_thread.is_started() and _shortcut_thread.is_alive():
		printerr("SteamIntegration WARN: Another shortcut operation is already running.")
		return false 

	if name.is_empty() or app_id.is_empty():
		printerr("SteamIntegration ERROR: app_id and name are required.")
		return false

	var args = ["--action", "add", "--appid", app_id, "--name", name]
	if not icon_path.is_empty() and FileAccess.file_exists(icon_path):
		args.append("--icon")
		args.append(icon_path)
	elif not icon_path.is_empty():
		print("WARN SteamIntegration: Icon path for add provided but file not found: ", icon_path)

	_shortcut_thread = Thread.new()
	var callable = Callable(self, "_execute_shortcut_manager_in_thread")
	var err = _shortcut_thread.start(callable.bind(args)) 

	if err != OK:
		printerr("SteamIntegration ERROR: Could not start thread for 'add' action! Code: ", err)
		_shortcut_thread = null
		return false 

	print("SteamIntegration: Thread started for 'add' action, OpID (internal): ", _shortcut_thread.get_id())
	return true 


func remove_from_steam(app_id: String) -> bool:
	print("DEBUG Remove shortcut from steam with app_id: ", app_id)
	if _shortcut_thread != null and _shortcut_thread.is_started() and _shortcut_thread.is_alive():
		printerr("SteamIntegration WARN: Another shortcut operation is already running.")
		return false

	if app_id.is_empty(): return false

	var args = ["--action", "remove", "--appid", app_id]
	
	_shortcut_thread = Thread.new()
	var callable = Callable(self, "_execute_shortcut_manager_in_thread")
	var err = _shortcut_thread.start(callable.bind(args))

	if err != OK:
		printerr("SteamIntegration ERROR: Could not start thread for 'remove' action! Code: ", err)
		_shortcut_thread = null
		return false

	print("SteamIntegration: Thread started for 'remove' action, OpID (internal): ", _shortcut_thread.get_id())
	return true


func is_in_steam(app_id: String) -> bool:
	printerr("SteamIntegration DEPRECATED: is_in_steam() cannot return synchronously anymore. Use async check.")
	return false

func check_in_steam_async(app_id: String) -> bool:
	if _shortcut_thread != null and _shortcut_thread.is_started() and _shortcut_thread.is_alive():
		printerr("SteamIntegration WARN: Another shortcut operation is already running.")
		return false

	if app_id.is_empty(): return false
	var args = ["--action", "check", "--appid", app_id]
	_shortcut_thread = Thread.new()
	var callable = Callable(self, "_execute_shortcut_manager_in_thread")
	var err = _shortcut_thread.start(callable.bind(args))
	if err != OK: printerr("SteamIntegration ERROR: Could not start thread for 'check' action! Code: ", err); _shortcut_thread = null; return false
	print("SteamIntegration: Thread started for 'check' action, OpID (internal): ", _shortcut_thread.get_id())
	return true


func _notify_steam_restart():
	print("ACTION NEEDED: Please restart Steam for shortcut changes to take effect.")
	# emit_signal("steam_restart_needed")
	
