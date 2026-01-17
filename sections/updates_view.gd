extends Control

signal image_load_requested(url: String, texture_rect: TextureRect)
signal focus_exited_up_from_lists()

@onready var update_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ListMarginContainer/UpdateListContainer
@onready var select_all_check_button: CheckBox = $MarginContainer/VBoxContainer/HeaderContainer/SelectAllContainer/CheckBoxPanel/SelectAllCheckBox
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/RefreshContainer/RefreshButton
@onready var update_selected_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/ActionContainer/UpdateSelectedButton
@onready var no_updates_label: Label = $MarginContainer/VBoxContainer/NoUpdatesLabel

var update_item_scene = preload("res://sections/update_item.tscn")
var available_updates: Array = [] # List of Dictionaries {app_id, name, old_version, new_version, size, icon}
var selected_app_ids: Array = []

var audio_player: AudioStreamPlayer
var stream_select = preload("res://assets/select.mp3")
var stream_focus = preload("res://assets/change.mp3")

func _ready():
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	if is_instance_valid(select_all_check_button):
		select_all_check_button.pressed.connect(_on_select_all_pressed)
	
	if is_instance_valid(refresh_button):
		refresh_button.pressed.connect(_on_refresh_pressed)
		
	if is_instance_valid(update_selected_button):
		update_selected_button.pressed.connect(_on_update_selected_pressed)
		
	# Initial Load (Mock or Real)
	_load_updates()

func on_view_entered():
	# Refocus logic if needed
	var focus_owner = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner) or not is_ancestor_of(focus_owner):
		if update_list_container.get_child_count() > 0:
			update_list_container.get_child(0).grab_focus()
		elif is_instance_valid(refresh_button):
			refresh_button.grab_focus()

func _load_updates():
	# Placeholder: Fetch updates from a manager or API
	# For now, let's pretend we have no updates or mock some if needed for testing.
	# available_updates = _fetch_mock_updates() 
	available_updates = [] # Start empty
	_populate_list()

func _fetch_mock_updates() -> Array:
	return [
		{
			"app_id": "com.example.app1",
			"name": "Example App 1",
			"old_version": "1.0",
			"new_version": "1.2",
			"size": "150 MB",
			"icon": "https://dl.flathub.org/repo/appstream/x86_64/icons/128x128/com.discordapp.Discord.png"
		},
		{
			"app_id": "com.example.app2",
			"name": "Example App 2",
			"old_version": "2.1",
			"new_version": "3.0",
			"size": "500 MB",
			"icon": ""
		}
	]

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
		item.setup(
			update.get("app_id"), 
			update.get("name"), 
			update.get("old_version"), 
			update.get("new_version"), 
			update.get("size"), 
			update.get("icon", "")
		)
		item.selection_toggled.connect(_on_item_selection_toggled)
		item.image_load_requested.connect(func(url, rect): emit_signal("image_load_requested", url, rect))
		
		# Restore selection if it was in our list
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
	
	# Update Select All Checkbox state
	if total_items > 0:
		if selected_count == total_items:
			select_all_check_button.button_pressed = true
			# We might want a "mixed" state visual if CheckBox supported it easily, 
			# but typically CheckBox in Godot is binary unless we use icons.
			# For simple UX: Unchecked if not ALL are selected is common, 
			# OR Unchecked if NONE, Checked if ALL, Mixed if SOME.
			# Let's stick to: Checked = All selected. Unchecked = Not all selected.
		else:
			select_all_check_button.button_pressed = false
	
	# Update Action Button
	update_selected_button.disabled = (selected_count == 0)
	if selected_count > 0:
		update_selected_button.text = "Update Selected (%d)" % selected_count
	else:
		update_selected_button.text = "Update Selected"

func _on_select_all_pressed():
	if audio_player and stream_select: audio_player.play()
	
	# Logic:
	# If currently ALL are selected -> Deselect All
	# If currently NONE or SOME are selected -> Select All
	
	var total_items = available_updates.size()
	var selected_count = selected_app_ids.size()
	
	var should_select_all = (selected_count < total_items)
	
	selected_app_ids.clear()
	
	if should_select_all:
		for update in available_updates:
			selected_app_ids.append(update.get("app_id"))
			
	# Update all items visual state
	for child in update_list_container.get_children():
		if child.has_method("set_selected"):
			child.set_selected(should_select_all)
			
	# Manually update the checkbox visual because we intercepted the signal logic
	select_all_check_button.set_pressed_no_signal(should_select_all)
	
	_update_ui_state()

func _on_refresh_pressed():
	if audio_player and stream_select: audio_player.play()
	# Trigger refresh logic here
	print("UpdatesView: Refresh requested.")
	# _load_updates() # In real impl, this would call an external service

func _on_update_selected_pressed():
	if audio_player and stream_select: audio_player.play()
	print("UpdatesView: Updating %d apps: %s" % [selected_app_ids.size(), selected_app_ids])
	# Trigger update calls to DownloadManager

func update_internal_list_install_status(_installed_apps):
	# Updates view might not need installed list directly, but maybe to verify if update is valid
	pass
