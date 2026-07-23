extends Button

@export var install_color := Color.from_string("#245322", Color.GREEN)
@export var remove_color := Color.from_string("#5c0001", Color.RED)
@export var busy_color := Color.from_string("#4a4a4a", Color.DARK_GRAY) # Farbe für nicht-interaktive Zustände
@export var normal_color := Color.from_string("#626262", Color.GRAY) # Standardfarbe, wenn nichts zutrifft

@export var app_id: String = ""
@export var is_initially_installed: bool = false
var current_operation_id: String = ""
var app_size_bytes: int = 0
var _focus_sound_player: AudioStreamPlayer

var stylebox_normal: StyleBoxFlat
var stylebox_install: StyleBoxFlat
var stylebox_remove: StyleBoxFlat
var stylebox_busy: StyleBoxFlat
var _pressed_sound_player: AudioStreamPlayer


var app_name: String = ""
var icon_url: String = ""
var app_scope: String = ""

const TEXT_INSTALL = "Install"
const TEXT_UNINSTALL = "Remove"
const TEXT_CANCEL = "Cancel"
const TEXT_WAITING = "Waiting..."
const TEXT_DOWNLOADING = "Downloading"
const TEXT_INSTALLING = "Installing..."
const TEXT_REMOVING = "Removing..."
const TEXT_ERROR = "Error"
const TEXT_CANCELLED = "Cancelled"
const TEXT_SYSTEM = "Installed (System)"


func _ready():
	self.focus_entered.connect(_on_focus_entered_sound)
	self.focus_mode = Control.FOCUS_ALL

	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")

	var base_stylebox = get_theme_stylebox("normal")
	if base_stylebox is StyleBoxFlat: stylebox_normal = base_stylebox.duplicate()
	else: stylebox_normal = StyleBoxFlat.new(); stylebox_normal.set_corner_radius_all(4); stylebox_normal.content_margin_left = 10; stylebox_normal.content_margin_right = 10; stylebox_normal.content_margin_top = 5; stylebox_normal.content_margin_bottom = 5
	stylebox_install = stylebox_normal.duplicate(); stylebox_install.bg_color = install_color
	stylebox_remove = stylebox_normal.duplicate(); stylebox_remove.bg_color = remove_color
	stylebox_busy = stylebox_normal.duplicate(); stylebox_busy.bg_color = busy_color
	stylebox_normal.bg_color = normal_color # Setze die normale Hintergrundfarbe

	self.pressed.connect(_on_pressed)

	if ProjectSettings.has_setting("autoload/DownloadManager"):
		if DownloadManager.has_signal("task_updated"): DownloadManager.task_updated.connect(_on_task_updated)
		if DownloadManager.has_signal("task_finished"): DownloadManager.task_finished.connect(_on_task_finished)
	else:
		printerr("ActionButton: DownloadManager Autoload not found!"); disabled = true; text = "Error"
		return

	if not app_id.is_empty(): _update_ui(DownloadManager.get_task_status(app_id))
	print("DEBUG UI: ActionButton _ready finished for ", app_id)

func set_app_info(id: String, p_name: String, url):
	app_id = id
	app_name = p_name # Speichern!
	icon_url = str(url) if url != null else ""   # Sicherstellen, dass es ein String ist!

	# Initialen Status basierend auf Installation und DownloadManager setzen
	var main_node = get_node_or_null("/root/App") # Pfad anpassen!
	var is_installed = false
	app_scope = ""
	if main_node and main_node.has_method("is_app_installed"):
		is_installed = main_node.is_app_installed(app_id)
		if is_installed and main_node.has_method("get_app_scope"):
			app_scope = main_node.get_app_scope(app_id)

	var active_task_status = DownloadManager.get_task_status(app_id)
	var manager_has_active_task = false
	if not active_task_status.is_empty():
		var status = active_task_status.get("status")
		if status != null and not ["completed", "failed", "cancelled"].has(status):
			manager_has_active_task = true
			if active_task_status.has("operation_id"): current_operation_id = active_task_status.operation_id

	if manager_has_active_task:
		_update_ui(active_task_status)
	else:
		if is_installed: _update_ui({"status": "completed", "app_id": app_id, "name": app_name, "icon_url": icon_url, "scope": app_scope}) # Name/Icon/Scope mitgeben
		else: _update_ui({})


