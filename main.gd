extends Control

@export var product_box: PackedScene = preload("res://product_box.tscn")
@export var product_list_scene: PackedScene = preload("res://product_list.tscn")

@onready var popular_product_list: ProductList = $CanvasLayer/VBoxContainer/ContentScrollContainer/VBoxContainer/PopularProductList
@onready var trending_product_list: ProductList = $CanvasLayer/VBoxContainer/ContentScrollContainer/VBoxContainer/TrendingProductList

@onready var home_button: Button = $CanvasLayer/VBoxContainer/HBoxContainer/ButtonHome
@onready var top_button_bar: HBoxContainer = $CanvasLayer/VBoxContainer/HBoxContainer
@onready var global_scroll_container: ScrollContainer = $CanvasLayer/VBoxContainer/ContentScrollContainer

var _installed_flatpak_ids: Dictionary = {}
var _flatpak_list_output: String = ""
var _flatpak_thread: Thread = null

# --- Cache-Constants ---
const CACHE_DURATION_MSEC: int = 3600 * 1000 # 1 Stunde
const API_CACHE_DIR = "user://cache/api/"

# =============================================================================
# LIFECYCLE METHODS
# =============================================================================

func _ready():
	var dir_access = DirAccess.open("user://")
	if dir_access:
		var absolute_cache_dir = ProjectSettings.globalize_path(API_CACHE_DIR)
		print("INFO: Cache-Directory (absolute Path): ", absolute_cache_dir)
		var err = DirAccess.make_dir_recursive_absolute(API_CACHE_DIR)
		if err != OK and err != ERR_ALREADY_EXISTS:
			printerr("Could not create cache directory: ", API_CACHE_DIR, ", Code: ", err)
	else:
		printerr("Could not open user:// directory.")
			
	if not popular_product_list.product_box_scene:
		popular_product_list.product_box_scene = product_box
	if not trending_product_list.product_box_scene:
		trending_product_list.product_box_scene = product_box

	home_button.focus_mode = Control.FOCUS_ALL
	for btn in top_button_bar.get_children():
		if btn is Button: btn.focus_mode = Control.FOCUS_ALL

	home_button.pressed.connect(load_popular_products)
	home_button.pressed.connect(load_trending_products)
	Input.joy_connection_changed.connect(_on_joy_connection_changed) # Beibehalten

	popular_product_list.image_load_requested.connect(_on_product_list_image_load_requested)
	popular_product_list.focus_exited_up.connect(_on_product_list_focus_exited_up)
	trending_product_list.image_load_requested.connect(_on_product_list_image_load_requested)
	trending_product_list.focus_exited_up.connect(_on_product_list_focus_exited_up)

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
			popular_product_list.focus_first_product()
			get_viewport().set_input_as_handled()
		elif action_string == "ui_left" or action_string == "ui_right":
			pass
	
# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

func _get_api_cache_filepath(url: String) -> String:
	var hash = url.md5_text() 
	return API_CACHE_DIR.path_join(hash + ".json")

func _on_product_list_image_load_requested(url: String, texture_rect: TextureRect):
	if not is_instance_valid(texture_rect):
		printerr("Image request for invalid texture_rect") # Debug
		return

	var http_request_image = HTTPRequest.new()
	add_child(http_request_image)
	http_request_image.request_completed.connect(
		_on_image_request_completed.bind(texture_rect, url, http_request_image)
	)

	var error = http_request_image.request(url)
	if error != OK:
		printerr("Error while starting image request %s: %s" % [url, error])
		if is_instance_valid(http_request_image): http_request_image.queue_free()

func _on_product_list_focus_exited_up():
	if is_instance_valid(home_button):
		print("Main: Received focus_exited_up, focusing Home button.") # Debug
		home_button.grab_focus()

		if is_instance_valid(global_scroll_container):
			global_scroll_container.scroll_vertical = 0
			print("Main: Reset global scroll position to top.") # Debug
		else:
			printerr("Main: GlobalScrollContainer nicht gefunden zum Zurücksetzen!")

# =============================================================================
# PRODUCT LOADING & CALLBACKS 
# =============================================================================

