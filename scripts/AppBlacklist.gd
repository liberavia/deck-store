extends Node

var blacklisted_apps: Array = []

func _ready():
	load_blacklist()

func load_blacklist():
	var file_path = "res://blacklist.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var content = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(content)
		if error == OK:
			var data = json.get_data()
			if typeof(data) == TYPE_DICTIONARY and data.has("blacklisted_apps"):
				var apps = data["blacklisted_apps"]
				if typeof(apps) == TYPE_ARRAY:
					blacklisted_apps = apps
					print("AppBlacklist loaded: ", blacklisted_apps.size(), " apps.")
		file.close()
	else:
		print("AppBlacklist: No blacklist.json found. Creating default.")
		_create_default_blacklist()

func _create_default_blacklist():
	var default_data = {
		"blacklisted_apps": [
			"com.valvesoftware.Steam"
		]
	}
	var file = FileAccess.open("res://blacklist.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(default_data, "\t"))
		file.close()
		blacklisted_apps = default_data["blacklisted_apps"]
		print("AppBlacklist: Created default blacklist.json")

func is_blacklisted(app_id: String) -> bool:
	return app_id in blacklisted_apps
