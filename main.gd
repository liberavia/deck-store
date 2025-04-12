extends Control

@export var product_box: PackedScene = preload("res://product_box.tscn")
@export var product_list_scene: PackedScene = preload("res://product_list.tscn")

@onready var popular_product_list: ProductList = $CanvasLayer/VBoxContainer/ContentScrollContainer/VBoxContainer/PopularProductList
@onready var trending_product_list: ProductList = $CanvasLayer/VBoxContainer/ContentScrollContainer/VBoxContainer/TrendingProductList

@onready var home_button: Button = $CanvasLayer/VBoxContainer/HBoxContainer/ButtonHome
@onready var top_button_bar: HBoxContainer = $CanvasLayer/VBoxContainer/HBoxContainer
@onready var global_scroll_container: ScrollContainer = $CanvasLayer/VBoxContainer/ContentScrollContainer

# --- Cache-Konstanten ---
const CACHE_DURATION_MSEC: int = 3600 * 1000 # 1 Stunde
const API_CACHE_DIR = "user://cache/api/"

# =============================================================================
# LIFECYCLE METHODS
# =============================================================================

func _ready():
	var dir_access = DirAccess.open("user://")
	if dir_access:
		var absolute_cache_dir = ProjectSettings.globalize_path(API_CACHE_DIR)
		print("INFO: Cache-Verzeichnis (absoluter Pfad): ", absolute_cache_dir)
		var err = DirAccess.make_dir_recursive_absolute(API_CACHE_DIR)
		if err != OK and err != ERR_ALREADY_EXISTS:
			printerr("Konnte Cache-Verzeichnis nicht erstellen: ", API_CACHE_DIR, ", Fehlercode: ", err)
	else:
		printerr("Konnte user:// Verzeichnis nicht öffnen.")
			
	# Konfiguriere die Produktlisten-Instanz (falls Exports nicht im Editor gesetzt)
	if not popular_product_list.product_box_scene:
		popular_product_list.product_box_scene = product_box
	if not trending_product_list.product_box_scene:
		trending_product_list.product_box_scene = product_box

	# Buttons fokussierbar machen
	home_button.focus_mode = Control.FOCUS_ALL
	for btn in top_button_bar.get_children():
		if btn is Button: btn.focus_mode = Control.FOCUS_ALL

	# Signale verbinden
	home_button.pressed.connect(load_popular_products)
	home_button.pressed.connect(load_trending_products)
	Input.joy_connection_changed.connect(_on_joy_connection_changed) # Beibehalten

	# Signale VON der Produktliste verbinden
	popular_product_list.image_load_requested.connect(_on_product_list_image_load_requested)
	popular_product_list.focus_exited_up.connect(_on_product_list_focus_exited_up)
	trending_product_list.image_load_requested.connect(_on_product_list_image_load_requested)
	trending_product_list.focus_exited_up.connect(_on_product_list_focus_exited_up)

	_check_connected_controllers() 
	print("-----------------------------------------")
	load_popular_products()
	load_trending_products()

# =============================================================================
# INPUT HANDLING (Nur _unhandled_input)
# =============================================================================

# --- ANGEPASST: _unhandled_input behandelt nur noch Button-Leiste und Übergänge ---
func _unhandled_input(event: InputEvent):
	var focused_control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused_control): return

	# Nur handeln, wenn Fokus in der Button-Leiste ist
	if top_button_bar.is_ancestor_of(focused_control):
		var action_string = ""
		# Prüfe auf Keyboard oder Buttons
		if event.is_action_pressed("ui_down"): action_string = "ui_down"
		elif event.is_action_pressed("ui_left"): action_string = "ui_left" # Für Navigation innerhalb der Buttons
		elif event.is_action_pressed("ui_right"): action_string = "ui_right" # Für Navigation innerhalb der Buttons

		if action_string == "ui_down":
			# Fokus an die Produktliste übergeben
			popular_product_list.focus_first_product()
			get_viewport().set_input_as_handled()
		elif action_string == "ui_left" or action_string == "ui_right":
			# Lasse Godots Standard-Handling für links/rechts innerhalb der HBox zu,
			# AUSSER wir wollen Wrap-Around oder anderes Verhalten.
			# Wenn Standard ok ist, kein set_input_as_handled() hier.
			pass # Oder implementiere Logik mit find_prev/next_valid_focus

	# Kein else mehr nötig, da die Produktliste ihren Input selbst behandelt
	

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Erstellt den Dateipfad für eine gegebene URL im Cache
func _get_api_cache_filepath(url: String) -> String:
	var hash = url.md5_text() 
	return API_CACHE_DIR.path_join(hash + ".json")

# --- NEU: Signal-Handler für Bildanfragen von ProductList ---
func _on_product_list_image_load_requested(url: String, texture_rect: TextureRect):
	if not is_instance_valid(texture_rect):
		# print("Image request for invalid texture_rect") # Debug
		return

	var http_request_image = HTTPRequest.new()
	add_child(http_request_image) # Füge als Kind des Haupt-Nodes hinzu

	# Verbinde mit dem allgemeinen Image-Callback (bleibt gleich)
	# Wichtig: Binde texture_rect und den Request-Node selbst mit!
	http_request_image.request_completed.connect(
		_on_image_request_completed.bind(texture_rect, url, http_request_image)
	)

	var error = http_request_image.request(url)
	if error != OK:
		printerr("Fehler beim Starten des Bild-Requests für %s: %s" % [url, error])
		if is_instance_valid(http_request_image): http_request_image.queue_free()