func _on_image_request_completed(result, response_code, headers, body, texture_rect: TextureRect, image_url: String, http_request_node: HTTPRequest):
	if not is_instance_valid(texture_rect):
		if is_instance_valid(http_request_node): http_request_node.queue_free(); return
	if response_code == 200:
		var image = Image.new(); var error = image.load_png_from_buffer(body)
		if error == OK: texture_rect.texture = ImageTexture.create_from_image(image)
	if is_instance_valid(http_request_node): http_request_node.queue_free()

func process_home_popular_products_result(result, response_code, headers, body, http_request_list: HTTPRequest):
	if response_code == 200:
		var response_string = body.get_string_from_utf8(); var json = JSON.parse_string(response_string)
		if json is Dictionary and json.has('hits') and json['hits'] is Array:
			if is_instance_valid(popular_product_list):
				popular_product_list.set_products(json['hits'])
			else:
				printerr("PopularProductList is invalid!")
	if is_instance_valid(http_request_list): http_request_list.queue_free()

func process_home_trending_products_result(result, response_code, headers, body, http_request_list: HTTPRequest):
	if response_code == 200:
		var response_string = body.get_string_from_utf8(); var json = JSON.parse_string(response_string)
		if json is Dictionary and json.has('hits') and json['hits'] is Array:
			if is_instance_valid(popular_product_list):
				trending_product_list.set_products(json['hits'])
			else:
				printerr("TrendingProductList is invalid!")
	if is_instance_valid(http_request_list): http_request_list.queue_free()

# =============================================================================
# DATA LOADING (Mit File Cache Logik)
# =============================================================================

func _load_product_list(url: String, target_list: ProductList):
	if not is_instance_valid(target_list):
		printerr("Versuche Daten für ungültige Zielliste zu laden, URL: ", url)
		return
	print("Anfrage für '%s': %s" % [target_list.title, url])

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
				var current_time = Time.get_ticks_msec()
				var cache_age = current_time - timestamp

				if cache_age < CACHE_DURATION_MSEC and api_data != null:
					print("--> Cache HIT for %s (Age: %d ms)" % [target_list.title, cache_age])
					_process_product_list_data(api_data, target_list)
					return
				else:
					print("--> Cache EXPIRED oder ungültig for %s (Age: %d ms)" % [target_list.title, cache_age])
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
		_on_product_list_request_completed.bind(http_request, url, target_list) # URL und Ziel binden
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
					"timestamp": Time.get_ticks_msec(),
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

				_process_product_list_data(api_json, target_list)
		else:
			printerr("JSON parse error for URL '%s'." % url)
	else:
		printerr("HTTP Error %d while requesting from '%s'." % [response_code, url])

	if is_instance_valid(http_request_list):
		http_request_list.queue_free()
		
func _process_product_list_data(json_data, target_list: ProductList):
	if not is_instance_valid(target_list): printerr("Invalid target list in _process_product_list_data"); return
	if json_data is Dictionary and json_data.has('hits') and json_data['hits'] is Array:
		target_list.set_products(json_data['hits'])
		print("Productlist '%s' updated." % target_list.title)
	else: printerr("Unexpected data structure for list '%s'." % target_list.title)

func load_popular_products():
	_load_product_list("https://flathub.org/api/v2/collection/popular?page=1&per_page=10&locale=en", popular_product_list)

func load_trending_products():
	_load_product_list("https://flathub.org/api/v2/collection/trending?page=1&per_page=10&locale=en", trending_product_list)

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
	else:
		printerr("ERROR: 'flatpak list' failed with code: ", exit_code)
		printerr("Flatpak Output: ", output)

	if _flatpak_thread != null and _flatpak_thread.is_started():
		_flatpak_thread.wait_to_finish()
	_flatpak_thread = null

func _update_all_lists_install_status():
	print("INFO: Update installed state in lists...")
	if is_instance_valid(popular_product_list):
		popular_product_list.update_installed_status(_installed_flatpak_ids)
	if is_instance_valid(trending_product_list):
		trending_product_list.update_installed_status(_installed_flatpak_ids)
