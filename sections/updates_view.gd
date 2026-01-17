extends Control

signal image_load_requested(url: String, texture_rect: TextureRect)
signal focus_exited_up_from_lists()

@onready var update_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ListMarginContainer/UpdateListContainer
@onready var select_all_check_button: CheckBox = $MarginContainer/VBoxContainer/HeaderContainer/SelectAllContainer/CheckBoxPanel/SelectAllCheckBox
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

var audio_player: AudioStreamPlayer
var stream_select = preload("res://assets/nextprev.wav")
var stream_focus = preload("res://assets/change.mp3")

func _ready():
	print("UpdatesView: _ready called.")
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	if loading_overlay_scene:
		loading_overlay_instance = loading_overlay_scene.instantiate()
		add_child(loading_overlay_instance)
		loading_overlay_instance.visible = false
	
	if is_instance_valid(select_all_check_button):
		select_all_check_button.pressed.connect(_on_select_all_pressed)
		select_all_check_button.focus_entered.connect(_on_focus_entered)
	
	if is_instance_valid(refresh_button):
		refresh_button.pressed.connect(_on_refresh_pressed)
		refresh_button.focus_entered.connect(_on_focus_entered)
		
	if is_instance_valid(update_selected_button):
		update_selected_button.pressed.connect(_on_update_selected_pressed)
		update_selected_button.focus_entered.connect(_on_focus_entered)
		
	# Connect Sort Button signals
	if is_instance_valid(sort_option_button):
		sort_option_button.item_selected.connect(_on_sort_option_selected)
		sort_option_button.focus_entered.connect(_on_sort_focus_entered)
		sort_option_button.pressed.connect(_on_sort_pressed)
		
	# Manual Focus Neighbors for Header (Force Horizontal Flow)
	if is_instance_valid(select_all_check_button) and is_instance_valid(refresh_button):
		select_all_check_button.focus_neighbor_right = refresh_button.get_path()
		refresh_button.focus_neighbor_left = select_all_check_button.get_path()
		
	if is_instance_valid(refresh_button) and is_instance_valid(sort_option_button):
		refresh_button.focus_neighbor_right = sort_option_button.get_path()
		sort_option_button.focus_neighbor_left = refresh_button.get_path()
		
	if is_instance_valid(sort_option_button) and is_instance_valid(update_selected_button):
		sort_option_button.focus_neighbor_right = update_selected_button.get_path()
		update_selected_button.focus_neighbor_left = sort_option_button.get_path()
		
	# Initial Load
	_start_update_check()

func _on_focus_entered():
	if audio_player and stream_focus:
		audio_player.stream = stream_focus
		audio_player.play()

func on_view_entered():
	print("UpdatesView: on_view_entered called.")
	
	if not _initial_check_done:
		_initial_check_done = true
		_start_update_check()
		
	# Refocus logic if needed
	var focus_owner = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner) or not is_ancestor_of(focus_owner):
		if update_list_container.get_child_count() > 0:
			update_list_container.get_child(0).grab_focus()
		elif is_instance_valid(refresh_button):
			refresh_button.grab_focus()

func _start_update_check():
	print("UpdatesView: Starting update check...")
	if _update_check_thread != null and _update_check_thread.is_alive():
		print("UpdatesView: Update check thread already running.")
		return

	if is_instance_valid(loading_overlay_instance):
		loading_overlay_instance.show_overlay()
		
	_update_check_thread = Thread.new()
	_update_check_thread.start(_execute_update_check_in_thread)

