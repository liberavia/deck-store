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
	tween.chain().tween_callback(_on_flyout_hidden)
	
	if is_instance_valid(_previous_focus_owner):
		_previous_focus_owner.grab_focus()

func _on_flyout_hidden():
	hide()
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
			
			task_btn.custom_minimum_size = Vector2(0, 90)
			
			var style_normal = StyleBoxFlat.new()
			style_normal.bg_color = Color(0.1, 0.1, 0.1, 0.8)
			style_normal.set_corner_radius_all(8)
			style_normal.content_margin_left = 10
			style_normal.content_margin_top = 10
			style_normal.content_margin_right = 10
			style_normal.content_margin_bottom = 10
			
			var style_focus = style_normal.duplicate()
			style_focus.border_color = Color.PURPLE
			style_focus.border_width_left = 2
			style_focus.border_width_top = 2
			style_focus.border_width_right = 2
			style_focus.border_width_bottom = 2
			
			task_btn.add_theme_stylebox_override("normal", style_normal)
			task_btn.add_theme_stylebox_override("focus", style_focus)
			task_btn.add_theme_stylebox_override("hover", style_focus)
			task_btn.add_theme_stylebox_override("pressed", style_focus)
			
			var main_hbox = HBoxContainer.new()
			main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
			main_hbox.offset_left = 10
			main_hbox.offset_top = 10
			main_hbox.offset_right = -10
			main_hbox.offset_bottom = -10
			main_hbox.add_theme_constant_override("separation", 15)
			main_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			var icon_rect = TextureRect.new()
			icon_rect.name = "IconRect"
			icon_rect.custom_minimum_size = Vector2(50, 50)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			main_hbox.add_child(icon_rect)
			
			var vbox = VBoxContainer.new()
			vbox.name = "VBoxContainer"
			vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_theme_constant_override("separation", 2)
			vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			var name_lbl = Label.new()
			name_lbl.name = "NameLabel"
			name_lbl.add_theme_font_size_override("font_size", 16)
			name_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			name_lbl.text = tr("LBL_LOADING")
			vbox.add_child(name_lbl)
			
			var status_vbox = VBoxContainer.new()
			status_vbox.name = "StatusVBox"
			status_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pbar = ProgressBar.new()
			pbar.name = "ProgressBar"
			pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pbar.custom_minimum_size = Vector2(0, 15)
			pbar.show_percentage = false
			pbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			var pb_style = StyleBoxFlat.new()
			pb_style.bg_color = Color(0.627, 0.125, 0.941, 1.0)
			pbar.add_theme_stylebox_override("fill", pb_style)
			
			status_vbox.add_child(pbar)
			
			var status_lbl = Label.new()
			status_lbl.name = "StatusLabel"
			status_lbl.add_theme_font_size_override("font_size", 14)
			status_lbl.text = "0% - " + tr("LBL_PENDING")
			status_vbox.add_child(status_lbl)
			
			vbox.add_child(status_vbox)
			main_hbox.add_child(vbox)
			task_btn.add_child(main_hbox)
			
			task_btn.pressed.connect(_on_task_selected.bind(actual_app_id))
			queue_container.add_child(task_btn)
			
			var app_data = task.get("app_data", {})
			var icon_url = app_data.get("icon", app_data.get("icon_url", task.get("status_data", {}).get("icon_url", "")))
			if icon_url != "":
				var main_app = get_node_or_null("/root/App")
				if main_app and main_app.has_method("_on_product_list_image_load_requested"):
					main_app._on_product_list_image_load_requested(icon_url, icon_rect)
			
		var main_hbox = task_btn.get_child(0)
		var vbox = main_hbox.get_node("VBoxContainer")
		var name_lbl = vbox.get_node("NameLabel") as Label
		var status_vbox = vbox.get_node("StatusVBox")
		var pbar = status_vbox.get_node("ProgressBar") as ProgressBar
		var status_lbl = status_vbox.get_node("StatusLabel") as Label
		
		var app_data = task.get("app_data")
		if typeof(app_data) != TYPE_DICTIONARY:
			app_data = {}
		var status_data = task.get("status_data")
		if typeof(status_data) != TYPE_DICTIONARY:
			status_data = {}
			
		name_lbl.text = app_data.get("name", status_data.get("name", actual_app_id))
		pbar.value = status_data.get("progress", 0)
		var status_text = status_data.get("status", "pending")
		if status_text == "pending": status_text = tr("LBL_IN_QUEUE")
		elif status_text == "downloading": status_text = tr("LBL_DOWNLOADING_SHORT")
		elif status_text == "installing": status_text = tr("LBL_INSTALLING")
		elif status_text == "completed": status_text = tr("LBL_COMPLETED")
		status_lbl.text = str(status_data.get("progress", 0)) + "% - " + status_text

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
