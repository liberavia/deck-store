extends Control

@export var product_box: PackedScene = preload("res://product_box.tscn")
@export var product_list_scene: PackedScene = preload("res://product_list.tscn")

@onready var details_view: Control = $DetailsView
@onready var main_view: VBoxContainer = $CanvasLayer/VBoxContainer

@onready var section_view_container: Control = $CanvasLayer/VBoxContainer/SectionViewContainer

@onready var home_button: Button = $CanvasLayer/VBoxContainer/TopButtonBar/ButtonHome
@onready var top_button_bar: HBoxContainer = $CanvasLayer/VBoxContainer/TopButtonBar
@onready var global_scroll_container: ScrollContainer = $CanvasLayer/VBoxContainer/ContentScrollContainer
@onready var select_sound: AudioStreamPlayer = $SelectSoundPlayer
@onready var focus_sound: AudioStreamPlayer = $FocusSoundPlayer
@onready var back_sound: AudioStreamPlayer = $BackSoundPlayer
@onready var switch_sound: AudioStreamPlayer = $SwitchSoundPlayer

var _installed_flatpak_ids: Dictionary = {}
var _flatpak_list_output: String = ""
var _flatpak_thread: Thread = null
var _last_focused_product_box: Control = null
var _current_home_view_instance: Control = null
var _sections: Array[Dictionary] = [
	{"name": "Home", "scene_path": "res://sections/home_view.tscn", "button_node_name": "ButtonHome", "instance": null},
	{"name": "Categories", "scene_path": "res://sections/categories_view.tscn", "button_node_name": "ButtonCategories", "instance": null},
	{"name": "Installed", "scene_path": "res://sections/installed_view.tscn", "button_node_name": "ButtonInstalled", "instance": null},
	{"name": "Updates", "scene_path": "res://sections/updates_view.tscn", "button_node_name": "ButtonUpdates", "instance": null},
	{"name": "Extensions", "scene_path": "res://sections/extensions_view.tscn", "button_node_name": "ButtonExtensions", "instance": null},
	{"name": "Search", "scene_path": "res://sections/search_view.tscn", "button_node_name": "ButtonSearch", "instance": null}
]
var _current_section_index: int = 0
var _is_switching_section: bool = false
var _suppress_focus_sound: bool = false

# --- Cache-Constants ---
const DECKSTORE_BASE_DIR_NAME = ".deck-store"
const API_CACHE_SUBDIR = "cache/api"
const IMAGE_CACHE_SUBDIR = "cache/images"

const CACHE_DURATION_SEC: int = 3600 # 1 hour
const IMAGE_CACHE_DURATION_SEC: int = 7 * 24 * 60 * 60 # 1 week

var transition_time := 0.5
var transition_time_section_change := 0.2

# Absolute paths, will be initialized in _ready()
var _deckstore_abs_base_path: String = ""
var _api_cache_abs_path: String = ""
var _image_cache_abs_path: String = ""

signal installed_apps_updated

# =============================================================================
# LIFECYCLE METHODS
# =============================================================================

