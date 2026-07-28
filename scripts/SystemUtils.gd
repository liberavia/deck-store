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
		print("SystemUtils: Running natively. Using direct 'flatpak' command.")
		_flatpak_cmd = "flatpak"
		_flatpak_args_prefix = []

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
	return "sh"

func get_host_sh_args(shell_command: String) -> PackedStringArray:
	if _is_flatpak_container:
		return PackedStringArray(["--host", "sh", "-c", shell_command])
	return PackedStringArray(["-c", shell_command])

func get_flatpak_host_cmd_prefix() -> String:
	if _is_flatpak_container:
		return "flatpak-spawn --host "
	return ""
