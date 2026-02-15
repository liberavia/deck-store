extends Control

signal move_to_details_view_requested(app_id: String, installed: bool, app_name: String)
signal focus_exited_up_from_lists()
signal image_load_requested(url: String, texture_rect: TextureRect)

const REFRESH_COOLDOWN_SECONDS = 120
const INSTALLED_AUTOMATIC_REFRESH = true

@onready var app_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ListMarginContainer/AppListContainer
@onready var total_size_label: Label = $MarginContainer/VBoxContainer/HeaderContainer/TotalSizeLabel
@onready var sort_option_button: OptionButton = $MarginContainer/VBoxContainer/HeaderContainer/SortOptionButton
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer

# Refresh UI Elements (dynamically connected in _ready or via scene if we updated scene)
# Assuming they will be added to the scene:
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/RefreshContainer/RefreshButton
@onready var last_updated_label: Label = $MarginContainer/VBoxContainer/HeaderContainer/RefreshContainer/LastUpdatedLabel
@onready var cooldown_progress: TextureProgressBar = $MarginContainer/VBoxContainer/HeaderContainer/RefreshContainer/RefreshButton/CooldownProgress
@onready var loading_overlay_scene = preload("res://loading_overlay.tscn")

var loading_overlay_instance: Control = null
var installed_app_item_scene = preload("res://sections/installed_app_item.tscn")
var current_installed_apps_data: Dictionary = {}
var last_refresh_time: int = 0
var last_updated_time_str: String = "--:--"

# Sounds
var audio_player: AudioStreamPlayer
var stream_focus = preload("res://assets/change.mp3")
var stream_select = preload("res://assets/nextprev.wav")

func _ready():
	# Setup Audio
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)

	# Setup Loading Overlay
	if loading_overlay_scene:
		loading_overlay_instance = loading_overlay_scene.instantiate()
		add_child(loading_overlay_instance)
		loading_overlay_instance.visible = false

	# Connect Sort Button signals
	sort_option_button.item_selected.connect(_on_sort_option_selected)
	sort_option_button.focus_entered.connect(_on_sort_focus_entered)
	sort_option_button.pressed.connect(_on_sort_pressed) # When dropdown opens
	
	# Connect Refresh Button
	if is_instance_valid(refresh_button):
		refresh_button.pressed.connect(_on_refresh_pressed)
		refresh_button.focus_entered.connect(_on_sort_focus_entered) # Use same sound logic

	# Manual Focus Neighbors for Header
	if is_instance_valid(refresh_button) and is_instance_valid(sort_option_button):
		refresh_button.focus_neighbor_right = sort_option_button.get_path()
		sort_option_button.focus_neighbor_left = refresh_button.get_path()
		
	# Initial populate if data is already available
	var main_node = get_node_or_null("/root/App")
	if main_node and main_node.has_method("get_installed_ids"):
		var apps = main_node.get_installed_ids()
		if not apps.is_empty():
			update_internal_list_install_status(apps)

func _process(_delta):
	if not self.visible: return
	
	var current_time = Time.get_unix_time_from_system()
	var time_diff = current_time - last_refresh_time
	var remaining = REFRESH_COOLDOWN_SECONDS - time_diff
	
	if remaining > 0:
		# Cooldown active
		if is_instance_valid(refresh_button): 
			refresh_button.text = "Refresh List (%ds)" % int(remaining)
		if is_instance_valid(cooldown_progress):
			cooldown_progress.visible = true
			var progress = (remaining / float(REFRESH_COOLDOWN_SECONDS)) * 100
			cooldown_progress.value = progress
	else:
		# Cooldown expired
		if is_instance_valid(refresh_button): 
			refresh_button.text = "Refresh List"
		if is_instance_valid(cooldown_progress):
			cooldown_progress.visible = false
			
		# Auto-Refresh if enabled
		if INSTALLED_AUTOMATIC_REFRESH:
			print("InstalledView: Timer expired, triggering auto-refresh.")
			_trigger_refresh()

func _on_refresh_pressed():
	if audio_player and stream_select:
		audio_player.stream = stream_select
		audio_player.play()
	_trigger_refresh()

func _trigger_refresh():
	last_refresh_time = Time.get_unix_time_from_system()
	_update_last_updated_label()
	
	if is_instance_valid(loading_overlay_instance):
		loading_overlay_instance.show_overlay()
		
	var main_node = get_node_or_null("/root/App")
	if main_node and main_node.has_method("refresh_installed_apps_list"):
		main_node.refresh_installed_apps_list()
	
	# Fallback/Safety: Hide overlay after a few seconds if no update comes back quickly, 
	# though normally update_internal_list_install_status will clear it.
	get_tree().create_timer(5.0).timeout.connect(func(): if is_instance_valid(loading_overlay_instance): loading_overlay_instance.hide_overlay())

