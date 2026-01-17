extends Control

signal image_load_requested(url: String, texture_rect: TextureRect)
signal focus_exited_up_from_lists()

@onready var update_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ListMarginContainer/UpdateListContainer
@onready var select_all_check_button: CheckBox = $MarginContainer/VBoxContainer/HeaderContainer/SelectAllContainer/CheckBoxPanel/SelectAllCheckBox
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/RefreshContainer/RefreshButton
@onready var update_selected_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/ActionContainer/UpdateSelectedButton
@onready var no_updates_label: Label = $MarginContainer/VBoxContainer/NoUpdatesLabel

var update_item_scene = preload("res://sections/update_item.tscn")
var loading_overlay_scene = preload("res://loading_overlay.tscn")
var available_updates: Array = [] 
var selected_app_ids: Array = []
var _update_check_thread: Thread = null
var loading_overlay_instance: Control = null
var _initial_check_done: bool = false

var audio_player: AudioStreamPlayer
var stream_select = preload("res://assets/select.mp3")
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
	
	if is_instance_valid(refresh_button):
		refresh_button.pressed.connect(_on_refresh_pressed)
		
	if is_instance_valid(update_selected_button):
		update_selected_button.pressed.connect(_on_update_selected_pressed)

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
			var size_str = parts[3].strip_edges()
			
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
	for child in update_list_container.get_children():
		child.queue_free()
	
	if available_updates.is_empty():
		no_updates_label.visible = true
		update_selected_button.disabled = true
		select_all_check_button.disabled = true
		select_all_check_button.button_pressed = false
		return
	else:
		no_updates_label.visible = false
		select_all_check_button.disabled = false
		
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
