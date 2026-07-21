extends Control

# --- Signals (Required by Main) ---
signal move_to_details_view_requested(app_id: String, installed: bool)
signal image_load_requested(url: String, texture_rect: TextureRect)
signal focus_exited_up_from_lists()
signal load_new_page_requested(url: String, target_list: ProductList)

# --- UI Nodes ---
@onready var category_button_container: VBoxContainer = $HSplitContainer/LeftPanel/VBoxContainer/ScrollContainer/CategoryList
@onready var product_list: ProductList = $HSplitContainer/RightPanel/ProductList
@onready var back_button: Button = $HSplitContainer/LeftPanel/VBoxContainer/BackButton

# --- Internal State ---
var _api_cache_dir: String = ""
const CACHE_DURATION_SEC: int = 86400 # 24 hours

# --- Styling & Audio ---
var _style_normal: StyleBoxFlat
var _style_focus: StyleBoxFlat
var _style_pressed: StyleBoxFlat
var _category_button_group: ButtonGroup
var _focus_sound_player: AudioStreamPlayer
var _select_sound_player: AudioStreamPlayer
var _first_load: bool = true

func _ready():
	_setup_styles()
	_setup_audio()
	_setup_paths()
	_setup_product_list()
	
	# Fetch categories dynamically
	_fetch_categories()
	
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)
		back_button.visible = false # Hidden initially

func _setup_styles():
	# Normal Style (Transparent Black, Thin White Border)
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0, 0, 0, 0.35)
	_style_normal.set_border_width_all(1)
	_style_normal.border_color = Color(1, 1, 1, 1)
	_style_normal.content_margin_left = 15
	_style_normal.content_margin_right = 15
	
	# Focus Style (Transparent Black, Thick Purple Border)
	_style_focus = StyleBoxFlat.new()
	_style_focus.bg_color = Color(0, 0, 0, 0.35)
	_style_focus.set_border_width_all(3)
	_style_focus.border_color = Color(0.627, 0.125, 0.941, 1)
	_style_focus.content_margin_left = 15
	_style_focus.content_margin_right = 15
	
	# Pressed/Selected Style (Purple Background, Purple Border)
	_style_pressed = StyleBoxFlat.new()
	_style_pressed.bg_color = Color(0.627, 0.125, 0.941, 0.6) # Semi-transparent Purple
	_style_pressed.set_border_width_all(3)
	_style_pressed.border_color = Color(0.627, 0.125, 0.941, 1) # Solid Purple border
	_style_pressed.content_margin_left = 15
	_style_pressed.content_margin_right = 15
	
	_category_button_group = ButtonGroup.new()

func _setup_audio():
	_focus_sound_player = AudioStreamPlayer.new()
	_focus_sound_player.stream = load("res://assets/change.mp3")
	_focus_sound_player.bus = "Master" # Or specific UI bus if exists
	add_child(_focus_sound_player)
	
	_select_sound_player = AudioStreamPlayer.new()
	_select_sound_player.stream = load("res://assets/nextprev.wav")
	_select_sound_player.bus = "Master"
	add_child(_select_sound_player)

func _setup_paths():
	var main_node = get_node_or_null("/root/App")
	if main_node and main_node.has_method("get_api_cache_dir"):
		_api_cache_dir = main_node.get_api_cache_dir()
	else:
		_api_cache_dir = "user://cache/api"

func _setup_product_list():
	if is_instance_valid(product_list):
		product_list.use_auto_height = false
		product_list.move_to_details_view.connect(func(id, installed): emit_signal("move_to_details_view_requested", id, installed))
		product_list.image_load_requested.connect(func(url, rect): emit_signal("image_load_requested", url, rect))
		product_list.focus_exited_up.connect(func(): emit_signal("focus_exited_up_from_lists"))
		product_list.load_new_page.connect(func(url, list): emit_signal("load_new_page_requested", url, list))
		product_list.products_loaded.connect(_on_products_loaded)

func _on_products_loaded():
	if is_instance_valid(product_list) and is_visible_in_tree():
		# Wait for layout to stabilize (fixes scroll/focus issues)
		await get_tree().create_timer(0.05).timeout
		product_list.focus_first_product()

# --- Data Fetching ---

func _fetch_categories():
	var url = "https://flathub.org/api/v2/collection/category"
	
	if _try_load_from_cache(url):
		return
		
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_categories_request_completed.bind(http, url))
	
	var err = http.request(url)
	if err != OK:
		printerr("CategoriesView: Error requesting categories: ", err)
		http.queue_free()

func _on_categories_request_completed(_result, response_code, _headers, body, http: HTTPRequest, url: String):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json is Array:
			_save_to_cache(url, json)
			_populate_category_list(json)
		else:
			printerr("CategoriesView: Invalid JSON format for categories.")
	else:
		printerr("CategoriesView: HTTP Error fetching categories: ", response_code)
	
	http.queue_free()

