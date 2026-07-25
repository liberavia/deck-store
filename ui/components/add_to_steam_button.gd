# AddToSteamButton.gd
extends Button

@export var app_id: String = ""
@export var app_name: String = ""

var icon_url: String = ""
var _focus_sound_player: AudioStreamPlayer
var _awaiting_install_completion: bool = false

const DEFAULT_FLATPAK_EXE_PATH = "/usr/bin/flatpak"


func _ready():
	pressed.connect(_on_pressed)
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(_on_focus_entered_sound)
	
	if get_tree().get_root().has_node("App/FocusSoundPlayer"):
		_focus_sound_player = get_node("/root/App/FocusSoundPlayer")
	else:
		print("AddToSteamButton WARN: FocusSoundPlayer nicht gefunden unter /root/App/FocusSoundPlayer")
		
	if ExtensionsManager:
		ExtensionsManager.extension_status_updated.connect(_on_extension_status_updated)
		
	if ProjectSettings.has_setting("autoload/SteamIntegration"):
		var steam_int = get_node_or_null("/root/SteamIntegration")
		if steam_int and steam_int.has_signal("shortcut_action_completed"):
			steam_int.shortcut_action_completed.connect(_on_shortcut_action_completed)

func _on_shortcut_action_completed(action: String, p_app_id: String, success: bool):
	if (action == "add" or action == "remove") and p_app_id == app_id:
		disabled = false
		text = "Add to Steam"


func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()


func set_app_info(p_app_id: String, p_app_name: String, p_icon_url: String):
	app_id = p_app_id
	app_name = p_app_name
	icon_url = p_icon_url
	tooltip_text = "Add '%s' to your Steam library" % app_name
	text = tr("BTN_ADD_TO_STEAM")
	disabled = false


func _on_extension_status_updated(extension_id: String, is_installed: bool):
	if extension_id == "steam_shortcut_manager_installer" and _awaiting_install_completion:
		# Always re-enable button when operation cycle is complete
		text = "Add to Steam"
		disabled = false
		_awaiting_install_completion = false
		
		if is_installed:
			grab_focus.call_deferred()


func _on_pressed():
	# 1. Check for Extension Dependency
	if not ExtensionsManager.get_extension_status("steam_shortcut_manager_installer"):
		print("AddToSteamButton: Extension missing. Showing dependency popup.")
		var popup_scene = load("res://sections/dependency_popup.tscn")
		if popup_scene:
			var popup = popup_scene.instantiate()
			get_tree().root.add_child(popup)
			popup.setup("install", "Steam Shortcuts", ["steam_shortcut_manager_installer"])
			popup.confirmed.connect(func():
				print("AddToSteamButton: User confirmed extension install.")
				text = "Installing Tool..."
				disabled = true
				_awaiting_install_completion = true
				ExtensionsManager.install_extension("steam_shortcut_manager_installer")
			)
		else:
			printerr("AddToSteamButton ERROR: Could not load dependency_popup.tscn")
		return

	if app_id.is_empty() or app_name.is_empty():
		printerr("AddToSteamButton ERROR: app_id or app_name is empty! Cannot add to Steam.")
		return

	var icon_cache_path: String = ""
	var main_node = get_node_or_null("/root/App") 

	if icon_url.is_empty():
		printerr("AddToSteamButton ERROR: Icon URL is missing for app_id: '", app_id, "'. Cannot determine icon path.")
		text = "Icon URL missing!" 
		await get_tree().create_timer(1.5).timeout
		text = "Add to Steam"
		return
	elif is_instance_valid(main_node) and main_node.has_method("get_cached_image_path"):
		icon_cache_path = main_node.get_cached_image_path(icon_url) 
	else:
		printerr("AddToSteamButton ERROR: Main node '/root/App' not found or 'get_cached_image_path' method is missing!")
		text = "Cache Error!"
		await get_tree().create_timer(1.5).timeout
		text = "Add to Steam"
		text = tr("BTN_ADD_TO_STEAM")
		return

	if icon_cache_path.is_empty():
		printerr("AddToSteamButton ERROR: Icon for app_id '", app_id, "' not found in cache (URL: ", icon_url, "). Cannot add to Steam.")
		text = "Icon Missing!"
		await get_tree().create_timer(1.5).timeout
		text = tr("BTN_ADD_TO_STEAM")
		return

	var global_icon_path: String = ProjectSettings.globalize_path(icon_cache_path)
	if not FileAccess.file_exists(global_icon_path):
		printerr("AddToSteamButton ERROR: Globalized icon path does not exist: '", global_icon_path, "' (Original cache path: '", icon_cache_path, "')")
		text = "Icon Path Error!"
		await get_tree().create_timer(1.5).timeout
		text = tr("BTN_ADD_TO_STEAM")
		return

	print("INFO AddToSteamButton: Button pressed for app_id: '", app_id, "', Name: '", app_name, "'")
	print("INFO AddToSteamButton: Using Icon Path (absolute): '", global_icon_path, "'")
	
	disabled = true
	text = tr("BTN_ADDING")

	if not ProjectSettings.has_setting("autoload/SteamIntegration"):
		printerr("AddToSteamButton ERROR: SteamIntegration Autoload setting not found!")
		text = tr("BTN_INTEGRATION_ERROR")
		await get_tree().create_timer(1.5).timeout
		disabled = false
		text = tr("BTN_ADD_TO_STEAM")
		return

	var steam_integration_node = get_node_or_null("/root/SteamIntegration")
	if not is_instance_valid(steam_integration_node) or not steam_integration_node.has_method("add_to_steam"):
		printerr("AddToSteamButton ERROR: SteamIntegration node not found or 'add_to_steam' method is missing!")
		text = tr("BTN_INTEGRATION_ERROR")
		await get_tree().create_timer(1.5).timeout
		disabled = false
		text = tr("BTN_ADD_TO_STEAM")
		return

	var flatpak_exe_path = DEFAULT_FLATPAK_EXE_PATH
	var flatpak_launch_params = "run %s" % app_id

	var success: bool = steam_integration_node.add_to_steam(app_id, app_name, flatpak_exe_path, flatpak_launch_params, global_icon_path)

	if success:
		print("INFO AddToSteamButton: Successfully called/started add_to_steam for app_id '", app_id, "'. Waiting for signal...")
	else:
		printerr("ERROR AddToSteamButton: Failed to start add_to_steam process for app_id '", app_id, "'.")
		text = tr("BTN_START_FAILED")
		await get_tree().create_timer(1.5).timeout
		disabled = false
		text = tr("BTN_ADD_TO_STEAM")
