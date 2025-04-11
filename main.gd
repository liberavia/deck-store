extends Control

@export var product_box: PackedScene = preload("res://product_box.tscn")
@onready var product_container: HFlowContainer = $CanvasLayer/VBoxContainer/ScrollContainer/ProductFlowContainer
@onready var home_button: Button = $CanvasLayer/VBoxContainer/HBoxContainer/ButtonHome
@onready var top_button_bar: HBoxContainer = $CanvasLayer/VBoxContainer/HBoxContainer

var _product_box_min_width: float = 210.0 # Wird in _ready aktualisiert

# --- Cooldown Variablen ---
# Erhöhe diesen Wert, falls Doppelsprünge auftreten! 250ms ist ein guter Start.
const NAV_COOLDOWN_MS = 250
var last_nav_time = { "up": 0, "down": 0, "left": 0, "right": 0 }
# --------------------------


# =============================================================================
# LIFECYCLE METHODS
# =============================================================================

func _ready():
	# Produktbox Mindestbreite ermitteln
	var temp_box = product_box.instantiate()
	_product_box_min_width = temp_box.custom_minimum_size.x
	temp_box.queue_free()
	if _product_box_min_width <= 0:
		printerr("Warnung: custom_minimum_size.x nicht lesbar...")
		_product_box_min_width = 210.0

	# Buttons fokussierbar machen
	home_button.focus_mode = Control.FOCUS_ALL
	for btn in top_button_bar.get_children():
		if btn is Button: btn.focus_mode = Control.FOCUS_ALL

	# Signale verbinden
	home_button.pressed.connect(load_home_products)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	# Initiales Setup
	_check_connected_controllers()
	print("-----------------------------------------")
	load_home_products()

# KEINE _process(delta) Funktion in dieser Version!

# =============================================================================
# INPUT HANDLING (Nur _unhandled_input)
# =============================================================================

func _unhandled_input(event: InputEvent):
	# Prüft, ob eine der Navigationsaktionen ausgelöst wird (Keyboard, Button, ODER Achse über InputMap-Deadzone)
	var action_string = ""
	if event.is_action_pressed("ui_up"): action_string = "ui_up"
	elif event.is_action_pressed("ui_down"): action_string = "ui_down"
	elif event.is_action_pressed("ui_left"): action_string = "ui_left"
	elif event.is_action_pressed("ui_right"): action_string = "ui_right"
	elif event.is_action_pressed("select_entry"): action_string = "select_entry"

	# Nur handeln, wenn eine Aktion erkannt wurde
	if action_string != "":
		var current_time = Time.get_ticks_msec()

		# Prüfe Cooldown
		if current_time - last_nav_time.get(action_string, 0) > NAV_COOLDOWN_MS:
			print("Action '%s' triggered (Cooldown OK)" % action_string) # Debug
			# Versuche Navigation auszuführen
			if _handle_navigation(action_string):
				# Zeitstempel NUR aktualisieren, wenn Navigation erfolgreich war
				last_nav_time[action_string] = current_time
				# Event als behandelt markieren
				get_viewport().set_input_as_handled()
				print("   Action '%s' handled." % action_string) # Debug
			else: 
				print("   _handle_navigation returned false.") # Debug
		else:
			# Cooldown aktiv, Event trotzdem als behandelt markieren!
			print("Action '%s' on COOLDOWN" % action_string) # Debug
			get_viewport().set_input_as_handled()

	

# =============================================================================
# CORE NAVIGATION LOGIC (Unverändert von vorheriger sauberer Version)
# =============================================================================

func _handle_navigation(action_string: String) -> bool:
	var focused_control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused_control): return false

	var navigation_occurred = false
	var target_node_to_focus: Control = null

	# Fokus in Top Button Bar
	if top_button_bar.is_ancestor_of(focused_control):
		if action_string == "ui_down":
			target_node_to_focus = _get_first_focusable_product()
			if is_instance_valid(target_node_to_focus): navigation_occurred = true
		# Optional: Links/Rechts für Buttons hier implementieren, falls nötig

	# Fokus in Product Container
	elif product_container.is_ancestor_of(focused_control):
		var current_index = focused_control.get_index()
		var child_count = product_container.get_child_count()
		var target_index = -1

		if action_string == "ui_up":
			var is_in_first_row = false
			if child_count > 0 and current_index >= 0:
				var focused_pos_y = focused_control.global_position.y
				var first_child_pos_y = product_container.get_child(0).global_position.y
				if abs(focused_pos_y - first_child_pos_y) < 10.0: is_in_first_row = true

			if is_in_first_row:
				if is_instance_valid(home_button):
					target_node_to_focus = home_button
					navigation_occurred = true
			else:
				var num_columns = _get_current_column_count()
				target_index = current_index - num_columns
				if target_index >= 0: navigation_occurred = true

		elif action_string == "ui_down":
			var num_columns = _get_current_column_count()
			target_index = current_index + num_columns
			if target_index < child_count: navigation_occurred = true

		elif action_string == "ui_left":
			target_index = current_index - 1
			if target_index >= 0: navigation_occurred = true

		elif action_string == "ui_right":
			target_index = current_index + 1
			if target_index < child_count: navigation_occurred = true

		# Ziel-Node holen, falls per Index bestimmt
		if navigation_occurred and target_index != -1:
			if target_index >= 0 and target_index < child_count:
				target_node_to_focus = product_container.get_child(target_index) as Control
				if not (is_instance_valid(target_node_to_focus) and target_node_to_focus.focus_mode != Control.FOCUS_NONE):
					target_node_to_focus = null
					navigation_occurred = false
			else: navigation_occurred = false

	# Fokus setzen, wenn gültiges Ziel gefunden
	if navigation_occurred and is_instance_valid(target_node_to_focus):
		_focus_product_at_index(target_node_to_focus)
	elif navigation_occurred: # Intended but no target found
		navigation_occurred = false

	return navigation_occurred