func _update_last_updated_label():
	if is_instance_valid(last_updated_label):
		var time_dict = Time.get_time_dict_from_system()
		last_updated_time_str = "%02d:%02d" % [time_dict.hour, time_dict.minute]
		last_updated_label.text = "Updated: " + last_updated_time_str

func _on_sort_option_selected(_index):
	if audio_player and stream_select:
		audio_player.stream = stream_select
		audio_player.play()
	_populate_list(current_installed_apps_data)

func _on_sort_focus_entered():
	if audio_player and stream_focus:
		audio_player.stream = stream_focus
		audio_player.play()

func _on_sort_pressed():
	# Optional: Play select sound when opening the dropdown
	if audio_player and stream_select:
		audio_player.stream = stream_select
		audio_player.play()

func on_view_entered():
	var current_time = Time.get_unix_time_from_system()
	var time_diff = current_time - last_refresh_time
	
	var should_refresh = false
	if current_installed_apps_data.is_empty():
		should_refresh = true
	elif INSTALLED_AUTOMATIC_REFRESH and time_diff >= REFRESH_COOLDOWN_SECONDS:
		should_refresh = true
		
	if should_refresh:
		print("InstalledView: Auto-refreshing installed apps (Cooldown expired or empty).")
		_trigger_refresh()
	else:
		print("InstalledView: Skipping auto-refresh (Cooldown active or disabled).")

	# Focus first element if nothing focused
	var focus_owner = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner) or not is_ancestor_of(focus_owner):
		focus_first_element()

func update_internal_list_install_status(installed_apps: Dictionary):
	# Hide overlay when data arrives
	if is_instance_valid(loading_overlay_instance):
		loading_overlay_instance.hide_overlay()
		
	# If this update came from an external source (not our refresh trigger), update timestamp anyway
	if installed_apps.hash() != current_installed_apps_data.hash():
		_update_last_updated_label()
		
	current_installed_apps_data = installed_apps
	_populate_list(installed_apps)

func _populate_list(installed_apps: Dictionary):
	# Clear existing
	for child in app_list_container.get_children():
		child.queue_free()
	
	var app_ids = installed_apps.keys()
	var sort_mode = sort_option_button.selected
	# 0 = Name Asc, 1 = Name Desc, 2 = Size Desc, 3 = Size Asc
	
	app_ids.sort_custom(func(a, b):
		if sort_mode == 2: # Size Descending (▼)
			var size_a = _parse_size(installed_apps[a].get("size", "0 B")).value_bytes
			var size_b = _parse_size(installed_apps[b].get("size", "0 B")).value_bytes
			return size_a > size_b
		elif sort_mode == 3: # Size Ascending (▲)
			var size_a = _parse_size(installed_apps[a].get("size", "0 B")).value_bytes
			var size_b = _parse_size(installed_apps[b].get("size", "0 B")).value_bytes
			return size_a < size_b
		elif sort_mode == 1: # Name Descending (Z-A, ▼)
			var name_a = installed_apps[a].get("name", a).to_lower()
			var name_b = installed_apps[b].get("name", b).to_lower()
			return name_a > name_b
		else: # Name Ascending (A-Z, ▲, Default 0)
			var name_a = installed_apps[a].get("name", a).to_lower()
			var name_b = installed_apps[b].get("name", b).to_lower()
			return name_a < name_b
	)
	
	var total_bytes: float = 0.0
	
	for app_id in app_ids:
		var info = installed_apps[app_id]
		
		# Only show user apps in this list
		if info.get("scope") != "user":
			continue
			
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
		if item.has_signal("image_load_requested"):
			item.image_load_requested.connect(func(url, rect): emit_signal("image_load_requested", url, rect))
		
	# Update Total Size Label
	total_size_label.text = "Total Size: %s" % _format_size(total_bytes)

func _on_item_pressed(app_id: String):
	var app_name = ""
	if current_installed_apps_data.has(app_id):
		app_name = current_installed_apps_data[app_id].get("name", "")
	emit_signal("move_to_details_view_requested", app_id, true, app_name)

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
	if is_instance_valid(refresh_button):
		refresh_button.grab_focus()
	elif app_list_container.get_child_count() > 0:
		var first = app_list_container.get_child(0)
		if first is Control:
			first.grab_focus()

func _unhandled_input(event):
	if event.is_action_pressed("go_back"):
		var focus_owner = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus_owner) and (app_list_container.is_ancestor_of(focus_owner) or focus_owner == refresh_button or focus_owner == sort_option_button):
			emit_signal("focus_exited_up_from_lists")
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_up"):
		var focus_owner = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus_owner):
			if app_list_container.is_ancestor_of(focus_owner):
				if focus_owner.get_index() == 0:
					if is_instance_valid(refresh_button):
						refresh_button.grab_focus()
						get_viewport().set_input_as_handled()
			elif focus_owner == refresh_button or focus_owner == sort_option_button:
				emit_signal("focus_exited_up_from_lists")
				get_viewport().set_input_as_handled()
