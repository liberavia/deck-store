# AddToSteamButton.gd
extends Button

@export var app_id: String = ""
@export var app_name: String = ""

var icon_url: String = ""
var _focus_sound_player: AudioStreamPlayer

func _ready():
	# Verbinde pressed Signal
	pressed.connect(_on_pressed)
	# Fokus-Einstellungen und Sound (optional)
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(_on_focus_entered_sound)
	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")


func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()


# Funktion, die von DetailsView aufgerufen wird, um die nötigen Infos zu setzen
func set_app_info(id: String, name: String, url: String):
	app_id = id
	app_name = name
	icon_url = url
	# Tooltip hinzufügen
	tooltip_text = "Add '%s' to your Steam library" % app_name

func _on_pressed():
	if app_id.is_empty() or app_name.is_empty():
		printerr("AddToSteamButton ERROR: app_id or app_name is empty!")
		return

	var icon_cache_path = ""
	var main_node = get_node_or_null("/root/App")

	if icon_url.is_empty():
		printerr("AddToSteamButton ERROR: Icon URL is missing for ", app_id)
		text = "Icon missing!"
		await get_tree().create_timer(1.5).timeout
		text = "Add to Steam"
		return
	elif main_node and main_node.has_method("get_cached_image_path"):
		icon_cache_path = main_node.get_cached_image_path(icon_url)
	else:
		printerr("AddToSteamButton ERROR: Cannot access main node or get_cached_image_path function!")
		return

	if icon_cache_path.is_empty():
		printerr("AddToSteamButton ERROR: Icon for ", app_id, " not found in cache (URL: ", icon_url, "). Cannot add to Steam.")
		text = "Icon missing!"
		await get_tree().create_timer(1.5).timeout
		text = "Add to Steam"
		return 

	var global_icon_path = ProjectSettings.globalize_path(icon_cache_path)

	print("INFO: Add to Steam button pressed for: ", app_id)
	print("INFO: Using Icon Path: ", global_icon_path)
	disabled = true
	text = "Adding..."

	if not ProjectSettings.has_setting("autoload/SteamIntegration"):
		printerr("AddToSteamButton ERROR: SteamIntegration Autoload not found!")
		text = "Error!"; await get_tree().create_timer(1.5).timeout; disabled = false; text = "Add to Steam"
		return

	var success = SteamIntegration.add_to_steam(app_id, app_name, global_icon_path)

	if success:
		print("INFO: Successfully called add_to_steam for ", app_id)
		text = "Add to Steam"
		disabled = false
		visible = false
	else:
		printerr("ERROR: add_to_steam failed for ", app_id)
		text = "Failed!"
		await get_tree().create_timer(1.5).timeout
		disabled = false
		text = "Add to Steam"