func set_app_id_and_initial_state(assigned_id: String, is_initially_installed: bool):
	# print("DEBUG UI: Setting initial state for ", assigned_id, " - Installed: ", is_initially_installed) # Weniger Output
	app_id = assigned_id
	current_operation_id = ""
	app_scope = ""
	
	var main_node = get_node_or_null("/root/App")
	if is_initially_installed and main_node and main_node.has_method("get_app_scope"):
		app_scope = main_node.get_app_scope(app_id)

	var active_task_status = DownloadManager.get_task_status(app_id)
	var manager_has_active_task = false
	if not active_task_status.is_empty():
		var status = active_task_status.get("status")
		if status != null and status != "completed" and status != "failed" and status != "cancelled":
			manager_has_active_task = true
			if active_task_status.has("operation_id"): current_operation_id = active_task_status.operation_id

	if manager_has_active_task:
		# print("DEBUG UI: Initial state from active task: ", active_task_status) # Weniger Output
		_update_ui(active_task_status)
	else:
		# print("DEBUG UI: Initial state from installed flag: ", is_initially_installed) # Weniger Output
		if is_initially_installed: _update_ui({"status": "completed", "app_id": app_id, "scope": app_scope})
		else: _update_ui({})


func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player) and SettingsManager.get_setting("play_ui_sounds", true): 
		_focus_sound_player.play()


func _on_pressed():
	print("INFO: ActionButton pressed for app: ", app_id, " (Current Text: '", self.text, "', Disabled: ", self.disabled, ")")
	if app_id.is_empty(): printerr("ERROR: ActionButton - AppID is empty!"); return

	if self.disabled:
		print("DEBUG UI: Button pressed but disabled.")
		return

	_pressed_sound_player = get_node_or_null("/root/App/ButtonSoundPlayer")
	if _pressed_sound_player and SettingsManager.get_setting("play_ui_sounds", true):
		_pressed_sound_player.play()

	match self.text:
		TEXT_INSTALL, TEXT_ERROR, TEXT_CANCELLED: 
			var space_left: int = 0
			var dir = DirAccess.open("user://")
			if dir:
				space_left = dir.get_space_left()
				
			if space_left > 0 and app_size_bytes > 0:
				# Add 10% safety buffer
				if space_left < (app_size_bytes * 1.1):
					print("ActionButton: Not enough space! Need ", app_size_bytes, " but have ", space_left)
					self.text = "Not enough space"
					self.disabled = true
					return

			print("ActionButton: Choosing INSTALL path based on text '", self.text, "'")
			self.disabled = true; self.text = TEXT_WAITING; add_theme_stylebox_override("normal", stylebox_busy)
			var app_data_for_task = {"name": app_name, "icon": icon_url, "icon_url": icon_url}
			current_operation_id = DownloadManager.queue_install(app_id, app_data_for_task)

		TEXT_UNINSTALL: 
			print("ActionButton: Choosing UNINSTALL path based on text '", self.text, "'")
			self.disabled = true; self.text = TEXT_WAITING; add_theme_stylebox_override("normal", stylebox_busy)
			var app_data_for_task = {"name": app_name, "icon": icon_url, "icon_url": icon_url}
			current_operation_id = DownloadManager.queue_uninstall(app_id, app_data_for_task)

		TEXT_CANCEL:
			if not current_operation_id.is_empty():
				print("ActionButton: Choosing CANCEL path based on text '", self.text, "' for OpID: ", current_operation_id)
				self.disabled = true; self.text = "Cancelling..."; add_theme_stylebox_override("normal", stylebox_busy)
				DownloadManager.cancel_operation(current_operation_id)
			else:
				printerr("ActionButton: Cannot cancel, no known operation_id for ", app_id)

		_: 		   
			printerr("ActionButton: Pressed with unexpected/busy text: ", self.text)


