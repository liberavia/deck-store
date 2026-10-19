extends Node

signal controller_type_changed(type: String)
signal input_block_state_changed(blocked: bool)

enum ControllerType { XBOX, PS, SWITCH, KEYBOARD }

var active_type: ControllerType = ControllerType.XBOX
var last_device_id: int = -1

var _has_window_focus: bool = true
var _is_overlay_active: bool = false
var _focus_cooldown_active: bool = false
var _focus_cooldown_timer: Timer = null
var _input_blocker_node: Node = null

func _ready():
	_focus_cooldown_timer = Timer.new()
	_focus_cooldown_timer.one_shot = true
	_focus_cooldown_timer.wait_time = 0.15
	_focus_cooldown_timer.timeout.connect(_on_focus_cooldown_timeout)
	add_child(_focus_cooldown_timer)
	call_deferred("_setup_input_blocker")

func _setup_input_blocker():
	var win = get_window()
	if is_instance_valid(win):
		_has_window_focus = win.has_focus()
		if win.has_signal("focus_entered") and not win.focus_entered.is_connected(_on_window_focus_entered):
			win.focus_entered.connect(_on_window_focus_entered)
		if win.has_signal("focus_exited") and not win.focus_exited.is_connected(_on_window_focus_exited):
			win.focus_exited.connect(_on_window_focus_exited)
	_update_input_block_state()

func _notification(what: int):
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_on_window_focus_exited()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_on_window_focus_entered()

func _on_window_focus_exited():
	if _has_window_focus:
		_has_window_focus = false
		if is_instance_valid(_focus_cooldown_timer):
			_focus_cooldown_timer.stop()
		_focus_cooldown_active = false
		print("ControllerManager: Window lost focus, blocking controller input.")
		_update_input_block_state()

func _on_window_focus_entered():
	if not _has_window_focus:
		_has_window_focus = true
		_focus_cooldown_active = true
		if is_instance_valid(_focus_cooldown_timer):
			_focus_cooldown_timer.start()
		print("ControllerManager: Window regained focus, starting 150ms input cooldown.")
		_update_input_block_state()

func _on_focus_cooldown_timeout():
	_focus_cooldown_active = false
	_update_input_block_state()

func set_overlay_active(active: bool):
	if _is_overlay_active != active:
		_is_overlay_active = active
		if not active:
			_focus_cooldown_active = true
			if is_instance_valid(_focus_cooldown_timer):
				_focus_cooldown_timer.start()
		_update_input_block_state()

func is_input_blocked() -> bool:
	return (not _has_window_focus) or _is_overlay_active or _focus_cooldown_active

func _update_input_block_state():
	var blocked = is_input_blocked()
	var vp = get_viewport()
	if is_instance_valid(vp):
		var app = get_node_or_null("/root/App")
		var is_typing_now = false
		if is_instance_valid(app) and app.has_method("is_any_section_typing"):
			is_typing_now = app.is_any_section_typing()
		vp.gui_disable_input = blocked and not is_typing_now
	emit_signal("input_block_state_changed", blocked)

func _input(event: InputEvent):
	if is_input_blocked():
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			return
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