func _ready():
	var home_dir = OS.get_environment("HOME")
	if home_dir.is_empty():
		printerr("FATAL ERROR: Could not determine user's HOME directory. Caching will fail.")
		return

	# Construct absolute paths for DeckStore data
	_deckstore_abs_base_path = home_dir.path_join(DECKSTORE_BASE_DIR_NAME)
	_api_cache_abs_path = _deckstore_abs_base_path.path_join(API_CACHE_SUBDIR)
	_image_cache_abs_path = _deckstore_abs_base_path.path_join(IMAGE_CACHE_SUBDIR)
	
	print("INFO: DeckStore Base Path (absolute): ", _deckstore_abs_base_path)
	print("INFO: API Cache Directory (absolute Path): ", _api_cache_abs_path)
	print("INFO: Image Cache Directory (absolute Path): ", _image_cache_abs_path)

	# Create API cache directory
	var err_api_cache = DirAccess.make_dir_recursive_absolute(_api_cache_abs_path)
	if err_api_cache != OK and err_api_cache != ERR_ALREADY_EXISTS:
		printerr("ERROR: Could not create API cache directory: ", _api_cache_abs_path, ", Code: ", err_api_cache)
	
	# Create Image cache directory
	var err_img_cache = DirAccess.make_dir_recursive_absolute(_image_cache_abs_path)
	if err_img_cache != OK and err_img_cache != ERR_ALREADY_EXISTS:
		printerr("ERROR: Could not create image cache directory: ", _image_cache_abs_path, ", Code: ", err_img_cache)
			
	# --- Setup Top Bar Buttons (Styles & Toggle) ---
	var section_btn_group = ButtonGroup.new()
	
	# Pressed/Selected Style (Purple Background, Purple Border)
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.627, 0.125, 0.941, 0.6) # Semi-transparent Purple
	style_pressed.set_border_width_all(3)
	style_pressed.border_color = Color(0.627, 0.125, 0.941, 1) # Solid Purple border
	
	# Focus Style (Reuse existing focus style logic or create similar if needed, 
	# but buttons already have overrides from scene. We just add 'pressed')
	
	home_button.focus_mode = Control.FOCUS_ALL
	for btn in top_button_bar.get_children():
		if btn is Button: 
			btn.focus_mode = Control.FOCUS_ALL
			btn.toggle_mode = true
			btn.button_group = section_btn_group
			btn.add_theme_stylebox_override("pressed", style_pressed)
			# Optional: Make hover look like focus if not already consistent
			# btn.add_theme_stylebox_override("hover", ...) 

	for i in range(_sections.size()):
		var section_data = _sections[i]
		var scene = load(section_data.scene_path) as PackedScene
		if scene:
			var instance = scene.instantiate()
			_sections[i].instance = instance 
			
			if section_data.name == "Home" and "product_box_scene" in instance:
				instance.product_box_scene = product_box
			
			_connect_section_signals(instance)
			
			instance.visible = (i == 0) # Mache nur die erste Sektion (Home) sichtbar
			section_view_container.add_child(instance)
		else:
			printerr("ERROR: Could not load scene for section: ", section_data.name)

	for i in range(_sections.size()):
		var section_data = _sections[i]
		var button_node = top_button_bar.get_node_or_null(section_data.button_node_name) as Button
		if is_instance_valid(button_node):
			button_node.pressed.connect(_on_top_bar_button_pressed.bind(i))
		else:
			printerr("ERROR: Button node not found for section: ", section_data.name)

	for btn_node in top_button_bar.get_children():
		if btn_node is Button:
			btn_node.focus_entered.connect(_on_top_bar_button_focus_entered)
			
	load_popular_products()
	load_trending_products()
	
	Input.joy_connection_changed.connect(_on_joy_connection_changed) # Beibehalten

	details_view.move_back_to_main_view.connect(_on_move_back_to_main_view)
	details_view.image_load_requested.connect(_on_product_list_image_load_requested)

	_check_connected_controllers() 
	print("-----------------------------------------")
	_switch_to_section(0)
	home_button.grab_focus()
	_fetch_installed_apps()
	
# =============================================================================
# INPUT HANDLING (Nur _unhandled_input)
# =============================================================================

func _unhandled_input(event: InputEvent):
	var new_section_index = _current_section_index
	var switched = false
	if event.is_action_pressed("section_next"): # R1 / RB
		new_section_index += 1
		if new_section_index >= _sections.size():
			new_section_index = 0 # Wrap around to the start
		switched = true
		
	elif event.is_action_pressed("section_previous"): # L1 / LB
		new_section_index -= 1
		if new_section_index < 0:
			new_section_index = _sections.size() - 1 # Wrap around to the end
		switched = true
	
	if switched:
		_on_top_bar_button_pressed(new_section_index)
		get_viewport().set_input_as_handled()
		return
			
	var focused_control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused_control): return

	if top_button_bar.is_ancestor_of(focused_control):
		if event.is_action_pressed("go_back"):
			if _current_section_index != 0:
				_on_top_bar_button_pressed(0)
				get_viewport().set_input_as_handled()
				return

		var action_string = ""
		if event.is_action_pressed("ui_down"): action_string = "ui_down"
		elif event.is_action_pressed("ui_left"): action_string = "ui_left" # Für Navigation innerhalb der Buttons
		elif event.is_action_pressed("ui_right"): action_string = "ui_right" # Für Navigation innerhalb der Buttons

		if action_string == "ui_down":
			if is_instance_valid(_current_home_view_instance) and _current_home_view_instance.has_method("focus_first_product_in_popular_list"):
				_current_home_view_instance.focus_first_product_in_popular_list()
			get_viewport().set_input_as_handled()
		elif action_string == "ui_left" or action_string == "ui_right":
			pass
	
# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
func _on_top_bar_button_focus_entered():
	if _suppress_focus_sound:
		return

	if is_instance_valid(focus_sound):
		focus_sound.play()

func load_popular_products():
	# Get the instance of the home view from our sections array
	var home_view_node = _sections[0].instance # Index 0 is "Home"
	if is_instance_valid(home_view_node) and home_view_node.has_node("ContentScrollContainer/VBoxContainer/PopularProductList"):
		var popular_list = home_view_node.get_node("ContentScrollContainer/VBoxContainer/PopularProductList")
		_load_product_list("https://flathub.org/api/v2/collection/popular?page=1&per_page=10&locale=en", popular_list)
	else:
		printerr("ERROR: Could not find PopularProductList in HomeView instance.")