# =============================================================================
# HELPER FUNCTIONS (Unverändert)
# =============================================================================

# --- KORRIGIERTE Hilfsfunktion: Berechnet die aktuelle Spaltenanzahl ---
func _get_current_column_count() -> int:
	if not is_instance_valid(product_container):
		printerr("_get_current_column_count: product_container ist ungültig.")
		return 1

	if product_container is HFlowContainer:
		# Berechne die Spalten basierend auf verfügbarer Breite und Box-Mindestbreite
		# print("DEBUG: Berechne Spalten für HFlowContainer") # Optional
		if _product_box_min_width <= 0:
			printerr("_get_current_column_count: _product_box_min_width ist ungültig.")
			return 1 # Verhindert Division durch Null

		var container_width = product_container.size.x
		# Hole den Abstand sicherheitshalber mit Fallback-Wert
		var h_separation = 50.0 # Dein Standardwert als Fallback
		# Prüfe, ob die Konstante im Theme definiert ist
		if product_container.has_theme_constant("h_separation"):
			h_separation = product_container.get_theme_constant("h_separation")
		# Alternativ prüfen, ob sie spezifisch für den Typ definiert ist (weniger üblich)
		elif product_container.has_theme_constant("h_separation", "HFlowContainer"):
			h_separation = product_container.get_theme_constant("h_separation", "HFlowContainer")

		# Verhindere Division durch Null oder negativen Wert
		var divisor = _product_box_min_width + h_separation
		if divisor <= 0:
			printerr("_get_current_column_count: Divisor (Breite+Abstand) ist <= 0.")
			return 1

		# Berechne die Spalten
		var columns = floor((container_width + h_separation) / divisor)
		# print("DEBUG: Berechnete Spalten: ", columns) # Optional
		return max(1, int(columns)) # Mindestens eine Spalte

	# Fallback für andere, unerwartete Container-Typen
	else:
		printerr("FEHLER: Unbekannter Container-Typ in _get_current_column_count: ", product_container.get_class())
		return 1 # Gib einen sicheren Standardwert zurück

# Verwendet direkten grab_focus
func _focus_product_at_index(target_node: Control):
	if not is_instance_valid(target_node): return
	if target_node.focus_mode != Control.FOCUS_NONE:
		target_node.grab_focus()

func _get_first_focusable_product() -> Control:
	if not is_instance_valid(product_container): return null
	for child in product_container.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			return child
	return null

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

func load_product_boxes(product_data: Array):
	for child in product_container.get_children(): child.queue_free()
	for product in product_data:
		var product_box_instance = product_box.instantiate()
		product_box_instance.focus_mode = Control.FOCUS_ALL
		product_box_instance.get_node("Panel/ProductName").text = product.get("name", "N/A")
		var image_url = product.get("icon")
		if image_url and not image_url.is_empty():
			var product_logo_rect = product_box_instance.get_node_or_null("Panel/ProductLogo") as TextureRect
			if product_logo_rect:
				var http_request_image = HTTPRequest.new(); add_child(http_request_image)
				http_request_image.request_completed.connect(_on_image_request_completed.bind(product_logo_rect, image_url, http_request_image))
				if http_request_image.request(image_url) != OK:
					if is_instance_valid(http_request_image): http_request_image.queue_free()
		product_container.add_child(product_box_instance)

func process_home_products_result(result, response_code, headers, body, http_request_list: HTTPRequest):
	if response_code == 200:
		var response_string = body.get_string_from_utf8(); var json = JSON.parse_string(response_string)
		if json is Dictionary and json.has('hits') and json['hits'] is Array:
			load_product_boxes(json['hits'])
	if is_instance_valid(http_request_list): http_request_list.queue_free()

func load_home_products():
	var http_request_list = HTTPRequest.new(); add_child(http_request_list)
	http_request_list.request_completed.connect(process_home_products_result.bind(http_request_list))
	var url = "https://flathub.org/api/v2/collection/popular?page=1&per_page=10&locale=en"
	if http_request_list.request(url) != OK:
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
