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
	"install_scope": "user",
	"language": "auto"
}

func _ready():
	var home_dir = OS.get_environment("HOME")
	if home_dir.is_empty():
		home_dir = "/home/deck"
	var base_path = home_dir.path_join(DECKSTORE_BASE_DIR_NAME)
	
	if not DirAccess.dir_exists_absolute(base_path):
		DirAccess.make_dir_absolute(base_path)
		
	_settings_filepath = base_path.path_join(SETTINGS_FILE_NAME)
	load_settings()
	_apply_language()

func _apply_language():
	var lang = settings.get("language", "auto")
	if lang == "auto":
		var steam_lang = ""
		if ProjectSettings.has_setting("autoload/SteamIntegration"):
			var steam_int = get_node_or_null("/root/SteamIntegration")
			if is_instance_valid(steam_int) and steam_int.is_steam_initialized:
				if Engine.has_singleton("Steam") and Steam.has_method("getSteamUILanguage"):
					steam_lang = Steam.getSteamUILanguage()
		
		var mapped_lang = "en"
		match steam_lang:
			"german": mapped_lang = "de"
			"french": mapped_lang = "fr"
			"spanish": mapped_lang = "es"
			"italian": mapped_lang = "it"
			"polish": mapped_lang = "pl"
			"ukrainian": mapped_lang = "uk"
			"english": mapped_lang = "en"
			_:
				var os_lang = OS.get_locale().left(2)
				if os_lang in ["de", "fr", "es", "it", "pl", "uk"]:
					mapped_lang = os_lang
		
		TranslationServer.set_locale(mapped_lang)
	else:
		TranslationServer.set_locale(lang)

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
	if settings.has(key):
		settings[key] = value
		save_settings()
		emit_signal("settings_changed", key, value)
		if key == "language":
			_apply_language()
	else:
		printerr("SettingsManager: Unknown setting key ", key)