func _execute_update_check_in_thread():
	print("UpdatesView (Thread): Executing flatpak commands via flatpak-spawn...")
	
	var spawn_cmd = "/usr/bin/flatpak-spawn"
	if not FileAccess.file_exists(spawn_cmd):
		print("UpdatesView (Error): flatpak-spawn not found!")
		call_deferred("_process_update_check_result", "")
		return

	# 1. Update AppStream metadata
	var host_cmd_metadata = "flatpak update --appstream"
	var args_metadata = ["--host", "sh", "-c", host_cmd_metadata]
	OS.execute(spawn_cmd, args_metadata, [], false) 

	# 2. Get list of remotes (Explicitly check user and system to support older flatpak versions)
	var remotes_info = [] # Array of Arrays [name, type]
	
	# Check User Remotes
	var cmd_user = "LC_ALL=C flatpak remotes --user --columns=name"
	var args_user = ["--host", "sh", "-c", cmd_user]
	var output_user = []
	OS.execute(spawn_cmd, args_user, output_user)
	
	if output_user.size() > 0:
		for line in output_user[0].strip_edges().split("\n"):
			line = line.strip_edges()
			if not line.is_empty():
				remotes_info.append([line, "user"])

	# Check System Remotes
	var cmd_sys = "LC_ALL=C flatpak remotes --system --columns=name"
	var args_sys = ["--host", "sh", "-c", cmd_sys]
	var output_sys = []
	OS.execute(spawn_cmd, args_sys, output_sys)
	
	if output_sys.size() > 0:
		for line in output_sys[0].strip_edges().split("\n"):
			line = line.strip_edges()
			if not line.is_empty():
				# Avoid duplicates if logic elsewhere is weird, but technically same name in different install is distinct.
				# We allow duplicates in the list because they have different types.
				remotes_info.append([line, "system"])
	
	print("UpdatesView (Thread): Found remotes with info: ", remotes_info)
	
	var accumulated_output = ""
	
	# 3. Query each remote precisely
	for info in remotes_info:
		var remote_name = info[0]
		var install_type = info[1] # "system" or "user"
		var type_flag = "--" + install_type
		
		var host_cmd_list = "LC_ALL=C flatpak remote-ls %s %s --updates --app --columns=application,name,version,download-size" % [type_flag, remote_name]
		var args_list = ["--host", "sh", "-c", host_cmd_list]
		var output_updates = []
		
		print("UpdatesView (Thread): Checking remote: ", remote_name, " (", install_type, ")")
		var exit_code = OS.execute(spawn_cmd, args_list, output_updates, true) 
		
		if output_updates.size() > 0:
			var output_str = output_updates[0]
			if exit_code == 0:
				accumulated_output += output_str + "\n"
			else:
				print("UpdatesView (Thread): Failed to check remote ", remote_name, " [", install_type, "] (Exit Code: ", exit_code, "). Output:\n", output_str)
		else:
			print("UpdatesView (Thread): Failed to check remote ", remote_name, " [", install_type, "] (No output, Exit Code: ", exit_code, ")")
	
	print("UpdatesView (Thread): Update check finished. Total result length: ", accumulated_output.length())
	call_deferred("_process_update_check_result", accumulated_output)

func _process_update_check_result(output: String):
	print("UpdatesView: Processing update check results...")
	if _update_check_thread:
		_update_check_thread.wait_to_finish()
		_update_check_thread = null

	if is_instance_valid(loading_overlay_instance):
		loading_overlay_instance.hide_overlay()

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
			
			# Clean size string: replace non-breaking space (or question marks) with space
			var size_str = raw_size.replace("?", " ").replace("\u00A0", " ").strip_edges()
			
			var old_version = "?"
			
			available_updates.append({
				"app_id": app_id,
				"name": app_name,
				"old_version": old_version,
				"new_version": new_version,
				"size": size_str,
				"icon": "" 
			})
			
			selected_app_ids.append(app_id)

	_populate_list()

func _populate_list():
	# Ensure sort button is focusable (fix for controller issue)
	if is_instance_valid(sort_option_button) and sort_option_button.focus_mode == Control.FOCUS_NONE:
		sort_option_button.focus_mode = Control.FOCUS_ALL

	if available_updates.is_empty():
		for child in update_list_container.get_children():
			child.queue_free()
		no_updates_label.visible = true
		update_selected_button.disabled = true
		select_all_check_button.disabled = true
		select_all_check_button.button_pressed = false
		return
	else:
		no_updates_label.visible = false
		select_all_check_button.disabled = false
		
	# Sorting Logic
	var sort_mode = 0
	if is_instance_valid(sort_option_button):
		sort_mode = sort_option_button.selected
	
	available_updates.sort_custom(func(a, b):
		if sort_mode == 2: # Size Descending (▼)
			var size_a = _parse_size(a.get("size", "0 B")).value_bytes
			var size_b = _parse_size(b.get("size", "0 B")).value_bytes
			return size_a > size_b
		elif sort_mode == 3: # Size Ascending (▲)
			var size_a = _parse_size(a.get("size", "0 B")).value_bytes
			var size_b = _parse_size(b.get("size", "0 B")).value_bytes
			return size_a < size_b
		elif sort_mode == 1: # Name Descending (Z-A, ▼)
			var name_a = a.get("name", "").to_lower()
			var name_b = b.get("name", "").to_lower()
			return name_a > name_b
		else: # Name Ascending (A-Z, ▲, Default 0)
			var name_a = a.get("name", "").to_lower()
			var name_b = b.get("name", "").to_lower()
			return name_a < name_b
	)
	
	# Check if we can reuse existing nodes
	var current_nodes = {}
	var children_to_remove = []
	
	for child in update_list_container.get_children():
		if "app_id" in child:
			current_nodes[child.app_id] = child
		else:
			children_to_remove.append(child)
			
	for child in children_to_remove:
		child.queue_free()
		
	# Check if set of IDs matches (for sorting vs refreshing)
	var new_ids = []
	for u in available_updates: new_ids.append(u.app_id)
	
	var can_reuse = true
	if current_nodes.size() != available_updates.size():
		can_reuse = false
	else:
		for id in new_ids:
			if not current_nodes.has(id):
				can_reuse = false
				break
	
	if can_reuse:
		print("UpdatesView: Reusing existing nodes for sort.")
		# Just reorder
		for i in range(available_updates.size()):
			var u = available_updates[i]
			var node = current_nodes[u.app_id]
			update_list_container.move_child(node, i)
	else:
		print("UpdatesView: Rebuilding list.")
		for child in update_list_container.get_children():
			child.queue_free()
			
		for update in available_updates:
			var item = update_item_scene.instantiate()
			update_list_container.add_child(item)
			
			var icon_url = ""
			item.setup(
				update.get("app_id"), 
				update.get("name"), 
				update.get("old_version"), 
				update.get("new_version"), 
				update.get("size"), 
				icon_url
			)
			item.selection_toggled.connect(_on_item_selection_toggled)
			item.image_load_requested.connect(func(url, rect): emit_signal("image_load_requested", url, rect))
			
			if selected_app_ids.has(update.get("app_id")):
				item.set_selected(true)

	_update_ui_state()

