class_name ProductBox
extends Control

@onready var panel: Panel = $Panel
@onready var status_indicator: Control = $Panel/StatusIndicator
@onready var install_overlay: ColorRect = $Panel/InstallOverlay
@onready var status_label: Label = $Panel/InstallOverlay/VBoxContainer/StatusLabel
@onready var progress_bar: ProgressBar = $Panel/InstallOverlay/VBoxContainer/ProgressBar
@onready var loading_spinner: TextureRect = $Panel/LoadingSpinner

signal move_to_details_view(app_id: String, installed: bool)

@export var focused_scale_factor: float = 1.05
@export var animation_duration: float = 0.1

var _original_panel_style: StyleBox
var _focus_sound_player: AudioStreamPlayer
var app_id: String = ""
var is_installed: bool = false
var default_scale: Vector2 = Vector2.ONE
var scale_tween: Tween = null

func _ready():
	if panel: 
		_original_panel_style = panel.get_theme_stylebox("panel")
		# Ensure children don't block mouse events for the parent
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		for child in panel.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_PASS
	else: 
		printerr("Panel node not found in ProductBox!")

	self.focus_entered.connect(_on_focus_entered_visual)
	self.focus_exited.connect(_on_focus_exited_visual)
	self.focus_entered.connect(_on_focus_entered_sound)
	self.mouse_entered.connect(_on_mouse_entered)
	self.gui_input.connect(_on_gui_input)
	
	self.mouse_filter = Control.MOUSE_FILTER_STOP # Parent should catch everything
	self.focus_mode = Control.FOCUS_ALL
	
	default_scale = self.scale
	
	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	if not _focus_sound_player:
		printerr("FocusSoundPlayer not found at /root/App/FocusSoundPlayer!")
		
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		var DownloadManager = get_node_or_null("/root/DownloadManager")
		if DownloadManager:
			if DownloadManager.has_signal("task_updated"):
				DownloadManager.task_updated.connect(_on_task_updated)
			if DownloadManager.has_signal("task_finished"):
				DownloadManager.task_finished.connect(_on_task_finished)
	if loading_spinner:
		loading_spinner.pivot_offset = loading_spinner.size / 2.0
	_update_install_status()

func _process(delta):
	if is_instance_valid(loading_spinner) and loading_spinner.visible:
		loading_spinner.rotation += delta * 5.0

func set_app_id(assigned_id: String):
	app_id = assigned_id
	_update_install_status()
		
func set_installed_status(installed_status: bool):
	is_installed = installed_status
	if is_instance_valid(status_indicator) and not (is_instance_valid(install_overlay) and install_overlay.visible):
		status_indicator.visible = is_installed
	_update_install_status()

func _update_install_status():
	if app_id.is_empty(): return
	if not is_inside_tree(): return
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		var DownloadManager = get_node_or_null("/root/DownloadManager")
		if DownloadManager:
			var task_status = DownloadManager.get_task_status(app_id)
			if task_status.get("status") in ["running", "pending"]:
				_show_installing(task_status)
			else:
				_hide_installing()

func _on_task_updated(updated_app_id: String, task_data: Dictionary):
	if updated_app_id == app_id:
		_show_installing(task_data)

func _on_task_finished(finished_app_id: String, _success: bool, _message: String):
	if finished_app_id == app_id:
		_hide_installing()

func _show_installing(task_data: Dictionary):
	if is_instance_valid(install_overlay):
		install_overlay.visible = true
		if is_instance_valid(loading_spinner):
			loading_spinner.visible = true
		if is_instance_valid(status_indicator):
			status_indicator.visible = false
		var progress = task_data.get("progress", 0)
		if is_instance_valid(progress_bar):
			progress_bar.value = progress
		if is_instance_valid(status_label):
			var status_text = task_data.get("status", "Installing")
			if status_text == "pending":
				status_text = "In Queue..."
			status_label.text = status_text.capitalize() + "\n" + str(progress) + "%"

func _hide_installing():
	if is_instance_valid(install_overlay):
		install_overlay.visible = false
		if is_instance_valid(loading_spinner):
			loading_spinner.visible = false
		if is_instance_valid(status_indicator):
			status_indicator.visible = is_installed

func _unhandled_input(event: InputEvent):
	if not has_focus():
		return
		
	if event.is_action_pressed("ui_accept"):
		emit_signal("move_to_details_view", app_id, is_installed)

func _on_focus_entered_visual():
	if not is_instance_valid(panel): return
	
	if scale_tween and scale_tween.is_valid():
		scale_tween.kill()	
	
	if _original_panel_style is StyleBoxFlat:
		var focused_style = _original_panel_style.duplicate() as StyleBoxFlat
		focused_style.border_color = Color.PURPLE
		focused_style.border_width_top = 3 
		focused_style.border_width_left = 3 
		focused_style.border_width_right = 3 
		focused_style.border_width_bottom = 3 
		panel.add_theme_stylebox_override("panel", focused_style)
	else:
		panel.modulate = Color.REBECCA_PURPLE.lightened(0.6)
		
	self.pivot_offset = self.size / 2.0
	scale_tween = create_tween()
	var target_scale = default_scale * focused_scale_factor
	scale_tween.tween_property(self, "scale", target_scale, animation_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

func _on_focus_exited_visual():
	if not is_instance_valid(panel): return
	
	if scale_tween and scale_tween.is_valid():
		scale_tween.kill()
	self.pivot_offset = self.size / 2.0
	scale_tween = create_tween()
	
	scale_tween.tween_property(self, "scale", default_scale, animation_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN)

	panel.remove_theme_stylebox_override("panel")
	panel.add_theme_stylebox_override("panel", _original_panel_style)

func _on_mouse_entered():
	# Grab focus on hover for visual consistency with controller navigation
	self.grab_focus()

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("DEBUG ProductBox: Mouse click detected for AppID: ", app_id)
		emit_signal("move_to_details_view", app_id, is_installed)
		get_viewport().set_input_as_handled()

func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()
