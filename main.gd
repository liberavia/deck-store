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
			
	var home_view_scene = preload("res://sections/home_view.tscn")
	if home_view_scene:
		_current_home_view_instance = home_view_scene.instantiate()
		if _current_home_view_instance.has_method("set_product_box_scene_path") or "product_box_scene" in _current_home_view_instance:
			_current_home_view_instance.product_box_scene = product_box
		else:
			printerr("main.gd ERROR: HomeView instance does not have 'product_box_scene' export var.")

		if _current_home_view_instance.has_signal("move_to_details_view_requested"):
			_current_home_view_instance.move_to_details_view_requested.connect(_on_move_to_details_view)
		if _current_home_view_instance.has_signal("image_load_requested"):
			_current_home_view_instance.image_load_requested.connect(_on_product_list_image_load_requested) # Dein Handler bleibt gleich
		if _current_home_view_instance.has_signal("focus_exited_up_from_lists"):
			_current_home_view_instance.focus_exited_up_from_lists.connect(_on_product_list_focus_exited_up)
		if _current_home_view_instance.has_signal("load_new_page_requested"):
			_current_home_view_instance.load_new_page_requested.connect(_load_product_list) # Dein Handler bleibt gleich

		section_view_container.add_child(_current_home_view_instance)
		_current_home_view_instance.visible = true 
		
		# Optional: Rufe eine Methode in HomeView auf, um initiale Daten zu laden,
		# oder die load_popular/trending_products Funktionen unten rufen Methoden in HomeView auf.
		# Für den Moment lassen wir die load_... Funktionen unten die Logik steuern.
	else:
		printerr("ERROR: HomeView.tscn could not be preloaded!")

	home_button.focus_mode = Control.FOCUS_ALL
	for btn in top_button_bar.get_children():
		if btn is Button: btn.focus_mode = Control.FOCUS_ALL

	home_button.pressed.connect(load_popular_products)
	home_button.pressed.connect(load_trending_products)
	Input.joy_connection_changed.connect(_on_joy_connection_changed) # Beibehalten

	details_view.move_back_to_main_view.connect(_on_move_back_to_main_view)
	details_view.image_load_requested.connect(_on_product_list_image_load_requested)

	_check_connected_controllers() 
	print("-----------------------------------------")
	load_popular_products()
	load_trending_products()
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
	if is_instance_valid(_current_home_view_instance) and _current_home_view_instance.has_method("load_popular_products_in_view"):
		_current_home_view_instance.load_popular_products_in_view()

func load_trending_products():
	if is_instance_valid(_current_home_view_instance) and _current_home_view_instance.has_method("load_trending_products_in_view"):
		_current_home_view_instance.load_trending_products_in_view()

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

		if is_instance_valid(global_scroll_container):
			global_scroll_container.scroll_vertical = 0
			print("Main: Reset global scroll position to top.") # Debug
		else:
			printerr("Main: GlobalScrollContainer nicht gefunden zum Zurücksetzen!")

func _on_move_to_details_view(app_id: String, installed: bool):
	var focused_control = get_viewport().gui_get_focus_owner()
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
	
	if is_instance_valid(_last_focused_product_box):
		_last_focused_product_box.grab_focus()
		_last_focused_product_box = null
	else:
		# Delegate focus back to the home view instance
		if is_instance_valid(_current_home_view_instance) and _current_home_view_instance.has_method("focus_first_product_in_popular_list"):
			_current_home_view_instance.focus_first_product_in_popular_list()
		elif is_instance_valid(home_button): 
			home_button.grab_focus()
			
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
	print("INFO: Update installed state in lists...")
	if is_instance_valid(_current_home_view_instance) and _current_home_view_instance.has_method("update_internal_list_install_status"):
		_current_home_view_instance.update_internal_list_install_status(_installed_flatpak_ids)
