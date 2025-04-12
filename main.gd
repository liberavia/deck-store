extends Control

@export var product_box: PackedScene = preload("res://product_box.tscn")
@export var product_list_scene: PackedScene = preload("res://product_list.tscn")

@onready var popular_product_list: ProductList = $CanvasLayer/VBoxContainer/ContentScrollContainer/VBoxContainer/PopularProductList
@onready var trending_product_list: ProductList = $CanvasLayer/VBoxContainer/ContentScrollContainer/VBoxContainer/TrendingProductList

@onready var home_button: Button = $CanvasLayer/VBoxContainer/HBoxContainer/ButtonHome
@onready var top_button_bar: HBoxContainer = $CanvasLayer/VBoxContainer/HBoxContainer
@onready var global_scroll_container: ScrollContainer = $CanvasLayer/VBoxContainer/ContentScrollContainer

# =============================================================================
# LIFECYCLE METHODS
# =============================================================================

func _ready():
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
# CORE NAVIGATION LOGIC (Unverändert von vorheriger sauberer Version)
# =============================================================================



# =============================================================================
# HELPER FUNCTIONS (Unverändert)
# =============================================================================

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
# PRODUCT LOADING & CALLBACKS (Unverändert)
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

func load_popular_products():
	var http_request_list = HTTPRequest.new(); add_child(http_request_list)
	http_request_list.request_completed.connect(process_home_popular_products_result.bind(http_request_list))
	var url_popular = "https://flathub.org/api/v2/collection/popular?page=1&per_page=15&locale=en"
	if http_request_list.request(url_popular) != OK:
		if is_instance_valid(http_request_list): http_request_list.queue_free()
	
func load_trending_products():
	var http_request_list = HTTPRequest.new(); add_child(http_request_list)
	http_request_list.request_completed.connect(process_home_trending_products_result.bind(http_request_list))
	var url_trending = "https://flathub.org/api/v2/collection/trending?page=1&per_page=15&locale=en"
	if http_request_list.request(url_trending) != OK:
		if is_instance_valid(http_request_list): http_request_list.queue_free()

# =============================================================================
# JOY CONNECTION CALLBACKS (Unverändert)
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
