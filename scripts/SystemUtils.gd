extends Node

## Helper Singleton to abstract system commands across environments (Flatpak vs Native)

var _is_flatpak_container: bool = false
var _flatpak_cmd: String = "flatpak"
var _flatpak_args_prefix: PackedStringArray = []

func _ready():
	# Check if we are running inside a Flatpak sandbox
	_is_flatpak_container = FileAccess.file_exists("/.flatpak-info")
	
	if _is_flatpak_container:
		print("SystemUtils: Running inside Flatpak sandbox. Using 'flatpak-spawn --host' wrapper.")
		_flatpak_cmd = "flatpak-spawn"
		_flatpak_args_prefix = ["--host", "flatpak"]
	else:
		print("SystemUtils: Running natively. Using direct 'flatpak' command.")
		_flatpak_cmd = "flatpak"
		_flatpak_args_prefix = []

## Executes a flatpak command properly wrapped based on the environment.
## Returns an array containing the OS.execute output: [output_array, exit_code]
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

## Returns the command string to run a host shell (either flatpak-spawn or sh)
func get_host_sh_cmd() -> String:
	if _is_flatpak_container:
		return "flatpak-spawn"
	return "sh"

## Returns the array of arguments to execute the given shell command
func get_host_sh_args(shell_command: String) -> PackedStringArray:
	if _is_flatpak_container:
		return PackedStringArray(["--host", "sh", "-c", shell_command])
	return PackedStringArray(["-c", shell_command])

## Helper to build the exact command prefix string (e.g. for bash -c scripts)
func get_flatpak_host_cmd_prefix() -> String:
	if _is_flatpak_container:
		return "flatpak-spawn --host "
	return ""
