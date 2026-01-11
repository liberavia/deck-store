extends Control

signal move_to_details_view_requested(app_id: String, installed: bool)
signal focus_exited_up_from_lists()

@onready var app_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/AppListContainer
@onready var total_size_label: Label = $MarginContainer/VBoxContainer/HeaderContainer/TotalSizeLabel
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer

var installed_app_item_scene = preload("res://sections/installed_app_item.tscn")

func _ready():
	# Initial populate if data is already available
	var main_node = get_node_or_null("/root/App")
	if main_node and main_node.has_method("get_installed_ids"):
		update_internal_list_install_status(main_node.get_installed_ids())

func on_view_entered():
	# Refresh list when entering the view
	var main_node = get_node_or_null("/root/App")
	if main_node and main_node.has_method("get_installed_ids"):
		update_internal_list_install_status(main_node.get_installed_ids())

	# Focus first element if nothing focused
	var focus_owner = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner) or not is_ancestor_of(focus_owner):
		focus_first_element()

func update_internal_list_install_status(installed_apps: Dictionary):
	_populate_list(installed_apps)

func _populate_list(installed_apps: Dictionary):
	# Clear existing
	for child in app_list_container.get_children():
		child.queue_free()
	
	var app_ids = installed_apps.keys()
	# Sort alphabetically by Name
	app_ids.sort_custom(func(a, b):
		var name_a = installed_apps[a].get("name", a).to_lower()
		var name_b = installed_apps[b].get("name", b).to_lower()
		return name_a < name_b
	)
	
	var total_bytes: float = 0.0
	
	for app_id in app_ids:
		var info = installed_apps[app_id]
		var app_name = info.get("name", app_id)
		var raw_size_str = info.get("size", "0 B")
		
		var parsed_size = _parse_size(raw_size_str)
		total_bytes += parsed_size.value_bytes
		
		# Use cleaned string for display (e.g. "450.3 MB")
		var display_size_str = parsed_size.display_str
		if display_size_str.is_empty(): display_size_str = raw_size_str # Fallback
		
		var item = installed_app_item_scene.instantiate()
		app_list_container.add_child(item)
		item.setup(app_id, app_name, display_size_str)
		item.item_pressed.connect(_on_item_pressed)
		
	# Update Total Size Label
	total_size_label.text = "Total Size: %s" % _format_size(total_bytes)

func _on_item_pressed(app_id: String):
	emit_signal("move_to_details_view_requested", app_id, true)

func _parse_size(size_str: String) -> Dictionary:
	# Returns { "value_bytes": float, "display_str": String }
	
	# Regex to capture number and unit, ignoring potential garbage in between
	var regex = RegEx.new()
	regex.compile("([0-9.,]+).*?([A-Za-z]+)") 
	
	var match_result = regex.search(size_str)
	if not match_result:
		return { "value_bytes": 0.0, "display_str": size_str }
		
	var val_str = match_result.get_string(1).replace(",", ".") # Ensure dot decimal
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
		_: bytes = 0.0 # Unknown unit
		
	return {
		"value_bytes": bytes,
		"display_str": "%s %s" % [val_str, unit_str] # Clean formatted string
	}

func _format_size(size_bytes: float) -> String:
	if size_bytes >= 1024 * 1024 * 1024:
		return "%.1f GB" % (size_bytes / (1024 * 1024 * 1024))
	elif size_bytes >= 1024 * 1024:
		return "%.1f MB" % (size_bytes / (1024 * 1024))
	elif size_bytes >= 1024:
		return "%.1f kB" % (size_bytes / 1024)
	else:
		return "%d B" % size_bytes

func focus_first_element():
	if app_list_container.get_child_count() > 0:
		var first = app_list_container.get_child(0)
		if first is Control:
			first.grab_focus()

func _unhandled_input(event):
	if event.is_action_pressed("ui_up"):
		var focus_owner = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus_owner) and app_list_container.is_ancestor_of(focus_owner):
			if focus_owner.get_index() == 0:
				emit_signal("focus_exited_up_from_lists")
				get_viewport().set_input_as_handled()