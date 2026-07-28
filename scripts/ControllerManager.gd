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
		pass

func _detect_type(device_id: int):
	var new_type = ControllerType.XBOX
	var joy_name = Input.get_joy_name(device_id).to_lower()
	
	if Engine.has_singleton("Steam") and get_node_or_null("/root/SteamIntegration") and get_node("/root/SteamIntegration").is_steam_initialized:
		if Steam.has_method("getConnectedControllers") and Steam.has_method("getInputTypeForHandle"):
			var controllers = Steam.getConnectedControllers()
			if controllers.size() > 0:
				var handle = controllers[0]
				if device_id < controllers.size():
					handle = controllers[device_id]
				var steam_type = Steam.getInputTypeForHandle(handle)
				print("ControllerManager: Steam Input Type detected: ", steam_type)
				
				if steam_type in [5, 12, 13]:
					new_type = ControllerType.PS
				elif steam_type in [8, 9, 10]:
					new_type = ControllerType.SWITCH
				elif steam_type > 0:
					new_type = ControllerType.XBOX
				
				if steam_type != 0:
					_set_new_type(new_type)
					return
	
	if "playstation" in joy_name or "dualshock" in joy_name or "dualsense" in joy_name or "ps4" in joy_name or "ps5" in joy_name or "sony" in joy_name:
		new_type = ControllerType.PS
	elif "nintendo" in joy_name or "switch" in joy_name or "joy-con" in joy_name:
		new_type = ControllerType.SWITCH
	else:
		new_type = ControllerType.XBOX
		
	_set_new_type(new_type)

func _set_new_type(new_type: ControllerType):
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
	var fallback_filename = filename
	
	if type_str == "ps":
		match filename:
			"a": filename = "cross"
			"b": filename = "circle"
			"x": filename = "square"
			"y": filename = "triangle"
			"menu": filename = "options"
			"view": filename = "view"
	
	elif type_str == "xbox":
		match filename:
			"l1": filename = "lb"
			"r1": filename = "rb"
			"l2": filename = "lt"
			"r2": filename = "rt"
	
	var path = "res://assets/controller_glyphs/%s/%s.svg" % [type_str, filename]
	if ResourceLoader.exists(path):
		return path
	
	var xbox_filename = fallback_filename
	match fallback_filename:
		"l1": xbox_filename = "lb"
		"r1": xbox_filename = "rb"
		"l2": xbox_filename = "lt"
		"r2": xbox_filename = "rt"
		
	return "res://assets/controller_glyphs/xbox/%s.svg" % xbox_filename
