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
@onready var back_sound: AudioStreamPlayer = $BackSoundPlayer

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
var _is_switching_section: bool = false # To prevent multiple switches at once

# --- Cache-Constants ---
const DECKSTORE_BASE_DIR_NAME = ".deck-store"
const API_CACHE_SUBDIR = "cache/api"
const IMAGE_CACHE_SUBDIR = "cache/images"

const CACHE_DURATION_SEC: int = 3600 # 1 hour
const IMAGE_CACHE_DURATION_SEC: int = 7 * 24 * 60 * 60 # 1 week

var transition_time := 0.5

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
			
	home_button.focus_mode = Control.FOCUS_ALL
	for btn in top_button_bar.get_children():
		if btn is Button: btn.focus_mode = Control.FOCUS_ALL

	# Lade und instanziiere ALLE Sektions-Szenen beim Start
	for i in range(_sections.size()):
		var section_data = _sections[i]
		var scene = load(section_data.scene_path) as PackedScene
		if scene:
			var instance = scene.instantiate()
			_sections[i].instance = instance # Speichere die Instanz im Array
			
			# Übergib product_box, falls es die HomeView ist
			if section_data.name == "Home" and "product_box_scene" in instance:
				instance.product_box_scene = product_box
				# Verbinde die Signale von der HomeView-Instanz
				_connect_home_view_signals(instance)
			
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

	load_popular_products()
	load_trending_products()
	
	Input.joy_connection_changed.connect(_on_joy_connection_changed) # Beibehalten

	details_view.move_back_to_main_view.connect(_on_move_back_to_main_view)
	details_view.image_load_requested.connect(_on_product_list_image_load_requested)

	_check_connected_controllers() 
	print("-----------------------------------------")
	_switch_to_section(0)
	_fetch_installed_apps()
	
# =============================================================================
# INPUT HANDLING (Nur _unhandled_input)
# =============================================================================

func _unhandled_input(event: InputEvent):
	var focused_control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused_control): return

	if top_button_bar.is_ancestor_of(focused_control):
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
	if is_instance_valid(home_button):
		print("Main: Received focus_exited_up, focusing Home button.") # Debug
		home_button.grab_focus()

		if is_instance_valid(_current_home_view_instance) and \
			_current_home_view_instance.name == "HomeView" and \
			_current_home_view_instance.has_method("scroll_to_top"):
			
			_current_home_view_instance.scroll_to_top()
		else:
			# Fallback, falls der global_scroll_container noch relevant ist oder als Notlösung
			if is_instance_valid(global_scroll_container): # global_scroll_container ist der alte in main.tscn
				global_scroll_container.scroll_vertical = 0
				print("Main: Reset global scroll position to top (fallback).") 
			
