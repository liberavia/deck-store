extends Control

signal image_load_requested(url: String, texture_rect: TextureRect)
signal focus_exited_up_from_lists()

@onready var update_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ListMarginContainer/UpdateListContainer
@onready var select_all_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/SelectAllButton
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/RefreshContainer/RefreshButton
@onready var update_selected_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/ActionContainer/UpdateSelectedButton
@onready var no_updates_label: Label = $MarginContainer/VBoxContainer/NoUpdatesLabel
@onready var sort_option_button: OptionButton = $MarginContainer/VBoxContainer/HeaderContainer/SortOptionButton

var update_item_scene = preload("res://sections/update_item.tscn")
var loading_overlay_scene = preload("res://loading_overlay.tscn")
var available_updates: Array = [] 
var selected_app_ids: Array = []
var _update_check_thread: Thread = null
var loading_overlay_instance: Control = null
var _initial_check_done: bool = false
var is_updating: bool = false

var audio_player: AudioStreamPlayer
var stream_select = preload("res://assets/nextprev.wav")
var stream_focus = preload("res://assets/change.mp3")

# Styles for Update Button
var stylebox_install: StyleBoxFlat
var stylebox_cancel: StyleBoxFlat
var stylebox_normal: StyleBoxFlat

func _ready():
	print("UpdatesView: _ready called.")
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	if loading_overlay_scene:
		loading_overlay_instance = loading_overlay_scene.instantiate()
		add_child(loading_overlay_instance)
		loading_overlay_instance.visible = false
	
	_setup_styles()
	
	if is_instance_valid(select_all_button):
		select_all_button.pressed.connect(_on_select_all_pressed)
		select_all_button.focus_entered.connect(_on_focus_entered)
	
	if is_instance_valid(refresh_button):
		refresh_button.pressed.connect(_on_refresh_pressed)
		refresh_button.focus_entered.connect(_on_focus_entered)
		
	if is_instance_valid(update_selected_button):
		update_selected_button.pressed.connect(_on_update_selected_pressed)
		update_selected_button.focus_entered.connect(_on_focus_entered)
		
	if is_instance_valid(sort_option_button):
		sort_option_button.item_selected.connect(_on_sort_option_selected)
		sort_option_button.focus_entered.connect(_on_focus_entered)
		sort_option_button.pressed.connect(_on_sort_pressed)
		
	# Manual Focus Neighbors
	if is_instance_valid(select_all_button) and is_instance_valid(refresh_button):
		select_all_button.focus_neighbor_right = refresh_button.get_path()
		refresh_button.focus_neighbor_left = select_all_button.get_path()
		
	if is_instance_valid(refresh_button) and is_instance_valid(sort_option_button):
		refresh_button.focus_neighbor_right = sort_option_button.get_path()
		sort_option_button.focus_neighbor_left = refresh_button.get_path()
		
	if is_instance_valid(sort_option_button) and is_instance_valid(update_selected_button):
		sort_option_button.focus_neighbor_right = update_selected_button.get_path()
		update_selected_button.focus_neighbor_left = sort_option_button.get_path()

	# Connect DownloadManager signals
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		if DownloadManager.has_signal("task_updated"):
			DownloadManager.task_updated.connect(_on_task_updated)
		if DownloadManager.has_signal("task_finished"):
			DownloadManager.task_finished.connect(_on_task_finished)

func _setup_styles():
	if update_selected_button:
		var base_style = update_selected_button.get_theme_stylebox("normal")
		if base_style is StyleBoxFlat:
			stylebox_normal = base_style.duplicate()
		else:
			stylebox_normal = StyleBoxFlat.new()
			stylebox_normal.bg_color = Color(0, 0, 0, 0.35)
			stylebox_normal.border_color = Color(1,1,1,1)
			stylebox_normal.set_border_width_all(1)
		
		stylebox_install = stylebox_normal.duplicate()
		stylebox_install.bg_color = Color.from_string("#245322", Color.GREEN) # Green
		
		stylebox_cancel = stylebox_normal.duplicate()
		stylebox_cancel.bg_color = Color.from_string("#5c0001", Color.RED) # Red
		
		_update_button_style()

func on_view_entered():
	print("UpdatesView: on_view_entered called.")
	
	if not _initial_check_done:
		_initial_check_done = true
		_start_update_check()
		
	var focus_owner = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner) or not is_ancestor_of(focus_owner):
		if update_list_container.get_child_count() > 0:
			update_list_container.get_child(0).grab_focus()
		elif is_instance_valid(refresh_button):
			refresh_button.grab_focus()

func _on_focus_entered():
	if audio_player and stream_focus:
		audio_player.stream = stream_focus
		audio_player.play()