func _try_load_from_cache(url: String) -> bool:
	if _api_cache_dir.is_empty(): return false
	
	var filename = url.md5_text() + ".json"
	var path = _api_cache_dir.path_join(filename)
	
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			var data = JSON.parse_string(content)
			file.close()
			
			if data is Dictionary and data.has("timestamp") and data.has("api_data"):
				var age = Time.get_unix_time_from_system() - data["timestamp"]
				if age < CACHE_DURATION_SEC:
					print("CategoriesView: Cache HIT for categories.")
					_populate_category_list(data["api_data"])
					return true
	return false

func _save_to_cache(url: String, api_data):
	if _api_cache_dir.is_empty(): return
	
	var filename = url.md5_text() + ".json"
	var path = _api_cache_dir.path_join(filename)
	
	var cache_data = {
		"timestamp": Time.get_unix_time_from_system(),
		"api_data": api_data
	}
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(cache_data))
		file.close()

# --- UI Population ---

func _populate_category_list(categories: Array):
	# Clear existing
	for child in category_button_container.get_children():
		child.queue_free()
		
	categories.sort()
	
	# Add some spacing between buttons
	category_button_container.add_theme_constant_override("separation", 10)
	
	for cat_id in categories:
		var btn = Button.new()
		# Display name: capitalize first letter (or specific mapping)
		var display_name = cat_id.capitalize() 
		btn.text = display_name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		# Styling
		btn.add_theme_stylebox_override("normal", _style_normal)
		btn.add_theme_stylebox_override("focus", _style_focus)
		btn.add_theme_stylebox_override("pressed", _style_pressed)
		btn.add_theme_stylebox_override("hover", _style_focus) # Mouse hover behaves like focus
		
		btn.custom_minimum_size.y = 45 # Make them easily touchable/clickable
		
		# Toggle behavior for "Selected" state
		btn.toggle_mode = true
		btn.button_group = _category_button_group
		
		btn.pressed.connect(_on_category_button_pressed.bind(cat_id))
		btn.gui_input.connect(_on_category_button_gui_input)
		btn.focus_entered.connect(_on_button_focus_entered)
		btn.mouse_entered.connect(func(): btn.grab_focus())
		
		category_button_container.add_child(btn)
		
	# Initial selection if first load
	if _first_load and category_button_container.get_child_count() > 0:
		var first_btn = category_button_container.get_child(0)
		first_btn.set_pressed_no_signal(true)
		_on_category_button_pressed(categories[0], false) # Manually trigger load without sound
		_first_load = false

func _on_button_focus_entered():
	if _focus_sound_player and SettingsManager.get_setting("play_ui_sounds", true):
		_focus_sound_player.play()

func _on_category_button_gui_input(event: InputEvent):
	if event.is_action_pressed("ui_right"):
		if is_instance_valid(product_list):
			product_list.focus_first_product()
			get_viewport().set_input_as_handled()

func _on_category_button_pressed(category_id: String, play_sound: bool = true):
	print("Selected Category ID: ", category_id)
	if play_sound and _select_sound_player and SettingsManager.get_setting("play_ui_sounds", true):
		_select_sound_player.play()
	
	if product_list:
		if product_list.has_method("show_loading"):
			product_list.show_loading()
			
		product_list.title = "Apps in category " + category_id.capitalize()
		var url = "https://flathub.org/api/v2/collection/category/%s?page=1&per_page=24&locale=en" % category_id.uri_encode()
		emit_signal("load_new_page_requested", url, product_list)

func _on_back_button_pressed():
	# If we have subcategories later, implement this.
	pass

# --- Interface for Main ---

func update_internal_list_install_status(installed_ids: Dictionary):
	if is_instance_valid(product_list):
		product_list.update_installed_status(installed_ids)

func focus_default_element():
	# Try to focus the selected button first, otherwise the first one
	var pressed_btn = _category_button_group.get_pressed_button()
	if pressed_btn:
		pressed_btn.grab_focus()
	elif category_button_container.get_child_count() > 0:
		category_button_container.get_child(0).grab_focus()
	elif is_instance_valid(back_button) and back_button.visible:
		back_button.grab_focus()

func on_view_entered():
	pass

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("go_back"):
		var focus_owner = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus_owner):
			# If we are in the product list, go back to the category selection
			if product_list.is_ancestor_of(focus_owner):
				focus_default_element()
				get_viewport().set_input_as_handled()
				return
			
			# If we are already in the category list, exit to the top bar
			if category_button_container.is_ancestor_of(focus_owner):
				emit_signal("focus_exited_up_from_lists")
				get_viewport().set_input_as_handled()