func _on_sort_option_selected(_index):
	if audio_player and stream_select:
		audio_player.stream = stream_select
		audio_player.play()
	_populate_list()

func _on_sort_focus_entered():
	if audio_player and stream_focus:
		audio_player.stream = stream_focus
		audio_player.play()

func _on_sort_pressed():
	if audio_player and stream_select:
		audio_player.stream = stream_select
		audio_player.play()

func _parse_size(size_str: String) -> Dictionary:
	var regex = RegEx.new()
	regex.compile("([0-9.,]+).*?([A-Za-z]+)") 
	
	var match_result = regex.search(size_str)
	if not match_result:
		return { "value_bytes": 0.0, "display_str": size_str }
		
	var val_str = match_result.get_string(1).replace(",", ".")
	var unit_str = match_result.get_string(2)
	
	var value = val_str.to_float()
	var unit = unit_str.to_upper()
	var bytes = 0.0
	
	match unit:
		"TB": bytes = value * 1024 * 1024 * 1024 * 1024
		"GB": bytes = value * 1024 * 1024 * 1024
		"MB": bytes = value * 1024 * 1024
		"KB", "K": bytes = value * 1024
		"B": bytes = value
		_: bytes = 0.0 
		
	return {
		"value_bytes": bytes,
		"display_str": "%s %s" % [val_str, unit_str]
	}

func _on_item_selection_toggled(app_id: String, is_selected: bool):
	if is_selected:
		if not selected_app_ids.has(app_id):
			selected_app_ids.append(app_id)
	else:
		selected_app_ids.erase(app_id)
	
	_update_ui_state()

func _update_ui_state():
	var total_items = available_updates.size()
	var selected_count = selected_app_ids.size()
	
	if total_items > 0:
		select_all_check_button.button_pressed = (selected_count == total_items)
	
	update_selected_button.disabled = (selected_count == 0)
	if selected_count > 0:
		update_selected_button.text = "Update Selected (%d)" % selected_count
	else:
		update_selected_button.text = "Update Selected"

func _on_select_all_pressed():
	if audio_player and stream_select: audio_player.play()
	
	var total_items = available_updates.size()
	var selected_count = selected_app_ids.size()
	var should_select_all = (selected_count < total_items)
	
	selected_app_ids.clear()
	if should_select_all:
		for update in available_updates:
			selected_app_ids.append(update.get("app_id"))
		
	for child in update_list_container.get_children():
		if child.has_method("set_selected"):
			child.set_selected(should_select_all)
			
	select_all_check_button.set_pressed_no_signal(should_select_all)
	_update_ui_state()

func _on_refresh_pressed():
	if audio_player and stream_select: audio_player.play()
	print("UpdatesView: Refresh requested.")
	_start_update_check()

func _on_update_selected_pressed():
	if audio_player and stream_select: audio_player.play()
	print("UpdatesView: Updating %d apps: %s" % [selected_app_ids.size(), selected_app_ids])
	
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		var dm = get_node_or_null("/root/DownloadManager")
		if dm:
			for app_id in selected_app_ids:
				dm.queue_install(app_id)
			
			update_selected_button.disabled = true
			update_selected_button.text = "Queued"
		else:
			printerr("UpdatesView: DownloadManager not found!")
	else:
		printerr("UpdatesView: Autoload setting not found!")

func update_internal_list_install_status(_installed_apps):
	pass