func _on_sort_pressed():
	if audio_player and stream_select:
		audio_player.stream = stream_select
		audio_player.play()

func _start_update_check():
	if _update_check_thread != null and _update_check_thread.is_alive():
		return

	if is_instance_valid(loading_overlay_instance):
		loading_overlay_instance.show_overlay()
		
	_update_check_thread = Thread.new()
	_update_check_thread.start(_execute_update_check_in_thread)

func _execute_update_check_in_thread():
	var spawn_cmd = "/usr/bin/flatpak-spawn"
	if not FileAccess.file_exists(spawn_cmd):
		call_deferred("_process_update_check_result", "")
		return

	# 1. AppStream
	var host_cmd_metadata = "flatpak update --appstream"
	var args_metadata = ["--host", "sh", "-c", host_cmd_metadata]
	OS.execute(spawn_cmd, args_metadata, [], false)

	# 2. Remotes
	var remotes_info = [] 
	# Check User
	var cmd_user = "LC_ALL=C flatpak remotes --user --columns=name"
	var output_user = []
	OS.execute(spawn_cmd, ["--host", "sh", "-c", cmd_user], output_user)
	if output_user.size() > 0:
		for line in output_user[0].strip_edges().split("\n"):
			line = line.strip_edges()
			if not line.is_empty(): remotes_info.append(line)
	
	var accumulated_output = ""
	
	# 3. Query
	for remote_name in remotes_info:
		var host_cmd_list = "LC_ALL=C flatpak remote-ls --user %s --updates --app --columns=application,name,version,download-size" % [remote_name]
		var output_updates = []
		var exit_code = OS.execute(spawn_cmd, ["--host", "sh", "-c", host_cmd_list], output_updates, true) 
		
		if exit_code == 0 and output_updates.size() > 0:
			accumulated_output += output_updates[0] + "\n"
	
	call_deferred("_process_update_check_result", accumulated_output)

func _process_update_check_result(output: String):
	if _update_check_thread:
		_update_check_thread.wait_to_finish()
		_update_check_thread = null

	if is_instance_valid(loading_overlay_instance):
		loading_overlay_instance.hide_overlay()

	var old_selected = selected_app_ids.duplicate()
	var is_first_run = available_updates.is_empty()
	
	available_updates.clear()
	selected_app_ids.clear()
	
	var lines = output.strip_edges().split("\n")
	for line in lines:
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("error:"): continue
		
		var parts = line.split("\t")
		if parts.size() >= 4:
			var app_id = parts[0].strip_edges()
			var app_name = parts[1].strip_edges()
			var new_version = parts[2].strip_edges()
			var raw_size = parts[3].strip_edges()
			var size_str = raw_size.replace("?", " ").replace("\u00A0", " ").strip_edges()
			
			var exists = false
			for u in available_updates:
				if u.app_id == app_id: exists = true; break
			
			if not exists:
				available_updates.append({
					"app_id": app_id,
					"name": app_name,
					"old_version": "?",
					"new_version": new_version,
					"size": size_str,
					"icon": "",
					"installation": "user"
				})
				
				# Preserve selection or select all on first run
				if is_first_run or old_selected.has(app_id):
					selected_app_ids.append(app_id)

	_populate_list()

func _populate_list():
	# Ensure sort button is focusable
	if is_instance_valid(sort_option_button) and sort_option_button.focus_mode == Control.FOCUS_NONE:
		sort_option_button.focus_mode = Control.FOCUS_ALL

	if available_updates.is_empty():
		for child in update_list_container.get_children(): child.queue_free()
		no_updates_label.visible = true
		update_selected_button.disabled = true
		return
	else:
		no_updates_label.visible = false
		
	var sort_mode = 0
	if is_instance_valid(sort_option_button): sort_mode = sort_option_button.selected
	
	available_updates.sort_custom(func(a, b):
		if sort_mode == 2: return _parse_size(a.get("size", "0 B")).value_bytes > _parse_size(b.get("size", "0 B")).value_bytes
		elif sort_mode == 3: return _parse_size(a.get("size", "0 B")).value_bytes < _parse_size(b.get("size", "0 B")).value_bytes
		elif sort_mode == 1: return a.get("name", "").to_lower() > b.get("name", "").to_lower()
		else: return a.get("name", "").to_lower() < b.get("name", "").to_lower()
	)
	
	# Reuse logic
	var current_nodes = {}
	var children_to_remove = []
	for child in update_list_container.get_children():
		if "app_id" in child: current_nodes[child.app_id] = child
		else: children_to_remove.append(child)
	for child in children_to_remove: child.queue_free()
		
	var new_ids = []
	for u in available_updates: new_ids.append(u.app_id)
	
	var can_reuse = true
	if current_nodes.size() != available_updates.size(): can_reuse = false
	else:
		for id in new_ids: if not current_nodes.has(id): can_reuse = false; break
	
	if can_reuse:
		for i in range(available_updates.size()):
			var u = available_updates[i]
			var node = current_nodes[u.app_id]
			update_list_container.move_child(node, i)
			if node.has_method("set_selected"):
				node.set_selected(selected_app_ids.has(u.app_id))
	else:
		for child in update_list_container.get_children(): child.queue_free()
		for update in available_updates:
			var item = update_item_scene.instantiate()
			update_list_container.add_child(item)
			item.setup(update.app_id, update.name, update.old_version, update.new_version, update.size, update.icon)
			item.selection_toggled.connect(_on_item_selection_toggled)
			item.image_load_requested.connect(func(url, rect): emit_signal("image_load_requested", url, rect))
			if selected_app_ids.has(update.app_id): item.set_selected(true)

	_update_ui_state()

