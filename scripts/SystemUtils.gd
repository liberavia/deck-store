extends Node


var _is_flatpak_container: bool = false
var _flatpak_cmd: String = "flatpak"
var _flatpak_args_prefix: PackedStringArray = []

func _ready():
	_is_flatpak_container = FileAccess.file_exists("/.flatpak-info")
	
	if _is_flatpak_container:
		print("SystemUtils: Running inside Flatpak sandbox. Using 'flatpak-spawn --host' wrapper.")
		_flatpak_cmd = "flatpak-spawn"
		_flatpak_args_prefix = ["--host", "flatpak"]
	else:
		print("SystemUtils: Running natively (Steam). Stripping LD_LIBRARY_PATH via env.")
		_flatpak_cmd = "/usr/bin/env"
		_flatpak_args_prefix = ["-u", "LD_LIBRARY_PATH", "-u", "LD_PRELOAD", "-u", "STEAM_RUNTIME", "/usr/bin/flatpak"]
		
	_dump_debug_info()

func _dump_debug_info():
	var home = OS.get_environment("HOME")
	var f = FileAccess.open(home + "/deckstore_debug.txt", FileAccess.WRITE)
	if not f: return
	f.store_string("=== SYSTEM UTILS DEBUG ===\n")
	f.store_string("CMD: " + _flatpak_cmd + "\n")
	f.store_string("ARGS: " + str(_flatpak_args_prefix) + "\n\n")
	
	f.store_string("=== ENV ===\n")
	var env_out = []
	OS.execute("/usr/bin/env", [], env_out, true)
	if env_out.size() > 0:
		f.store_string(env_out[0])
		
	f.store_string("\n=== FLATPAK TEST ===\n")
	var fp_out = []
	var test_args = _flatpak_args_prefix.duplicate()
	test_args.append("--version")
	var exit = OS.execute(_flatpak_cmd, test_args, fp_out, true)
	f.store_string("Exit Code: " + str(exit) + "\n")
	if fp_out.size() > 0:
		f.store_string("Output: " + str(fp_out[0]) + "\n")
		
	f.close()
func execute_flatpak(args: PackedStringArray, read_stderr: bool = false) -> Dictionary:
	var final_args = _flatpak_args_prefix.duplicate()
	final_args.append_array(args)
	
	print("SystemUtils: Executing '", _flatpak_cmd, "' with args: ", final_args)
	var output = []
	var exit_code = OS.execute(_flatpak_cmd, final_args, output, read_stderr)
	var out_str = output[0] if output.size() > 0 else ""
	
	if exit_code != 0:
		printerr("SystemUtils: Command failed with exit code ", exit_code)
		if read_stderr:
			printerr("SystemUtils: Error Output: ", out_str)
	else:
		print("SystemUtils: Command succeeded.")
		
	return {
		"exit_code": exit_code,
		"output": out_str
	}

func get_host_sh_cmd() -> String:
	if _is_flatpak_container:
		return "flatpak-spawn"
	return "/usr/bin/env"

func get_host_sh_args(shell_command: String) -> PackedStringArray:
	if _is_flatpak_container:
		return PackedStringArray(["--host", "sh", "-c", shell_command])
	return PackedStringArray(["-u", "LD_LIBRARY_PATH", "-u", "LD_PRELOAD", "-u", "STEAM_RUNTIME", "sh", "-c", shell_command])

func get_flatpak_host_cmd_prefix() -> String:
	if _is_flatpak_container:
		return "flatpak-spawn --host "
	return "/usr/bin/env -u LD_LIBRARY_PATH -u LD_PRELOAD -u STEAM_RUNTIME "