func _on_task_updated(operation_id: String, status_data: Dictionary):
	# print("DEBUG UI: _on_task_updated SIGNAL RECEIVED for OpID: ", operation_id, " My OpID: ", current_operation_id) # Weniger Output
	if status_data.has("app_id") and status_data.app_id == app_id:
		var status = status_data.get("status", "unknown")
		if status == "preparing" or status == "queued":
			if current_operation_id != operation_id:
				# print("DEBUG UI: Storing current_operation_id: ", operation_id) # Weniger Output
				current_operation_id = operation_id
		if operation_id == current_operation_id or current_operation_id.is_empty():
			_update_ui(status_data)


func _on_task_finished(operation_id: String, final_status: String, operation_type: String):
	# print("DEBUG UI: _on_task_finished SIGNAL RECEIVED for OpID: ", operation_id, " My OpID: ", current_operation_id, " Status: ", final_status, " Type: ", operation_type) # Weniger Output
	if operation_id == current_operation_id:
		var final_ui_status_data = {}
		if final_status == "completed":
			if operation_type == "install": final_ui_status_data = {"status": "completed", "app_id": app_id}
			elif operation_type == "uninstall": final_ui_status_data = {}
			else: printerr("Unbekannter operation_type in _on_task_finished: ", operation_type); final_ui_status_data = {}
			print("DEBUG UI: Triggering app list refresh after completed operation.")
			var main_app_node = get_node_or_null("/root/App")
			if main_app_node and main_app_node.has_method("_fetch_installed_apps"): 
				main_app_node._fetch_installed_apps() 
			else: printerr("ActionButton: Could not find node/method to refresh installed apps!")
		elif final_status == "failed":
			final_ui_status_data = {"status": "failed", "app_id": app_id, "error": DownloadManager.get_task_status(app_id).get("error", "Unknown error")}
		elif final_status == "cancelled":
			final_ui_status_data = {}

		_update_ui(final_ui_status_data)
		current_operation_id = ""


func _update_ui(status_data: Dictionary):
	var button_text = TEXT_INSTALL; var button_disabled = false
	var button_stylebox = stylebox_install; var show_button = true

	if not status_data.is_empty():
		var status = status_data.get("status", "unknown")
		var scope = status_data.get("scope", app_scope)

		match status:
			"queued", "preparing":
				button_text = TEXT_WAITING; button_disabled = true; button_stylebox = stylebox_busy
			"downloading":
				button_text = TEXT_CANCEL; button_disabled = false; button_stylebox = stylebox_remove
			"installing":
				button_text = TEXT_INSTALLING; button_disabled = true; button_stylebox = stylebox_busy
			"removing":
				button_text = TEXT_REMOVING; button_disabled = true; button_stylebox = stylebox_busy
			"completed":
				if scope == "system":
					button_text = TEXT_SYSTEM; button_disabled = true; button_stylebox = stylebox_busy
				else:
					button_text = TEXT_UNINSTALL; button_disabled = false; button_stylebox = stylebox_remove
			"failed":
				button_text = TEXT_ERROR; button_disabled = false; button_stylebox = stylebox_normal
			"cancelled":
				button_text = TEXT_INSTALL; button_disabled = false; button_stylebox = stylebox_install
			_:
				button_text = TEXT_INSTALL; button_disabled = false; button_stylebox = stylebox_install
	else:
		# No task data, but check our internal app_scope for initial state
		if app_scope == "system":
			button_text = TEXT_SYSTEM; button_disabled = true; button_stylebox = stylebox_busy

	if button_text == TEXT_INSTALL and AppBlacklist.is_blacklisted(app_id):
		button_text = "Blacklisted"
		button_disabled = true
		button_stylebox = stylebox_busy
		
	if button_text == TEXT_INSTALL and Engine.has_singleton("OnlineStatusManager") and not get_node("/root/OnlineStatusManager").is_online:
		button_text = "Offline"
		button_disabled = true
		button_stylebox = stylebox_busy

	self.text = button_text
	self.disabled = button_disabled
	self.visible = show_button
	self.add_theme_stylebox_override("normal", button_stylebox)
	self.add_theme_stylebox_override("disabled", stylebox_busy)
