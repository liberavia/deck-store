extends Node

signal controller_type_changed(type: String)

enum ControllerType { XBOX, PS, SWITCH, KEYBOARD }

var active_type: ControllerType = ControllerType.XBOX
var last_device_id: int = -1

func _input(event: InputEvent):
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var device_id = event.device
		if device_id != last_device_id:
			last_device_id = device_id
			_detect_type(device_id)
	elif event is InputEventKey or event is InputEventMouseButton:
		# Optionally switch to keyboard mode?
		# For now we stick to last controller or default xbox
		pass

func _detect_type(device_id: int):
	var joy_name = Input.get_joy_name(device_id).to_lower()
	var new_type = ControllerType.XBOX
	
	if "playstation" in joy_name or "dualshock" in joy_name or "dualsense" in joy_name or "ps4" in joy_name or "ps5" in joy_name or "sony" in joy_name:
		new_type = ControllerType.PS
	elif "nintendo" in joy_name or "switch" in joy_name or "joy-con" in joy_name:
		new_type = ControllerType.SWITCH
	else:
		new_type = ControllerType.XBOX
		
	if new_type != active_type:
		active_type = new_type
		emit_signal("controller_type_changed", get_type_string())
		print("ControllerManager: Type detected as ", get_type_string())

func get_type_string() -> String:
	match active_type:
		ControllerType.PS: return "ps"
		ControllerType.SWITCH: return "switch"
		_: return "xbox"

func get_glyph_path(action: String) -> String:
	var type_str = get_type_string()
	var filename = action.to_lower()
	
	# Mapping PlayStation specific names
	if type_str == "ps":
		match filename:
			"a": filename = "cross"
			"b": filename = "circle"
			"x": filename = "square"
			"y": filename = "triangle"
	
	# Mapping Xbox specific names (LB/RB/LT/RT)
	elif type_str == "xbox":
		match filename:
			"l1": filename = "lb"
			"r1": filename = "rb"
			"l2": filename = "lt"
			"r2": filename = "rt"
	
	# Mapping Switch specific names if we had them
	# elif type_str == "switch": ...
	
	var path = "res://assets/controller_glyphs/%s/%s.svg" % [type_str, filename]
	if FileAccess.file_exists(path):
		return path
	
	# Fallback to xbox if ps/switch glyph missing
	return "res://assets/controller_glyphs/xbox/%s.svg" % filename
