# AddToSteamButton.gd
extends Button

@export var app_id: String = "" # Dies ist der Flatpak App ID, entspricht appid_tag
@export var app_name: String = "" # Der Anzeigename des Spiels/der App

var icon_url: String = "" # URL zum Icon, um den Cache-Pfad zu finden
var _focus_sound_player: AudioStreamPlayer

# Standardpfad für die Flatpak-Executable, wie in SteamIntegration und DownloadManager
const DEFAULT_FLATPAK_EXE_PATH = "/usr/bin/flatpak"


func _ready():
	# Verbinde pressed Signal
	pressed.connect(_on_pressed)
	# Fokus-Einstellungen und Sound (optional)
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(_on_focus_entered_sound)
	
	# Versuche, den AudioStreamPlayer zu bekommen
	if get_tree().get_root().has_node("App/FocusSoundPlayer"): # Sicherer Zugriff
		_focus_sound_player = get_node("/root/App/FocusSoundPlayer")
	else:
		print("AddToSteamButton WARN: FocusSoundPlayer nicht gefunden unter /root/App/FocusSoundPlayer")


func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()


# Funktion, die von einer Detailansicht aufgerufen wird, um die nötigen Infos zu setzen
func set_app_info(p_app_id: String, p_app_name: String, p_icon_url: String):
	app_id = p_app_id
	app_name = p_app_name
	icon_url = p_icon_url
	# Tooltip hinzufügen, der den Benutzern sagt, was der Button macht
	tooltip_text = "Add '%s' to your Steam library" % app_name
	# Text initial setzen oder aktualisieren
	text = "Add to Steam" 
	disabled = false # Sicherstellen, dass der Button initial nicht deaktiviert ist


