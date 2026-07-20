extends SceneTree

func _init():
	print("Adding open_settings input action...")
	
	if not ProjectSettings.has_setting("input/open_settings"):
		var setting = {
			"deadzone": 0.5,
			"events": []
		}
		
		var joy_event = InputEventJoypadButton.new()
		joy_event.button_index = JOY_BUTTON_START
		setting.events.append(joy_event)
		
		var key_event = InputEventKey.new()
		key_event.keycode = KEY_ESCAPE
		setting.events.append(key_event)
		
		ProjectSettings.set_setting("input/open_settings", setting)
		ProjectSettings.save()
		print("Input action open_settings added successfully.")
	else:
		print("Input action already exists.")
	
	quit()