func _parse_size(size_str: String) -> Dictionary:
	var regex = RegEx.new(); regex.compile("([0-9.,]+).*?([A-Za-z]+)") 
	var match_result = regex.search(size_str)
	if not match_result: return { "value_bytes": 0.0, "display_str": size_str }
	var val = match_result.get_string(1).replace(",", ".").to_float()
	var unit = match_result.get_string(2).to_upper()
	var bytes = 0.0
	match unit:
		"TB": bytes = val * 1024 * 1024 * 1024 * 1024
		"GB": bytes = val * 1024 * 1024 * 1024
		"MB": bytes = val * 1024 * 1024
		"KB", "K": bytes = val * 1024
		"B": bytes = val
	return { "value_bytes": bytes, "display_str": size_str }

func _on_item_selection_toggled(app_id: String, is_selected: bool):
	if is_selected:
		if not selected_app_ids.has(app_id): selected_app_ids.append(app_id)
	else:
		selected_app_ids.erase(app_id)
	_update_ui_state()

func _update_ui_state():
	if is_updating:
		select_all_button.disabled = true
		refresh_button.disabled = true
		sort_option_button.disabled = true
		
		# Disable all checkboxes
		for child in update_list_container.get_children():
			if child.has_node("MarginContainer/HBoxContainer/CheckBox"):
				child.get_node("MarginContainer/HBoxContainer/CheckBox").disabled = true
			
		_update_button_style()
		update_selected_button.text = "Cancel Update"
		update_selected_button.disabled = false
		return

	# Normal State
	select_all_button.disabled = false
	refresh_button.disabled = false
	sort_option_button.disabled = false
	
	for child in update_list_container.get_children():
		if child.has_node("MarginContainer/HBoxContainer/CheckBox"):
			child.get_node("MarginContainer/HBoxContainer/CheckBox").disabled = false

	var total_items = available_updates.size()
	var selected_count = selected_app_ids.size()
	
	if total_items > 0:
		if selected_count == total_items:
			select_all_button.text = "Deselect All"
		else:
			select_all_button.text = "Select All"
	else:
		select_all_button.text = "Select All"
		select_all_button.disabled = true
	
	update_selected_button.disabled = (selected_count == 0)
	if selected_count > 0: update_selected_button.text = "Update Selected (%d)" % selected_count
	else: update_selected_button.text = "Update Selected"
	
	_update_button_style()

func _update_button_style():
	if not is_instance_valid(update_selected_button): return
	
	if is_updating:
		update_selected_button.add_theme_stylebox_override("normal", stylebox_cancel)
		update_selected_button.add_theme_stylebox_override("hover", stylebox_cancel)
		update_selected_button.add_theme_stylebox_override("pressed", stylebox_cancel)
	else:
		update_selected_button.add_theme_stylebox_override("normal", stylebox_install)
		update_selected_button.add_theme_stylebox_override("hover", stylebox_install)
		update_selected_button.add_theme_stylebox_override("pressed", stylebox_install)

func _on_select_all_pressed():
	if is_updating: return
	if audio_player and stream_select: audio_player.play()
	var total_items = available_updates.size()
	var selected_count = selected_app_ids.size()
	
	var should_select_all = (selected_count < total_items)
	
	selected_app_ids.clear()
	if should_select_all:
		for update in available_updates:
			selected_app_ids.append(update.app_id)
			
	for child in update_list_container.get_children():
		if child.has_method("set_selected"):
			child.set_selected(should_select_all)
			
	_update_ui_state()

func _on_refresh_pressed():
	if is_updating: return
	if audio_player and stream_select: audio_player.play()
	_start_update_check()

func _on_sort_option_selected(_index):
	if is_updating: return
	if audio_player and stream_select: audio_player.play()
	_populate_list()

func _on_sort_focus_entered():
	if audio_player and stream_focus: audio_player.play()