func _on_move_to_details_view(app_id: String, installed: bool):
	var focused_control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused_control) and is_instance_valid(_sections[_current_section_index].instance) and \
		_sections[_current_section_index].instance.is_ancestor_of(focused_control):
		# Try to get the ProductBox itself if focused_control is a child
		var product_box_candidate = focused_control
		while is_instance_valid(product_box_candidate) and not product_box_candidate is ProductBox and is_instance_valid(product_box_candidate.get_parent()):
			product_box_candidate = product_box_candidate.get_parent()

			if is_instance_valid(product_box_candidate) and product_box_candidate is ProductBox:
				_last_focused_product_box = product_box_candidate
				print("INFO Main: Stored last focused product box: ", _last_focused_product_box.name if _last_focused_product_box else "null")
			else:
				_last_focused_product_box = null # Fallback if we couldn't find the ProductBox
				print("WARN Main: Could not determine ProductBox from focused element.")
	else:
		_last_focused_product_box = null
		print("INFO Main: Focus was not on a product box when moving to details.")
		
	# Check if the focused control is within the currently active section view
	if is_instance_valid(focused_control) and is_instance_valid(_current_home_view_instance) and \
	   _current_home_view_instance.is_ancestor_of(focused_control):
		_last_focused_product_box = focused_control
	else:
		_last_focused_product_box = null
			
	details_view.set_initial_state(app_id, installed)
	details_view.load_details()
	select_sound.play()
	var tween = create_tween()
	var main_view_height = main_view.size.y
	var target_y = main_view_height
	tween.tween_property(main_view, "position:y", target_y, transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
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
	await tween.finished
	details_view.clear_data()
	
	if is_instance_valid(_last_focused_product_box) and _last_focused_product_box.is_inside_tree():
		_last_focused_product_box.grab_focus()
		print("INFO Main: Restored focus to: ", _last_focused_product_box.name)
	else:
		print("INFO Main: _last_focused_product_box is invalid or not in tree. Focusing default.")
		if is_instance_valid(_sections[_current_section_index].instance) and \
			_sections[_current_section_index].instance.has_method("focus_first_product_in_popular_list"): # Or a more generic "focus_default_element"
			_sections[_current_section_index].instance.focus_first_product_in_popular_list()
		elif is_instance_valid(home_button):
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
	if _flatpak_thread != null and _flatpak_thread.is_started() and not _flatpak_thread.is_finished():
		return

	print("INFO: Start Thread for fetching installed flatpaks...")
	_flatpak_thread = Thread.new()
	var callable = Callable(self, "_execute_flatpak_in_thread")
	var err = _flatpak_thread.start(callable)
	if err != OK:
		printerr("FEHLER: Could not start flatpak thread! Code: ", err)
		_flatpak_thread = null


func _execute_flatpak_in_thread():
	var spawn_cmd = "/usr/bin/flatpak-spawn"
	var spawn_args = ["--host", "flatpak", "list", "--app", "--columns=application"]
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
			var app_id = line.strip_edges()
			if not app_id.is_empty():
				_installed_flatpak_ids[app_id] = true
				count += 1
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
# Switches to the section at the given index by toggling visibility
func _switch_to_section(target_index: int):
	if target_index == _current_section_index or target_index < 0 or target_index >= _sections.size():
		return # Do nothing if already on the same section or index is invalid

	# Call the exiting hook for the old section
	var old_section_instance = _sections[_current_section_index].instance
	if is_instance_valid(old_section_instance) and old_section_instance.has_method("on_view_exiting"):
		old_section_instance.on_view_exiting()
	
	# Hide all section instances
	for section_data in _sections:
		if is_instance_valid(section_data.instance):
			section_data.instance.visible = false

	# Show the new section instance
	var new_section_instance = _sections[target_index].instance
	if is_instance_valid(new_section_instance):
		new_section_instance.visible = true
		if new_section_instance.has_method("on_view_entered"):
			new_section_instance.on_view_entered()
	
	_current_section_index = target_index
	_update_top_bar_button_focus()

# Called when a button in the top bar is pressed
func _on_top_bar_button_pressed(target_index: int):
	if is_instance_valid(select_sound):
		select_sound.play()
	_switch_to_section(target_index)

# Helper to connect signals for HomeView
func _connect_home_view_signals(home_view_node: Control):
	if not is_instance_valid(home_view_node): return

	if home_view_node.has_signal("move_to_details_view_requested"):
		home_view_node.move_to_details_view_requested.connect(_on_move_to_details_view)
	if home_view_node.has_signal("image_load_requested"):
		home_view_node.image_load_requested.connect(_on_product_list_image_load_requested)
	if home_view_node.has_signal("focus_exited_up_from_lists"):
		home_view_node.focus_exited_up_from_lists.connect(_on_product_list_focus_exited_up)
	if home_view_node.has_signal("load_new_page_requested"):
		home_view_node.load_new_page_requested.connect(_load_product_list)

# Helper to update focus on top bar buttons
func _update_top_bar_button_focus():
	for i in range(_sections.size()):
		var button_name = _sections[i].button_node_name
		var button_node = top_button_bar.get_node_or_null(button_name) as Button
		if is_instance_valid(button_node):
			if i == _current_section_index:
				# Optional: Add a visual style for the active button
				# button_node.set_pressed_no_signal(true) # Or a custom style
				if get_viewport().gui_get_focus_owner() == null or not top_button_bar.is_ancestor_of(get_viewport().gui_get_focus_owner()):
					button_node.grab_focus() # Grab focus if focus is not already in top bar
			else:
				pass
				# button_node.set_pressed_no_signal(false) # Reset style for inactive buttons

func refresh_installed_apps_list():
	print("INFO Main: Refreshing installed apps list due to recent install/uninstall.")
	_fetch_installed_apps()
