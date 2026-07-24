extends Node

signal settings_changed

const SETTINGS_FILE_NAME = "settings.json"
const DECKSTORE_BASE_DIR_NAME = ".deck-store"

var _settings_filepath: String = ""

var settings = {
	"play_ui_sounds": true,
	"auto_refresh_installed": true,
	"auto_add_to_steam": true,
	"show_steam_restart_warning": true,
	"install_scope": "user"
}

func _ready():
	var home_dir = OS.get_environment("HOME")
	if home_dir.is_empty():
		home_dir = "/home/deck" # Fallback
	var base_path = home_dir.path_join(DECKSTORE_BASE_DIR_NAME)
	
	if not DirAccess.dir_exists_absolute(base_path):
		DirAccess.make_dir_absolute(base_path)
		
	_settings_filepath = base_path.path_join(SETTINGS_FILE_NAME)
	load_settings()

func load_settings():
	if FileAccess.file_exists(_settings_filepath):
		var file = FileAccess.open(_settings_filepath, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			var json = JSON.new()
			var error = json.parse(content)
			if error == OK:
				var loaded_data = json.data
				if typeof(loaded_data) == TYPE_DICTIONARY:
					# Merge loaded settings into default settings
					for key in loaded_data:
						if settings.has(key):
							settings[key] = loaded_data[key]
					print("SettingsManager: Loaded settings from ", _settings_filepath)
			else:
				printerr("SettingsManager: Failed to parse settings.json")
	else:
		print("SettingsManager: No settings file found, using defaults.")
		save_settings()

func save_settings():
	var file = FileAccess.open(_settings_filepath, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(settings, "\t")
		file.store_string(json_string)
		print("SettingsManager: Saved settings to ", _settings_filepath)
	else:
		printerr("SettingsManager: Failed to open settings.json for writing")

func get_setting(key: String, default_value = null):
	if settings.has(key):
		return settings[key]
	return default_value

func set_setting(key: String, value):
	if settings.has(key) and settings[key] == value:
		return # No change
		
	settings[key] = value
	save_settings()
	emit_signal("settings_changed", key, value)
