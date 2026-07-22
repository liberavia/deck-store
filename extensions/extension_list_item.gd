extends PanelContainer

@onready var name_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionName
@onready var description_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionDescription
@onready var status_label: Label = $MarginContainer/ExtensionContainer/MarginContainer/ExtensionInfoContainer/ExtensionStatus
@onready var icon_texture: TextureRect = $MarginContainer/ExtensionContainer/Control/ExtensionIcon
@onready var status_indicator: TextureRect = $MarginContainer/ExtensionContainer/Control/StatusIndicator

@onready var action_button: Button = $MarginContainer/ExtensionContainer/ActionContainer/ButtonsContainer/ActionButton
@onready var update_button: Button = $MarginContainer/ExtensionContainer/ActionContainer/ButtonsContainer/UpdateButton
@onready var progress_info: VBoxContainer = $MarginContainer/ExtensionContainer/ActionContainer/ProgressInfo
@onready var progress_label: Label = $MarginContainer/ExtensionContainer/ActionContainer/ProgressInfo/ProgressLabel
@onready var progress_bar: ProgressBar = $MarginContainer/ExtensionContainer/ActionContainer/ProgressInfo/ProgressBar

# --- Constants ---
# Colors matching ActionButton.gd
const COLOR_INSTALL = Color("#245322") # Greenish
const COLOR_REMOVE = Color("#5c0001")  # Reddish
const COLOR_BUSY = Color("#4a4a4a")    # Dark Gray
const COLOR_NORMAL = Color("#626262")  # Gray
const COLOR_UPDATE = Color("#005cc5")  # GitHub Blue-ish for Update
const COLOR_PURPLE_BORDER = Color(0.627451, 0.12549, 0.941176, 1)

# --- Internal State ---
var _extension_id: String
var _operation_in_progress: bool = false
var _update_available: bool = false
var _latest_version: String = ""
var _pending_focus_grab: bool = false

# Styleboxes for the button
var stylebox_install: StyleBoxFlat
var stylebox_remove: StyleBoxFlat
var stylebox_busy: StyleBoxFlat
var stylebox_normal: StyleBoxFlat
var stylebox_update: StyleBoxFlat
var stylebox_focus: StyleBoxFlat

# Audio
var stream_focus = preload("res://assets/change.mp3")
var stream_select = preload("res://assets/nextprev.wav")
var audio_player: AudioStreamPlayer

func get_extension_id() -> String:
	return _extension_id

func _ready():
	_setup_audio()
	_setup_styles()
	
	action_button.pressed.connect(_on_action_button_pressed)
	update_button.pressed.connect(_on_update_button_pressed)
	
	action_button.focus_entered.connect(_play_focus_sound)
	update_button.focus_entered.connect(_play_focus_sound)
	
	action_button.pressed.connect(_play_select_sound)
	update_button.pressed.connect(_play_select_sound)
	
	ExtensionsManager.extension_operation_started.connect(_on_operation_started)
	ExtensionsManager.extension_operation_finished.connect(_on_operation_finished)
	ExtensionsManager.extension_update_available.connect(_on_extension_update_available)
	ExtensionsManager.extension_progress_updated.connect(_on_extension_progress_updated)

func _setup_audio():
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)

func _play_focus_sound():
	if audio_player and stream_focus and SettingsManager.get_setting("play_ui_sounds", true):
		audio_player.stream = stream_focus
		audio_player.play()

func _play_select_sound():
	if audio_player and stream_select and SettingsManager.get_setting("play_ui_sounds", true):
		audio_player.stream = stream_select
		audio_player.play()

func _setup_styles():
	var base_stylebox = action_button.get_theme_stylebox("normal")
	if base_stylebox is StyleBoxFlat:
		stylebox_normal = base_stylebox.duplicate()
	else:
		stylebox_normal = StyleBoxFlat.new()
		stylebox_normal.set_corner_radius_all(4)
		stylebox_normal.content_margin_left = 10
		stylebox_normal.content_margin_right = 10
		stylebox_normal.content_margin_top = 5
		stylebox_normal.content_margin_bottom = 5
	
	stylebox_install = stylebox_normal.duplicate()
	stylebox_install.bg_color = COLOR_INSTALL
	
	stylebox_remove = stylebox_normal.duplicate()
	stylebox_remove.bg_color = COLOR_REMOVE
	
	stylebox_busy = stylebox_normal.duplicate()
	stylebox_busy.bg_color = COLOR_BUSY
	
	stylebox_update = stylebox_normal.duplicate()
	stylebox_update.bg_color = COLOR_UPDATE
	
	stylebox_normal.bg_color = COLOR_NORMAL
	
	# Setup focus style
	stylebox_focus = stylebox_normal.duplicate()
	stylebox_focus.draw_center = false
	stylebox_focus.border_width_left = 3
	stylebox_focus.border_width_top = 3
	stylebox_focus.border_width_right = 3
	stylebox_focus.border_width_bottom = 3
	stylebox_focus.border_color = COLOR_PURPLE_BORDER
	
	action_button.add_theme_stylebox_override("focus", stylebox_focus)
	update_button.add_theme_stylebox_override("focus", stylebox_focus)
	# Set update button normal style permanently
	update_button.add_theme_stylebox_override("normal", stylebox_update)

func _on_update_button_pressed():
	if _operation_in_progress: return
	
	# Dependency check for update (might need new dependencies?)
	var missing_deps = ExtensionsManager.get_missing_dependencies(_extension_id)
	if not missing_deps.is_empty():
		_show_dependency_popup("install", missing_deps) # Update is effectively install
		return
	
	print("INFO: Requesting update for ", _extension_id)
	_start_progress_display("Updating...")
	ExtensionsManager.update_extension(_extension_id)