# --- NEU: Signal-Handler für Fokusverlust nach oben von ProductList ---
func _on_product_list_focus_exited_up():
	print("Main: Received focus_exited_up") # Debug
	# Setze Fokus zurück auf den Home-Button (oder einen anderen)
	if is_instance_valid(home_button):
		print("Main: Received focus_exited_up, focusing Home button.") # Debug
		home_button.grab_focus()

		if is_instance_valid(global_scroll_container):
			# Setze die vertikale Scroll-Position auf 0 Pixel
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

# Lädt Daten für eine spezifische Liste/URL
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
			file.close() # Datei sofort schließen
			var cache_content = JSON.parse_string(json_string)

			if cache_content is Dictionary:
				var timestamp = cache_content.get("timestamp", 0)
				var api_data = cache_content.get("api_data")
				var current_time = Time.get_ticks_msec()
				var cache_age = current_time - timestamp

				if cache_age < CACHE_DURATION_MSEC and api_data != null:
					print("--> Cache HIT für %s (Alter: %d ms)" % [target_list.title, cache_age])
					# Verwende Daten aus dem Cache direkt
					_process_product_list_data(api_data, target_list)
					return # Kein HTTP-Request nötig
				else:
					print("--> Cache EXPIRED oder ungültig für %s (Alter: %d ms)" % [target_list.title, cache_age])
					# Optional: Lösche abgelaufene Datei (Fehler ignorieren, falls nicht existent)
					DirAccess.remove_absolute(cache_filepath)
			else:
				print("--> Cache-Datei-Inhalt ungültig (kein Dictionary) für %s: %s" % [target_list.title, cache_filepath.get_file()])
				# Optional: Lösche ungültige Datei
				DirAccess.remove_absolute(cache_filepath)
		else:
			printerr("--> Fehler beim Öffnen der Cache-Datei %s: %s" % [cache_filepath.get_file(), open_error])
			if is_instance_valid(file): file.close() # Sicherstellen, dass Handle geschlossen wird
	else:
		print("-> Cache MISS für %s" % target_list.title)
	# --- End File Cache Check ---

	# Kein gültiger Cache -> HTTP Request starten
	var http_request = HTTPRequest.new()
	add_child(http_request) # Node muss im Baum sein
	http_request.request_completed.connect(
		_on_product_list_request_completed.bind(http_request, url, target_list) # URL und Ziel binden
	)
	var error = http_request.request(url)
	if error != OK:
		printerr("Fehler beim Starten des Requests für '%s' (%s): %s" % [target_list.title, url, error])
		if is_instance_valid(http_request): http_request.queue_free()

# --- Callback für HTTP-Requests der Produktlisten ---
func _on_product_list_request_completed(result, response_code, headers, body, http_request_list: HTTPRequest, url: String, target_list: ProductList):
	if not is_instance_valid(target_list):
		printerr("Ziel-ProductList ungültig im Callback für URL: ", url)
		if is_instance_valid(http_request_list): http_request_list.queue_free(); return

	if response_code == 200:
		var response_string = body.get_string_from_utf8()
		var api_json = JSON.parse_string(response_string)

		if api_json != null:
			 # Hier könnte man noch prüfen, ob api_json wirklich Dictionary/Array ist
			 # if api_json is Dictionary or api_json is Array: # Je nachdem was die API liefert

				# --- NEU: Im Datei-Cache speichern ---
				var data_to_cache = {
					"timestamp": Time.get_ticks_msec(),
					"api_data": api_json # Speichere das geparste JSON-Objekt
				}
				var json_string_to_cache = JSON.stringify(data_to_cache, "  ") # Mit Einrückung für Lesbarkeit
				var cache_filepath = _get_api_cache_filepath(url)

				var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
				var open_error = FileAccess.get_open_error()
				if open_error == OK:
					file.store_string(json_string_to_cache)
					# Kein flush nötig für store_string, close reicht
					file.close()
					print("-> Daten für '%s' in Datei-Cache gespeichert: %s" % [url.get_file(), cache_filepath.get_file()])
				else:
					printerr("--> Fehler beim Schreiben der Cache-Datei %s: %s" % [cache_filepath.get_file(), open_error])
					if is_instance_valid(file): file.close()
				# -------------------------------

				# Verarbeite die frisch geladenen Daten
				_process_product_list_data(api_json, target_list)
			 # else: printerr(...) # Ggf. Typ-Fehler loggen
		else:
			printerr("JSON Parse Fehler für URL '%s'." % url)
	else:
		printerr("HTTP Fehler %d beim Laden von '%s'." % [response_code, url])

	# Request Node freigeben
	if is_instance_valid(http_request_list):
		http_request_list.queue_free()
		
# --- Verarbeitung der Daten (unverändert) ---
func _process_product_list_data(json_data, target_list: ProductList):
	if not is_instance_valid(target_list): printerr("Ungültige Ziel-Liste in _process_product_list_data"); return
	if json_data is Dictionary and json_data.has('hits') and json_data['hits'] is Array:
		target_list.set_products(json_data['hits'])
		print("Produktliste '%s' aktualisiert." % target_list.title)
	else: printerr("Unerwartete Datenstruktur für Liste '%s'." % target_list.title)

# Wrapper-Funktionen für spezifische Listen
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
		print("Beim Start erkannte Controller:")
		for device_id in connected_joypads: print("  Device ID: ", device_id, ", Name: ", Input.get_joy_name(device_id))
	else: print("Keine Controller beim Start von Godot erkannt.")

func _on_joy_connection_changed(device_id: int, connected: bool):
	if connected: print("CONTROLLER VERBUNDEN:\n  Device ID: ", device_id, ", Name: ", Input.get_joy_name(device_id))
	else: print("CONTROLLER GETRENNT:\n  Device ID: ", device_id)
	print("-----------------------------------------")