func load_trending_products():
	var home_view_node = _sections[0].instance
	if is_instance_valid(home_view_node) and home_view_node.has_node("ContentScrollContainer/VBoxContainer/TrendingProductList"):
		var trending_list = home_view_node.get_node("ContentScrollContainer/VBoxContainer/TrendingProductList")
		_load_product_list("https://flathub.org/api/v2/collection/trending?page=1&per_page=10&locale=en", trending_list)
	else:
		printerr("ERROR: Could not find TrendingProductList in HomeView instance.")

func get_image_cache_dir():
	return _image_cache_abs_path

func get_api_cache_dir() -> String:
	return _api_cache_abs_path
	
func is_app_installed(app_id: String) -> bool:
	return _installed_flatpak_ids.has(app_id)

func get_app_scope(app_id: String) -> String:
	if _installed_flatpak_ids.has(app_id):
		return _installed_flatpak_ids[app_id].get("scope", "user")
	return ""

func get_installed_ids() -> Dictionary:
	return _installed_flatpak_ids

func _get_api_cache_filepath(url: String) -> String:
	var hash = url.md5_text() 
	return get_api_cache_dir().path_join(hash + ".json")

func _get_image_cache_filepath(image_url: String, file_extension: String) -> String:
	if _image_cache_abs_path.is_empty():
		printerr("ERROR: _get_image_cache_filepath - Image Cache Path not initialized!")
		return ""
	var url_hash = image_url.md5_text()
	return _image_cache_abs_path.path_join(url_hash + file_extension)
	
func _on_product_list_image_load_requested(url: String, texture_rect: TextureRect):
	if not is_instance_valid(texture_rect):
		printerr("ERROR: Image request for invalid texture_rect, URL: ", url)
		return
	if url.is_empty():
		printerr("ERROR: Empty image URL provided.")
		return

	var url_hash = url.md5_text()
	var cache_filepath_png = _get_image_cache_filepath(url, ".png")
	var cache_filepath_webp = _get_image_cache_filepath(url, ".webp")

	var cache_filepath_to_load = ""
	var file_extension = ""

	if FileAccess.file_exists(cache_filepath_png):
		cache_filepath_to_load = cache_filepath_png
		file_extension = ".png"
	elif FileAccess.file_exists(cache_filepath_webp):
		cache_filepath_to_load = cache_filepath_webp
		file_extension = ".webp"

	if not cache_filepath_to_load.is_empty():
		var modification_time = FileAccess.get_modified_time(cache_filepath_to_load)
		var current_time = Time.get_unix_time_from_system()
		var cache_age = current_time - modification_time

		if cache_age < IMAGE_CACHE_DURATION_SEC:
			var file = FileAccess.open(cache_filepath_to_load, FileAccess.READ)
			if file:
				var file_size = file.get_length()
				if file_size > 0:
					var buffer = file.get_buffer(file_size)
					file.close()

					var image = Image.new()
					var error = ERR_CANT_OPEN

					if file_extension == ".png":
						error = image.load_png_from_buffer(buffer)
					elif file_extension == ".webp":
						error = image.load_webp_from_buffer(buffer)

					if error == OK:
						var texture = ImageTexture.create_from_image(image)
						texture_rect.texture = texture
						return
					else:
						printerr("ERROR: Failed to load image from cache buffer: ", cache_filepath_to_load, ", Error: ", error)
						DirAccess.remove_absolute(cache_filepath_to_load)
				else:
					printerr("ERROR: Cache file is empty: ", cache_filepath_to_load)
					file.close()
					DirAccess.remove_absolute(cache_filepath_to_load)
			else:
				printerr("ERROR: Could not open cache file for reading: ", cache_filepath_to_load, " Error code: ", FileAccess.get_open_error())
		else:
			DirAccess.remove_absolute(cache_filepath_to_load)

	var http_request_image = HTTPRequest.new()
	add_child(http_request_image)
	http_request_image.request_completed.connect(
		_on_image_request_completed.bind(texture_rect, url, http_request_image)
	)

	var error = http_request_image.request(url)
	if error != OK:
		printerr("ERROR: Starting image request failed for %s: %s" % [url, error])
		if is_instance_valid(http_request_image):
			http_request_image.queue_free()

		
