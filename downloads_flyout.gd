extends CanvasLayer

signal closed
signal opened

@onready var color_rect = $ColorRect
@onready var flyout_panel = $FlyoutPanel
@onready var scroll_container = $FlyoutPanel/MarginContainer/VBoxContainer/ScrollContainer
@onready var queue_container = $FlyoutPanel/MarginContainer/VBoxContainer/ScrollContainer/QueueContainer
@onready var no_tasks_label = $FlyoutPanel/MarginContainer/VBoxContainer/NoTasksLabel

var _previous_focus_owner: Control = null
var _queue_timer: Timer

func _ready():
	hide()
	flyout_panel.position.x = get_viewport().get_visible_rect().size.x
	color_rect.modulate.a = 0
	
	_queue_timer = Timer.new()
	_queue_timer.wait_time = 0.5
	_queue_timer.timeout.connect(_update_queue)
	add_child(_queue_timer)

func open_flyout():
	if visible: return
	_previous_focus_owner = get_viewport().gui_get_focus_owner()
	show()
	emit_signal("opened")
	_update_queue()
	_queue_timer.start()
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(flyout_panel, "position:x", get_viewport().get_visible_rect().size.x - flyout_panel.size.x, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(color_rect, "modulate:a", 1.0, 0.2)
	
	_focus_first_item()

func close_flyout():
	if not visible: return
	_queue_timer.stop()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(flyout_panel, "position:x", get_viewport().get_visible_rect().size.x, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(color_rect, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(hide)
	
	if is_instance_valid(_previous_focus_owner):
		_previous_focus_owner.grab_focus()
	emit_signal("closed")

func _update_queue():
	var DownloadManager = get_node_or_null("/root/DownloadManager")
	if not DownloadManager: return
	
	var active_tasks = DownloadManager.running_tasks
	var active_safe_ids = []
	for op_id in active_tasks.keys():
		active_safe_ids.append(op_id.replace(".", "_"))
	
	# Clean up removed tasks
	for child in queue_container.get_children():
		if not active_safe_ids.has(child.name):
			child.queue_free()
			
	var has_tasks = active_tasks.size() > 0
	no_tasks_label.visible = not has_tasks
	scroll_container.visible = has_tasks
	
	if not has_tasks and visible:
		no_tasks_label.focus_mode = Control.FOCUS_ALL
		no_tasks_label.grab_focus()
	
	for operation_id in active_tasks:
		var task = active_tasks[operation_id]
		var safe_op_id = operation_id.replace(".", "_")
		var actual_app_id = task.get("app_id", "")
		var task_btn = queue_container.get_node_or_null(safe_op_id)
		if not task_btn:
			task_btn = Button.new()
			task_btn.name = safe_op_id
			
			task_btn.custom_minimum_size = Vector2(0, 60)
			
			var vbox = VBoxContainer.new()
			vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
			vbox.set_offsets_preset(Control.PRESET_FULL_RECT)
			vbox.add_theme_constant_override("separation", 2)
			
			var name_lbl = Label.new()
			name_lbl.name = "NameLabel"
			name_lbl.add_theme_font_size_override("font_size", 16)
			name_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			name_lbl.text = "Loading..."
			vbox.add_child(name_lbl)
			
			var status_hbox = HBoxContainer.new()
			var pbar = ProgressBar.new()
			pbar.name = "ProgressBar"
			pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pbar.custom_minimum_size = Vector2(0, 15)
			pbar.show_percentage = false
			status_hbox.add_child(pbar)
			
			var status_lbl = Label.new()
			status_lbl.name = "StatusLabel"
			status_lbl.add_theme_font_size_override("font_size", 14)
			status_lbl.text = "0% - Pending"
			status_hbox.add_child(status_lbl)
			
			vbox.add_child(status_hbox)
			task_btn.add_child(vbox)
			
			task_btn.pressed.connect(_on_task_selected.bind(actual_app_id))
			queue_container.add_child(task_btn)
			
		var vbox = task_btn.get_child(0)
		var name_lbl = vbox.get_node("NameLabel") as Label
		var status_hbox = vbox.get_child(1)
		var pbar = status_hbox.get_node("ProgressBar") as ProgressBar
		var status_lbl = status_hbox.get_node("StatusLabel") as Label
		
		var app_data = task.get("app_data")
		if typeof(app_data) != TYPE_DICTIONARY:
			app_data = {}
		var status_data = task.get("status_data")
		if typeof(status_data) != TYPE_DICTIONARY:
			status_data = {}
			
		name_lbl.text = app_data.get("name", status_data.get("name", actual_app_id))
		pbar.value = status_data.get("progress", 0)
		var status_text = status_data.get("status", "pending")
		if status_text == "pending": status_text = "In Queue"
		status_lbl.text = str(status_data.get("progress", 0)) + "% - " + status_text.capitalize()

func _focus_first_item():
	if queue_container.get_child_count() > 0:
		queue_container.get_child(0).grab_focus()

func _unhandled_input(event: InputEvent):
	if visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_downloads"):
			close_flyout()
			get_viewport().set_input_as_handled()

func _on_task_selected(actual_app_id: String):
	var main_node = get_node_or_null("/root/App")
	if main_node and main_node.has_method("_on_move_to_details_view"):
		main_node._on_move_to_details_view(actual_app_id, main_node.is_app_installed(actual_app_id))
		close_flyout()