func _on_update_selected_pressed():
	if audio_player and stream_select: audio_player.play()
	
	if is_updating:
		_cancel_updates()
	else:
		_start_updates()

func _start_updates():
	if selected_app_ids.is_empty(): return
	
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		var dm = get_node_or_null("/root/DownloadManager")
		if dm:
			is_updating = true
			_update_ui_state()
			for app_id in selected_app_ids:
				# Prepare item UI
				var item = _find_item_by_id(app_id)
				if item: item.set_progress(0, "Queued")
				
				# Find the update data to pass installation scope
				var update_data = {}
				for u in available_updates:
					if u.app_id == app_id:
						update_data = u
						break
				
				dm.queue_update(app_id, update_data)
		else:
			printerr("UpdatesView: DownloadManager not found!")
	else:
		printerr("UpdatesView: Autoload setting not found!")

func _cancel_updates():
	# Cancel all queued/running operations for selected apps
	# We iterate backwards through our selected list or ask DownloadManager?
	# DownloadManager.cancel_operation(op_id). We need OpID.
	# We don't store OpIDs here easily.
	# But DownloadManager has get_task_status(app_id) which has 'operation_id'.
	
	var dm = get_node_or_null("/root/DownloadManager")
	if dm:
		for app_id in selected_app_ids:
			var status = dm.get_task_status(app_id)
			if status.has("operation_id"):
				dm.cancel_operation(status.operation_id)
	
	# We rely on task_finished signals to reset state, 
	# OR we force state reset if we want immediate feedback.
	# Usually task_finished comes back with "cancelled".

func _find_item_by_id(app_id: String) -> Control:
	for child in update_list_container.get_children():
		if "app_id" in child and child.app_id == app_id:
			return child
	return null

func _on_task_updated(operation_id: String, status_data: Dictionary):
	if not is_updating: return
	var app_id = status_data.get("app_id")
	if not app_id in selected_app_ids: return
	
	var item = _find_item_by_id(app_id)
	var status = status_data.get("status")
	var progress = status_data.get("progress")
	if progress == null: progress = 0.0
	else: progress = float(progress)
	
	if status == "completed":
		print("UpdatesView: Update completed for ", app_id)
		# Remove from internal lists
		selected_app_ids.erase(app_id)
		for i in range(available_updates.size()):
			if available_updates[i].app_id == app_id:
				available_updates.remove_at(i)
				break
		# Remove UI Node
		if item: item.queue_free()
		
		# Check if done
		_check_all_updates_finished()
		
	elif status == "failed" or status == "cancelled":
		print("UpdatesView: Update ", status, " for ", app_id)
		if item: 
			item.reset_progress()
			# Optionally show error? status_data.get("error")
		# We don't remove failed items, user might try again.
		# But we should consider them "done" for this batch process?
		# If we keep is_updating = true, user can't select others.
		# If failed, we should probably just stop tracking it as "active".
		# But we queue all at once.
		# Let's keep them in selected_app_ids but maybe mark as not running?
		# Actually, if we cancel, we stop updating.
		pass
		
	else:
		if item:
			var msg = ""
			match status:
				"queued": msg = "Queued"
				"preparing": msg = "Preparing..."
				"downloading": 
					msg = "Downloading (%d%%)" % progress
					var speed = status_data.get("speed")
					if speed: msg += " (%s)" % speed
				"installing": msg = "Installing..."
			item.set_progress(progress, msg)

func _on_task_finished(operation_id: String, final_status: String, operation_type: String):
	# Fallback if task_updated didn't catch final state or for cleanup
	# We mostly handled it in _on_task_updated via status checks
	# But let's check if we are completely idle now
	_check_all_updates_finished()

func _check_all_updates_finished():
	if not is_updating: return
	
	# Check if DownloadManager has any running tasks for our selected apps
	var any_running = false
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		var dm = get_node_or_null("/root/DownloadManager")
		if dm:
			for app_id in selected_app_ids:
				var status = dm.get_task_status(app_id)
				var s = status.get("status")
				if s != null and not ["completed", "failed", "cancelled"].has(s):
					any_running = true
					break
	
	if not any_running:
		print("UpdatesView: All batch updates finished.")
		is_updating = false
		_update_ui_state()

func _unhandled_input(event):
	if event.is_action_pressed("go_back"):
		var focus_owner = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus_owner):
			# Check if focus is in list or on header buttons
			if update_list_container.is_ancestor_of(focus_owner) or \
			   focus_owner == select_all_button or \
			   focus_owner == refresh_button or \
			   focus_owner == sort_option_button or \
			   focus_owner == update_selected_button:
				
				emit_signal("focus_exited_up_from_lists")
				get_viewport().set_input_as_handled()