func _on_action_button_pressed():
	if _operation_in_progress: return
	
	var current_text = action_button.text
	if current_text == "Install":
		# Check dependencies for Install
		var missing_deps = ExtensionsManager.get_missing_dependencies(_extension_id)
		if not missing_deps.is_empty():
			_show_dependency_popup("install", missing_deps)
			return

		print("INFO: Requesting install for ", _extension_id)
		_start_progress_display("Initializing...")
		ExtensionsManager.install_extension(_extension_id)
			
	elif current_text == "Uninstall":
		# Check dependents for Uninstall
		var dependents = ExtensionsManager.get_installed_dependents(_extension_id)
		if not dependents.is_empty():
			_show_dependency_popup("uninstall", dependents)
			return

		print("INFO: Requesting uninstall for ", _extension_id)
		_start_progress_display("Uninstalling...")
		ExtensionsManager.uninstall_extension(_extension_id)

func _show_dependency_popup(mode: String, dependency_ids: Array):
	var popup_scene = load("res://sections/dependency_popup.tscn")
	var popup = popup_scene.instantiate()
	
	# Add directly to root to ensure it exists and is independent of UI structure
	get_tree().root.add_child(popup)
	
	popup.setup(mode, name_label.text, dependency_ids)
	
	popup.confirmed.connect(func():
		if mode == "install":
			# Order: Dependencies first, then target
			var install_list = dependency_ids.duplicate()
			install_list.append(_extension_id)
			print("INFO: Batch install confirmed: ", install_list)
			
			# Check if it's an update (already installed) or fresh install
			var op = "update" if ExtensionsManager.get_extension_status(_extension_id) else "install"
			ExtensionsManager.execute_transaction(install_list, op)
			
		elif mode == "uninstall":
			# Order: Dependents first, then target
			var remove_list = dependency_ids.duplicate()
			remove_list.append(_extension_id)
			print("INFO: Batch remove confirmed: ", remove_list)
			ExtensionsManager.execute_transaction(remove_list, "remove")
	)

func _start_progress_display(label_text: String):
	progress_info.visible = true
	progress_label.text = label_text
	progress_bar.value = 0
	
func _on_extension_progress_updated(extension_id: String, percent: int, message: String):
	if extension_id == _extension_id:
		progress_info.visible = true
		progress_bar.value = percent
		progress_label.text = message

func _on_operation_started(extension_id: String, _operation: String):
	if extension_id == _extension_id:
		_operation_in_progress = true
		update_status(ExtensionsManager.get_extension_status(_extension_id))

func _on_operation_finished(extension_id: String, operation: String):
	if extension_id == _extension_id:
		_operation_in_progress = false
		_pending_focus_grab = true
		progress_bar.value = 100
		
		# If update finished, re-check status to hide update button if necessary
		if operation == "update":
			_update_available = not ExtensionsManager.get_update_status(_extension_id).is_empty()
		
		update_status(ExtensionsManager.get_extension_status(_extension_id))
		
		get_tree().create_timer(0.5).timeout.connect(func():
			progress_info.visible = false
		)

func _grab_appropriate_focus():
	if update_button.visible and not update_button.disabled:
		update_button.grab_focus()
	elif action_button.visible and not action_button.disabled:
		action_button.grab_focus()

func _on_extension_update_available(extension_id: String, latest_version: String):
	if extension_id == _extension_id:
		_update_available = true
		_latest_version = latest_version
		update_status(ExtensionsManager.get_extension_status(_extension_id))

func set_data(extension_data: Dictionary):
	_extension_id = extension_data.get("id", "unknown_id")
	name_label.text = extension_data.get("name", "Unknown Extension")
	description_label.text = extension_data.get("description", "No description available.")
	
	var icon_filename = extension_data.get("icon", "")
	var internal_path = extension_data.get("internal_path", "")
	
	if not icon_filename.is_empty() and not internal_path.is_empty():
		var icon_path = internal_path.path_join(icon_filename)
		if ResourceLoader.exists(icon_path):
			var texture = load(icon_path) as Texture2D
			if texture:
				icon_texture.texture = texture
				icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE 
				icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			else:
				icon_texture.texture = null
		else:
			icon_texture.texture = null
			
	# Check if an update is already known for this extension
	var known_update = ExtensionsManager.get_update_status(_extension_id)
	if not known_update.is_empty():
		_update_available = true
		_latest_version = known_update
	
	# Initial status update
	update_status(ExtensionsManager.get_extension_status(_extension_id))

func update_status(is_installed: bool):
	status_indicator.visible = is_installed
	
	if is_installed:
		action_button.text = "Uninstall"
		action_button.add_theme_stylebox_override("normal", stylebox_remove)
		
		if _update_available:
			status_label.text = "Update Available (v" + _latest_version + ")"
			update_button.visible = true
			update_button.text = "Update v" + _latest_version
		else:
			status_label.text = "Installed"
			update_button.visible = false
	else:
		status_label.text = "Not Installed"
		action_button.text = "Install"
		action_button.add_theme_stylebox_override("normal", stylebox_install)
		update_button.visible = false
	
	if _operation_in_progress:
		action_button.disabled = true
		update_button.disabled = true
		action_button.text = "..."
		update_button.visible = false 
		# If busy, hide update button to avoid confusion, focus on progress bar
		action_button.add_theme_stylebox_override("normal", stylebox_busy)
	else:
		action_button.disabled = false
		update_button.disabled = false
		progress_info.visible = false 

	if _pending_focus_grab:
		_grab_appropriate_focus.call_deferred()
		_pending_focus_grab = false