func _on_pressed():
	if app_id.is_empty() or app_name.is_empty():
		printerr("AddToSteamButton ERROR: app_id or app_name is empty! Cannot add to Steam.")
		return

	var icon_cache_path: String = ""
	# Sicherer Zugriff auf den Hauptknoten (passe "/root/App" ggf. an deinen Szenenbaum an)
	var main_node = get_node_or_null("/root/App") 

	if icon_url.is_empty():
		printerr("AddToSteamButton ERROR: Icon URL is missing for app_id: '", app_id, "'. Cannot determine icon path.")
		# Benutzerfeedback geben
		text = "Icon URL missing!" 
		await get_tree().create_timer(1.5).timeout # Kurze Anzeige der Fehlermeldung
		text = "Add to Steam" # Text zurücksetzen
		return
	elif is_instance_valid(main_node) and main_node.has_method("get_cached_image_path"):
		# Hole den Pfad zum gecachten Bild vom Hauptknoten
		icon_cache_path = main_node.get_cached_image_path(icon_url) 
	else:
		printerr("AddToSteamButton ERROR: Main node '/root/App' not found or 'get_cached_image_path' method is missing!")
		# Benutzerfeedback geben
		text = "Cache Error!"
		await get_tree().create_timer(1.5).timeout
		text = "Add to Steam"
		return

	if icon_cache_path.is_empty():
		printerr("AddToSteamButton ERROR: Icon for app_id '", app_id, "' not found in cache (URL: ", icon_url, "). Cannot add to Steam.")
		# Benutzerfeedback geben
		text = "Icon Missing!"
		await get_tree().create_timer(1.5).timeout
		text = "Add to Steam"
		return

	# Konvertiere den user:// oder res:// Pfad zu einem absoluten Systempfad
	var global_icon_path: String = ProjectSettings.globalize_path(icon_cache_path)
	if not FileAccess.file_exists(global_icon_path):
		printerr("AddToSteamButton ERROR: Globalized icon path does not exist: '", global_icon_path, "' (Original cache path: '", icon_cache_path, "')")
		text = "Icon Path Error!"
		await get_tree().create_timer(1.5).timeout
		text = "Add to Steam"
		return

	print("INFO AddToSteamButton: Button pressed for app_id: '", app_id, "', Name: '", app_name, "'")
	print("INFO AddToSteamButton: Using Icon Path (absolute): '", global_icon_path, "'")
	
	# Button deaktivieren und Text ändern, um Feedback zu geben
	disabled = true
	text = "Adding..."

	# Überprüfe, ob das SteamIntegration Autoload vorhanden ist
	if not ProjectSettings.has_setting("autoload/SteamIntegration"):
		printerr("AddToSteamButton ERROR: SteamIntegration Autoload setting not found!")
		text = "Integration Error!"
		await get_tree().create_timer(1.5).timeout
		disabled = false
		text = "Add to Steam"
		return

	# Sicherer Zugriff auf das SteamIntegration Singleton
	var steam_integration_node = get_node_or_null("/root/SteamIntegration") # Passe Pfad/Namen ggf. an
	if not is_instance_valid(steam_integration_node) or not steam_integration_node.has_method("add_to_steam"):
		printerr("AddToSteamButton ERROR: SteamIntegration node not found or 'add_to_steam' method is missing!")
		text = "Integration Error!"
		await get_tree().create_timer(1.5).timeout
		disabled = false
		text = "Add to Steam"
		return

	# Definiere exe_path und launch_params für Flatpak-Anwendungen
	var flatpak_exe_path = DEFAULT_FLATPAK_EXE_PATH
	var flatpak_launch_params = "run %s" % app_id # z.B. "run com.brave.Browser"

	# Rufe die add_to_steam Funktion mit allen 5 erforderlichen Argumenten auf
	# app_id hier ist der appid_tag für SteamIntegration
	var success: bool = steam_integration_node.add_to_steam(app_id, app_name, flatpak_exe_path, flatpak_launch_params, global_icon_path)

	# Die weitere Verarbeitung des Ergebnisses (success/failure) sollte über das
	# 'shortcut_action_completed' Signal von SteamIntegration erfolgen,
	# um den Button-Zustand zu aktualisieren und dem Benutzer Feedback zu geben.
	# Hier setzen wir den Button vorerst zurück, aber eine robustere Lösung
	# würde auf das Signal warten.

	if success: # Dies 'success' ist nur, ob der Thread gestartet werden konnte
		print("INFO AddToSteamButton: Successfully called/started add_to_steam for app_id '", app_id, "'. Waiting for signal...")
		# Der Text "Adding..." bleibt, bis das Signal von SteamIntegration kommt.
		# Die Logik zum Zurücksetzen des Buttons und Anzeigen des finalen Status
		# sollte idealerweise in einer Funktion erfolgen, die mit 
		# SteamIntegration.shortcut_action_completed verbunden ist.
	else:
		printerr("ERROR AddToSteamButton: Failed to start add_to_steam process for app_id '", app_id, "'.")
		text = "Start Failed!"
		await get_tree().create_timer(1.5).timeout
		disabled = false
		text = "Add to Steam"

# Beispielhafte Funktion, die mit SteamIntegration.shortcut_action_completed verbunden werden könnte:
# func _on_steam_integration_action_completed(action: String, completed_app_id: String, op_success: bool):
# 	if action == "add" and completed_app_id == self.app_id:
# 		if op_success:
# 			text = "Added!" # Oder Button ausblenden etc.
# 			# Ggf. Button permanent deaktivieren oder ausblenden, da schon hinzugefügt
# 			# visible = false 
# 		else:
# 			text = "Add Failed!"
# 		
# 		await get_tree().create_timer(2.0).timeout # Zeige Status kurz an
# 		disabled = false
# 		text = "Add to Steam" # Oder Text basierend auf neuem Status (z.B. "In Steam")
# 		# Hier könnte man auch prüfen, ob der Shortcut jetzt existiert und den Button-Text/Status anpassen
# 		# z.B. SteamIntegration.check_in_steam_async(self.app_id) aufrufen und UI entsprechend aktualisieren