func _on_product_list_focus_exited_up():
	var current_section = _sections[_current_section_index]
	var button_node = top_button_bar.get_node_or_null(current_section.button_node_name) as Button
	
	if is_instance_valid(button_node):
		print("Main: Received focus_exited_up, focusing current section button: ", button_node.name)
		button_node.grab_focus()

		if is_instance_valid(_current_home_view_instance) and \
			_current_home_view_instance.name == "HomeView" and \
			_current_home_view_instance.has_method("scroll_to_top"):
			
			_current_home_view_instance.scroll_to_top()
		else:
			# Fallback, falls der global_scroll_container noch relevant ist oder als Notlösung
			if is_instance_valid(global_scroll_container): # global_scroll_container ist der alte in main.tscn
				global_scroll_container.scroll_vertical = 0
				print("Main: Reset global scroll position to top (fallback).") 
			
# In main.gd

func _on_move_to_details_view(app_id: String, installed: bool, app_name: String = ""):
	var focused_control = get_viewport().gui_get_focus_owner()
	_last_focused_product_box = null # Reset before attempting to set

	if is_instance_valid(focused_control):
		var current_section_node = _sections[_current_section_index].instance
		if is_instance_valid(current_section_node) and current_section_node.is_ancestor_of(focused_control):
			var candidate = focused_control
			# Traverse up the scene tree from the focused_control
			# until we either find a node of type ProductBox
			# or we reach the current_section_node itself (meaning focused_control was not inside a ProductBox)
			# or we have no parent left within the section.
			while is_instance_valid(candidate):
				if candidate is ProductBox: # This requires 'class_name ProductBox' in your product_box.gd
					_last_focused_product_box = candidate
					print("INFO Main: Stored last focused ProductBox: ", candidate.name if "name" in candidate else "Unnamed ProductBox")
					break # Found it!
				
				# Stop if the parent is the section container itself or if there's no parent
				var parent = candidate.get_parent()
				if not is_instance_valid(parent) or parent == current_section_node:
					# If we reached here, focused_control was not inside a ProductBox,
					# or ProductBox itself was focused (and the 'is ProductBox' check above caught it).
					# If the originally focused control is what we want to re-focus and it's not a ProductBox,
					# we could store 'focused_control' directly, but it's usually better to focus its ProductBox container.
					if _last_focused_product_box == null: # Only if we haven't found a ProductBox yet
						print("WARN Main: Focused control was not a ProductBox or child of one. Storing direct focused_control for fallback: ", focused_control)
						_last_focused_product_box = focused_control # Fallback to the actual focused item
					break 
				candidate = parent
	
	if not is_instance_valid(_last_focused_product_box):
		print("INFO Main: Could not determine a specific control to re-focus within the current section.")

	# The rest of your function to switch to details_view
	details_view.set_initial_state(app_id, installed, app_name)
	details_view.load_details()
	if is_instance_valid(select_sound): select_sound.play() # Check if sound player is valid
	
	# --- Transition Logic (simplified for now, focus on the problem) ---
	# Your tweening logic for main_view and details_view
	var tween = create_tween()
	var main_view_height = main_view.size.y
	# var target_y = main_view_height # This moves main_view down, was it intended to move up?
	var target_y_main_out = -main_view_height # Example: move main_view up and out
	
	tween.tween_property(main_view, "position:y", target_y_main_out, transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	main_view.visible = false # Hide after animation

	details_view.position.y = 0 # Ensure details_view is at its correct position
	details_view.visible = true
	details_view.set_initial_focus()
		
func _on_move_back_to_main_view():
	back_sound.play()
	var tween = create_tween()
	var main_view_height = main_view.size.y
	print("Main view height back: ", main_view_height)
	var target_y = 0
	tween.tween_property(main_view, "position:y", target_y, transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	details_view.visible = false
	main_view.visible = true
	await tween.finished
	details_view.clear_data()
	
	if is_instance_valid(_last_focused_product_box) and _last_focused_product_box.is_inside_tree():
		_last_focused_product_box.grab_focus()
		print("INFO Main: Restored focus to: ", _last_focused_product_box.name if _last_focused_product_box and "name" in _last_focused_product_box else "unnamed or null")
	else:
		print("INFO Main: _last_focused_product_box is invalid or not in tree. Focusing default.")
		var current_section_instance = _sections[_current_section_index].instance
		if is_instance_valid(current_section_instance) and current_section_instance.has_method("focus_default_element"):
			current_section_instance.focus_default_element()
		elif is_instance_valid(home_button): # Absolute fallback
			home_button.grab_focus()
	_last_focused_product_box = null 
# =============================================================================
# PRODUCT LOADING & CALLBACKS 
# =============================================================================

func _on_image_request_completed(result, response_code, headers, body: PackedByteArray, texture_rect: TextureRect, image_url: String, http_request_node: HTTPRequest):
	if not is_instance_valid(texture_rect):
		printerr("ERROR: TextureRect invalid in image callback for URL: ", image_url)
		if is_instance_valid(http_request_node): http_request_node.queue_free()
		return

	if response_code == 200 and result == HTTPRequest.RESULT_SUCCESS:
		var image = Image.new()
		var error = ERR_FILE_UNRECOGNIZED
		var content_type = ""
		var file_extension = ""

		for header in headers:
			if header.findn("Content-Type:") == 0:
				content_type = header.get_slice(":", 1).strip_edges().to_lower()
				break

		if content_type == "image/png":
			error = image.load_png_from_buffer(body)
			file_extension = ".png"
		elif content_type == "image/webp":
			error = image.load_webp_from_buffer(body)
			file_extension = ".webp"
		else:
			printerr("ERROR: Unknown or unsupported image type '%s' for URL: %s" % [content_type, image_url])
			error = ERR_FILE_UNRECOGNIZED

		if error == OK:
			var texture = ImageTexture.create_from_image(image)
			texture_rect.texture = texture

			if not file_extension.is_empty():
				var url_hash = image_url.md5_text()
				var cache_filepath = _get_image_cache_filepath(image_url, file_extension)
				if not cache_filepath.is_empty():
					var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
				var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
				var open_error = FileAccess.get_open_error()
				if open_error == OK:
					file.store_buffer(body)
					file.close()
				else:
					printerr("ERROR: Could not open cache file for writing: ", cache_filepath, " Code: ", open_error)
					if is_instance_valid(file): file.close()
		else:
			printerr("ERROR: Failed loading image buffer. Type: '%s', Error: %s, URL: %s" % [content_type, error, image_url])
	else:
		printerr("ERROR: HTTP Error %d (Result %d) downloading image: %s" % [response_code, result, image_url])

	if is_instance_valid(http_request_node):
		http_request_node.queue_free()
				

# =============================================================================
# DATA LOADING (Mit File Cache Logik)
# =============================================================================

func _load_product_list(url: String, target_list: ProductList):
	if not is_instance_valid(target_list):
		printerr("ERROR Invalid target list, URL: ", url)
		return

	# --- File Cache Check ---
	# Special handling for Search (POST request disguised as GET URL for internal consistency)
	if url.begins_with("https://flathub.org/api/v2/search"):
		_perform_search_post(url, target_list)
		return

	var cache_filepath = _get_api_cache_filepath(url)
	if FileAccess.file_exists(cache_filepath):
		print("-> Cache-Datei gefunden: ", cache_filepath.get_file())
		var file = FileAccess.open(cache_filepath, FileAccess.READ)
		var open_error = FileAccess.get_open_error()

		if open_error == OK:
			var json_string = file.get_as_text()
			file.close()
			var cache_content = JSON.parse_string(json_string)

			if cache_content is Dictionary:
				var timestamp = cache_content.get("timestamp", 0) 
				var api_data = cache_content.get("api_data")
				var current_time = Time.get_unix_time_from_system() 
				var cache_age = current_time - timestamp

				# Vergleiche mit der Dauer in Sekunden
				if cache_age < CACHE_DURATION_SEC and api_data != null:
					print("--> Cache HIT for %s (Age: %d sec)" % [target_list.title, cache_age]) # Ausgabe in Sekunden
					_process_product_list_data(api_data, target_list, url)
					return
				else:
					print("--> Cache EXPIRED or invalid for %s (Age: %d sec)" % [target_list.title, cache_age]) # Ausgabe in Sekunden
					DirAccess.remove_absolute(cache_filepath)
			else:
				print("--> Cache-File corrupt (No Dictionary) for %s: %s" % [target_list.title, cache_filepath.get_file()])
				DirAccess.remove_absolute(cache_filepath)
		else:
			printerr("--> Error opening cahce file %s: %s" % [cache_filepath.get_file(), open_error])
			if is_instance_valid(file): file.close() # Sicherstellen, dass Handle geschlossen wird
	else:
		print("-> Cache MISS for  %s" % target_list.title)

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(
		_on_product_list_request_completed.bind(http_request, url, target_list)
	)	
	var error = http_request.request(url)
	if error != OK:
		printerr("Error starting request for '%s' (%s): %s" % [target_list.title, url, error])
		if is_instance_valid(http_request): http_request.queue_free()

func _perform_search_post(url: String, target_list: ProductList):
	print("DEBUG: Performing POST search for URL: ", url)
	
	# 1. Parse Parameters from URL string
	# URL format: https://flathub.org/api/v2/search?q=...&page=...&per_page=...
	var query_string = ""
	var page = 1
	var per_page = 24
	
	var parts = url.split("?")
	if parts.size() > 1:
		var params = parts[1].split("&")
		for p in params:
			var kv = p.split("=")
			if kv.size() == 2:
				var key = kv[0]
				var val = kv[1].uri_decode()
				match key:
					"q", "query": query_string = val
					"page": page = int(val)
					"per_page": per_page = int(val)
	
	if query_string.is_empty():
		printerr("ERROR: No query found in search URL: ", url)
		return

	# 2. Prepare POST Request
	var api_url = "https://flathub.org/api/v2/search"
	var headers = ["Content-Type: application/json"]
	var body_data = {
		"query": query_string,
		"page": page,
		"per_page": per_page
	}
	var body_json = JSON.stringify(body_data)
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(
		_on_search_request_completed.bind(http_request, url, target_list)
	)
	
	print("DEBUG: Sending POST to ", api_url, " with body: ", body_json)
	var error = http_request.request(api_url, headers, HTTPClient.METHOD_POST, body_json)
	if error != OK:
		printerr("Error starting SEARCH request: ", error)
		http_request.queue_free()

func _on_search_request_completed(result, response_code, headers, body, http_request_list: HTTPRequest, url: String, target_list: ProductList):
	if not is_instance_valid(target_list):
		if is_instance_valid(http_request_list): http_request_list.queue_free()
		return
		
	if response_code == 200:
		var response_string = body.get_string_from_utf8()
		var api_json = JSON.parse_string(response_string)
		
		if api_json != null:
			# We don't cache search results effectively yet, or we could cache by the custom URL hash
			# For now, just process data
			_process_product_list_data(api_json, target_list, url)
		else:
			printerr("JSON parse error for Search Response.")
	else:
		printerr("HTTP Error %d while searching." % response_code)
		if body.size() > 0:
			print("Response Body: ", body.get_string_from_utf8())

	if is_instance_valid(http_request_list):
		http_request_list.queue_free()

func _on_product_list_request_completed(result, response_code, headers, body, http_request_list: HTTPRequest, url: String, target_list: ProductList):
	if not is_instance_valid(target_list):
		printerr("Ziel-ProductList ungültig im Callback für URL: ", url)
		if is_instance_valid(http_request_list): http_request_list.queue_free(); return

	if response_code == 200:
		var response_string = body.get_string_from_utf8()
		var api_json = JSON.parse_string(response_string)

		if api_json != null:
			var data_to_cache = {
				"timestamp": Time.get_unix_time_from_system(),
				"api_data": api_json
			}
			var json_string_to_cache = JSON.stringify(data_to_cache, "  ") # Mit Einrückung für Lesbarkeit
			var cache_filepath = _get_api_cache_filepath(url)

			var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
			var open_error = FileAccess.get_open_error()
			if open_error == OK:
				file.store_string(json_string_to_cache)
				file.close()
				print("-> Data for  '%s' saved in cache file: %s" % [url.get_file(), cache_filepath.get_file()])
			else:
				printerr("--> Error writing cache file %s: %s" % [cache_filepath.get_file(), open_error])
				if is_instance_valid(file): file.close()

			_process_product_list_data(api_json, target_list, url)
		else:
			printerr("JSON parse error for URL '%s'." % url)
	else:
		printerr("HTTP Error %d while requesting from '%s'." % [response_code, url])

	if is_instance_valid(http_request_list):
		http_request_list.queue_free()
		
func _process_product_list_data(json_data, target_list: ProductList, url: String):
	print("DEBUG Process product list data of url: ", url)
	if not is_instance_valid(target_list): printerr("Invalid target list in _process_product_list_data"); return
	if json_data is Dictionary and json_data.has('hits') and json_data['hits'] is Array:
		target_list.set_url(url)
		target_list.set_products(json_data['hits'])
		target_list.set_pagination_data(int(json_data['hitsPerPage']), int(json_data['page']), int(json_data['totalPages']))
		print("Productlist '%s' updated." % target_list.title)
	else: printerr("Unexpected data structure for list '%s'." % target_list.title)

# =============================================================================
# JOY CONNECTION CALLBACKS
# =============================================================================

func _check_connected_controllers():
	var connected_joypads = Input.get_connected_joypads()
	if connected_joypads.size() > 0:
		print("Controllers at start:")
		for device_id in connected_joypads: print("  Device ID: ", device_id, ", Name: ", Input.get_joy_name(device_id))
	else: print("no controllers detected at start.")

func _on_joy_connection_changed(device_id: int, connected: bool):
	if connected: print("CONTROLLER CONNECTED:\n  Device ID: ", device_id, ", Name: ", Input.get_joy_name(device_id))
	else: print("CONTROLLER DISCONNECTED:\n  Device ID: ", device_id)
	print("-----------------------------------------")

# =============================================================================
# INSTALLED APP HANDLING
# =============================================================================

func _fetch_installed_apps():
	if _flatpak_thread != null and _flatpak_thread.is_alive():
		return

	print("INFO: Start Thread for fetching installed flatpaks...")
	_flatpak_thread = Thread.new()
	var callable = Callable(self, "_execute_flatpak_in_thread")
	var err = _flatpak_thread.start(callable)
	if err != OK:
		printerr("ERROR: Could not start flatpak thread! Code: ", err)
		_flatpak_thread = null


func _execute_flatpak_in_thread():
	var spawn_cmd = "/usr/bin/flatpak-spawn"
	# Use sh -c to set LC_ALL=C for consistent output format (dots for decimals)
	# and fetch application ID, name, size and installation scope.
	var host_command = "LC_ALL=C flatpak list --app --columns=application,name,size,installation"
	var spawn_args = ["--host", "sh", "-c", host_command]
	
	var output_array = []

	print("INFO: Thread: Execute '%s %s' ..." % [spawn_cmd, " ".join(spawn_args)])

	if not FileAccess.file_exists(spawn_cmd):
		printerr("ERROR: Command '%s' was not found. Cannot execute host command." % spawn_cmd)
		Callable(self, "_process_flatpak_result").call_deferred("", -1)
		return

	var exit_code = OS.execute(spawn_cmd, spawn_args, output_array)

	var output_string = ""
	if output_array.size() > 0:
		output_string = output_array[0]

	Callable(self, "_process_flatpak_result").call_deferred(output_string, exit_code)

func get_cached_image_path(image_url: String) -> String:
	if image_url.is_empty():
		return ""

	var url_hash = image_url.md5_text()
	var path_png = _get_image_cache_filepath(image_url, ".png")
	var path_webp = _get_image_cache_filepath(image_url, ".webp")

	if FileAccess.file_exists(path_png):
		return path_png
	elif FileAccess.file_exists(path_webp):
		print("WARN: Found cached image as WebP, Python Pillow needs libwebp support: ", path_webp)
		return path_webp
	else:
		print("DEBUG Main: Image not found in cache for URL: ", image_url)
		return ""

func _process_flatpak_result(output: String, exit_code: int):
	print("INFO: Process flatpak result...")
	if exit_code == 0:
		_installed_flatpak_ids.clear() 
		var lines = output.strip_edges().split("\n")
		var count = 0
		for line in lines:
			line = line.strip_edges()
			if line.is_empty(): continue
			
			# Columns: application, name, size, installation
			# separated by tabs usually, but let's be robust
			var parts = line.split("\t")
			if parts.size() >= 4:
				var app_id = parts[0].strip_edges()
				var app_name = parts[1].strip_edges()
				var app_size = parts[2].strip_edges()
				var scope = parts[3].strip_edges()
				
				_installed_flatpak_ids[app_id] = {
					"name": app_name,
					"size": app_size,
					"scope": scope
				}
				count += 1
			else:
				# Fallback if split by tab fails (maybe spaces?)
				# But spaces are dangerous because Name can have spaces.
				# Given LC_ALL=C and standard flatpak list, tabs are expected.
				# We log a warning if parsing fails.
				printerr("WARN: Could not parse flatpak line: ", line)
				
		print("INFO: %d installed flatpaks found and processed." % count)
		_update_all_lists_install_status()
		emit_signal("installed_apps_updated")
	else:
		printerr("ERROR: 'flatpak list' failed with code: ", exit_code)
		printerr("Flatpak Output: ", output)

	if _flatpak_thread != null and _flatpak_thread.is_started():
		_flatpak_thread.wait_to_finish()
	_flatpak_thread = null

func _update_all_lists_install_status():
	print("INFO Main: Updating install status in current section...")
	if _current_section_index >= 0 and _current_section_index < _sections.size():
		var current_section_node = _sections[_current_section_index].instance
		if is_instance_valid(current_section_node) and current_section_node.has_method("update_internal_list_install_status"):
			# The current section's script (e.g., home_view.gd, categories_view.gd)
			# must implement update_internal_list_install_status(installed_ids_dict)
			current_section_node.update_internal_list_install_status(_installed_flatpak_ids)
			print("INFO Main: Called update_internal_list_install_status on: ", current_section_node.name)
		elif is_instance_valid(current_section_node):
			print("DEBUG Main: Current section '", current_section_node.name, "' does not have 'update_internal_list_install_status' method.")
		else:
			print("DEBUG Main: Current section instance is invalid.")
	else:
		print("DEBUG Main: No valid current section index to update install status for.")

# Switches to the section at the given index with a carousel animation
func _switch_to_section(target_index: int):
	if _is_switching_section: return
	if target_index < 0 or target_index >= _sections.size(): return
	if target_index == _current_section_index and is_instance_valid(_sections[target_index].instance): return

	_is_switching_section = true

	var old_section_index = _current_section_index
	var old_section_instance = _sections[old_section_index].instance
	
	var new_section_instance = _sections[target_index].instance
	
	# --- START: Corrected Animation Direction Logic ---
	var direction = 1 # Default: "next" animation (new view from the right)
	
	# Determine direction based on index change
	if target_index < old_section_index:
		# This is a normal "previous" press (e.g., from index 3 to 2)
		direction = -1
	
	# Now, specifically handle the wrap-around cases to get the correct "feel"
	if old_section_index == _sections.size() - 1 and target_index == 0:
		# Case: Moving forward from the last section (e.g., Search) to the first (Home)
		# This is a "next" action.
		direction = 1
	elif old_section_index == 0 and target_index == _sections.size() - 1:
		# Case: Moving backward from the first section (Home) to the last (Search)
		# This is a "previous" action.
		direction = -1
	
	var container_width = section_view_container.size.x

	# Prepare and show the new section off-screen
	if is_instance_valid(new_section_instance):
		new_section_instance.position.x = container_width * direction
		new_section_instance.visible = true
		if new_section_instance.has_method("on_view_entered"):
			new_section_instance.on_view_entered()
	else:
		printerr("ERROR: New section instance is invalid for index: ", target_index)
		_is_switching_section = false
		return
		
	# Create and configure the tween for the animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	# Animate the new section into view
	tween.tween_property(new_section_instance, "position:x", 0, transition_time_section_change)

	# Animate the old section out of view
	if is_instance_valid(old_section_instance):
		if old_section_instance.has_method("on_view_exiting"):
			old_section_instance.on_view_exiting()
		# Move it in the opposite direction
		tween.tween_property(old_section_instance, "position:x", -container_width * direction, transition_time_section_change)
		# Hide the old section after the animation completes
		tween.chain().tween_callback(func(): old_section_instance.visible = false)
	
	# Update the current index *after* the direction has been calculated
	_current_section_index = target_index
	
	# Update the top bar focus and re-enable switching after animation
	await tween.finished
	_update_top_bar_button_focus()
	_is_switching_section = false
	
# Called when a button in the top bar is pressed
func _on_top_bar_button_pressed(target_index: int):
	if is_instance_valid(switch_sound) and _is_switching_section == false:
		switch_sound.play()
	_switch_to_section(target_index)

# Helper to connect signals for any Section View (HomeView, CategoriesView, etc.)
func _connect_section_signals(view_node: Control):
	if not is_instance_valid(view_node): return

	if view_node.has_signal("move_to_details_view_requested"):
		if not view_node.move_to_details_view_requested.is_connected(_on_move_to_details_view):
			view_node.move_to_details_view_requested.connect(_on_move_to_details_view)
			
	if view_node.has_signal("image_load_requested"):
		if not view_node.image_load_requested.is_connected(_on_product_list_image_load_requested):
			view_node.image_load_requested.connect(_on_product_list_image_load_requested)
			
	if view_node.has_signal("focus_exited_up_from_lists"):
		if not view_node.focus_exited_up_from_lists.is_connected(_on_product_list_focus_exited_up):
			view_node.focus_exited_up_from_lists.connect(_on_product_list_focus_exited_up)
			
	if view_node.has_signal("load_new_page_requested"):
		if not view_node.load_new_page_requested.is_connected(_load_product_list):
			view_node.load_new_page_requested.connect(_load_product_list)

# Helper to update focus and style on top bar buttons
func _update_top_bar_button_focus():
	for i in range(_sections.size()):
		var button_name = _sections[i].button_node_name
		var button_node = top_button_bar.get_node_or_null(button_name) as Button

		if not is_instance_valid(button_node):
			continue

		if i == _current_section_index:
			# Suppress the sound *before* grabbing focus
			_suppress_focus_sound = true
			button_node.grab_focus()
			button_node.set_pressed_no_signal(true)

			await get_tree().process_frame
			_suppress_focus_sound = false
		else:
			button_node.set_pressed_no_signal(false)
			
func refresh_installed_apps_list():
	print("INFO Main: Refreshing installed apps list due to recent install/uninstall.")
	_fetch_installed_apps()
