extends Button

@export var app_id: String = ""

var current_operation_id: String = ""
var _focus_sound_player: AudioStreamPlayer
var progress_info: VBoxContainer
var progress_bar: ProgressBar
var progress_label: Label

func _ready():
	self.focus_entered.connect(_on_focus_entered_sound)
	self.focus_mode = Control.FOCUS_ALL

	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	if not _focus_sound_player:
		printerr("FocusSoundPlayer not found at /root/App/FocusSoundPlayer!")
	
	progress_info = get_node_or_null("/root/App/DetailsView/MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/ProgressInfo")
	progress_bar = get_node_or_null("/root/App/DetailsView/MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/ProgressInfo/ProgressBar")
	progress_label = get_node_or_null("/root/App/DetailsView/MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/ProgressInfo/ProgressLabel")
	if progress_bar:
		progress_info.visible = false
		
	self.pressed.connect(_on_pressed)
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		if DownloadManager.has_signal("task_updated"):
			print("INFO: Connect Downloadmanager task_updated")
			DownloadManager.task_updated.connect(_on_task_updated)
		if DownloadManager.has_signal("task_finished"):
			print("INFO: Connect Downloadmanager task_finished")
			DownloadManager.task_finished.connect(_on_task_finished)
	else:
		printerr("DownloadManager Autoload nicht gefunden!")
		disabled = true # Button deaktivieren, wenn Manager fehlt
		return

func set_app_id(assigned_id):
	app_id = assigned_id
	var initial_status = DownloadManager.get_task_status(app_id)
	_update_ui(initial_status)	

func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()
		
# Weiter in InstallButton.gd

func _on_pressed():
	print("INFO: Pressed install button")
	if app_id.is_empty():
		print("ERROR: AppID is empty!")
		return

	var status_data = DownloadManager.get_task_status(app_id)
	var current_status = status_data.get("status", null) # Sicherer Zugriff

	# Logik basierend auf dem aktuellen Status
	if current_status == null or current_status == "cancelled" or current_status == "failed":
		# Installation starten
		print("Starte Installation für: ", app_id)
		visible = false
		
		current_operation_id = DownloadManager.queue_install(app_id)
		# UI sofort auf "queued" setzen, bis das erste Update kommt
		_update_ui({"status": "queued"})

	elif current_status == "completed":
		# Deinstallation starten
		print("Starte Deinstallation für: ", app_id)
		progress_label.text = "Waiting..."
		visible = false
		current_operation_id = DownloadManager.queue_uninstall(app_id)
		# UI sofort auf "queued" setzen
		_update_ui({"status": "queued"})

	elif current_status == "downloading" or current_status == "preparing" or current_status == "queued":
		# Laufenden Download/Vorbereitung abbrechen
		if not current_operation_id.is_empty():
			print("Breche Operation ab: ", current_operation_id)
			DownloadManager.cancel_operation(current_operation_id)
		else:
			print("Kann nicht abbrechen, keine laufende operation_id bekannt für ", app_id)

	# Optional: Abbruch von "installing" oder "removing" erlauben? (Kann heikel sein)
	# elif current_status == "installing" or current_status == "removing":
	#     # Abbruch versuchen?
	#     pass
	
func _on_task_updated(operation_id: String, status_data: Dictionary):
	# Prüfen, ob das Update für diesen Button/diese App relevant ist
	if operation_id == current_operation_id or (status_data.has("app_id") and status_data.app_id == app_id):
		# Wenn der Task gerade erst gestartet wurde, speichere seine ID
		if status_data.status == "preparing" or status_data.status == "queued":
			current_operation_id = operation_id
		# Aktualisiere die UI basierend auf den neuen Daten
		_update_ui(status_data)

func _on_task_finished(operation_id: String, _final_status: String):
	# Prüfen, ob der beendete Task unserer war
	if operation_id == current_operation_id:
		# Letzten bekannten Status holen und UI aktualisieren
		var final_task_data = DownloadManager.get_task_status(app_id)
		_update_ui(final_task_data)
		# ID zurücksetzen, da der Task nicht mehr aktiv ist
		current_operation_id = ""


# Hilfsfunktion zur UI-Aktualisierung
func _update_ui(status_data: Dictionary):
	if status_data.is_empty():
		progress_label.text = "Installing"
		visible = true
		if progress_info: progress_info.visible = false
		# Andere Labels zurücksetzen
		return

	var status = status_data.get("status", "unknown")
	var progress = status_data.get("progress", 0)
	var speed = status_data.get("speed", null)
	var eta = status_data.get("eta", null)

	# ProgressBar Sichtbarkeit und Wert
	if progress_bar:
		if status == "downloading" or status == "installing":
			progress_info.visible = true
			progress_bar.value = progress
		else:
			progress_info.visible = false

	# Button Text und Zustand
	match status:
		"queued", "preparing":
			progress_label.text = "Waiting..."
			progress_info.visible = true
			visible = false
		"downloading":
			progress_label.text = "Downloading (%d%%)" % progress
			progress_info.visible = true
			visible = false
			# Hier Speed/ETA Labels aktualisieren, z.B.:
			# $SpeedLabel.text = str(speed) if speed else ""
			# $EtaLabel.text = str(eta) if eta else ""
		"installing":
			progress_label.text = "Installing (%d%%)..." % progress
			progress_info.visible = true
			visible = false 
		"removing":
			progress_label.text = "Removing..."
			progress_info.visible = true
			visible = false
		"completed":
			progress_label.text = "Completed"
			progress_info.visible = false
			visible = true
		"failed":
			progress_label.text= "Error!" # Oder "Erneut versuchen"
			visible = true
			progress_info.visible = false
		"cancelled":
			progress_label.text = "Cancelled"
			visible = true
			progress_info.visible = false
		_: # Unbekannter Status oder null
			progress_label.text = "Installing"
			visible = true
			progress_info.visible = false
	
	# Evtl. Speed/ETA Labels leeren, wenn nicht downloading
	if status != "downloading":
		# $SpeedLabel.text = ""
		# $EtaLabel.text = ""
		pass # Platzhalter	
