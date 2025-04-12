# product_list.gd
class_name ProductList # Ermöglicht Typ-Hinting in main.gd
extends Control

# --- Konfiguration ---
enum DisplayMode { MULTI_LINE_WRAP, SINGLE_LINE_SCROLL }
@export var display_mode: DisplayMode = DisplayMode.MULTI_LINE_WRAP
@export var product_box_scene: PackedScene
@export var title: String
@export var min_rows: int = 2

# --- Signale ---
# Wird gesendet, wenn von der obersten Reihe nach oben navigiert wird
signal focus_exited_up
# Wird gesendet, wenn ein Bild geladen werden soll
signal image_load_requested(url: String, texture_rect: TextureRect)

# --- Nodes ---
@onready var multi_line_scroll: ScrollContainer = $VBoxContainer/MultiLineScroll
@onready var multi_line_content: HFlowContainer = $VBoxContainer/MultiLineScroll/MultiLineContent
@onready var single_line_scroll: ScrollContainer = $VBoxContainer/SingleLineScroll
@onready var single_line_content: HBoxContainer = $VBoxContainer/SingleLineScroll/SingleLineContent
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var inner_vbox: VBoxContainer = $VBoxContainer

# --- Interne Variablen ---
var _active_content_container: Container # Hält den aktuell genutzten Container
var _product_box_min_width: float = 210.0 # Wird aus Instanz geholt
var _product_box_min_height: float = 350.0

# --- Cooldown Variablen (hierher verschoben) ---
const NAV_COOLDOWN_MS = 250
var last_nav_time = { "up": 0, "down": 0, "left": 0, "right": 0 }
# ----------------------------------------------

func _ready():
	# Hole Breite UND Höhe der Produktbox
	if product_box_scene:
		var temp_box = product_box_scene.instantiate()
		_product_box_min_width = temp_box.custom_minimum_size.x
		_product_box_min_height = temp_box.custom_minimum_size.y # <<< NEU
		temp_box.queue_free()
		if _product_box_min_width <= 0: _product_box_min_width = 210.0
		if _product_box_min_height <= 0: _product_box_min_height = 350.0 # <<< NEU Fallback
	else:
		printerr("ProductList: product_box_scene ist nicht zugewiesen!")
		_product_box_min_width = 210.0 # Fallback
		_product_box_min_height = 350.0 # Fallback
			
	if title_label: # Sicherstellen, dass das Label gefunden wurde
		if not title.is_empty():
			title_label.text = title
			title_label.visible = true
		else:
			title_label.visible = false # Label ausblenden, wenn kein Titel gesetzt ist
	else:
		printerr("TitleLabel nicht gefunden in ProductList!")	# Layout basierend auf Modus aktivieren
		
	if display_mode == DisplayMode.MULTI_LINE_WRAP:
		multi_line_scroll.visible = true
		single_line_scroll.visible = false
		_active_content_container = multi_line_content
		print("ProductList: Multi-line mode activated.")
	else: # SINGLE_LINE_SCROLL
		multi_line_scroll.visible = false
		single_line_scroll.visible = true
		_active_content_container = single_line_content
		print("ProductList: Single-line mode activated.")

	# Mindestbreite für Spaltenberechnung holen (falls Multi-line)
	if product_box_scene:
		var temp_box = product_box_scene.instantiate()
		_product_box_min_width = temp_box.custom_minimum_size.x
		temp_box.queue_free()
		if _product_box_min_width <= 0: _product_box_min_width = 210.0
	else:
		printerr("ProductList: product_box_scene ist nicht zugewiesen!")
		
	# Berechne initiale Mindesthöhe
	# Warten auf nächsten Frame, damit Label Größe berechnet hat? Sicherer.
	call_deferred("_update_minimum_height") # <<< NEU (aufruf deferred)

	print("--- ProductList _ready END für '", title, "' ---")

# --- Öffentliche Methode zum Setzen der Produkte ---
func set_products(product_data: Array):
	if not is_instance_valid(_active_content_container):
		printerr("ProductList: Aktiver Content Container ist ungültig!")
		return

	# Alte Produkte löschen
	for child in _active_content_container.get_children():
		child.queue_free()

	if not product_box_scene:
		printerr("ProductList: product_box_scene ist nicht zugewiesen!")
		return

	# Neue Produkte erstellen
	for product in product_data:
		var product_box_instance = product_box_scene.instantiate()
		product_box_instance.focus_mode = Control.FOCUS_ALL # Wichtig!

		# Name setzen
		product_box_instance.get_node("Panel/ProductName").text = product.get("name", "N/A")

		# Bild laden anfordern (via Signal)
		var image_url = product.get("icon")
		if image_url and not image_url.is_empty():
			var product_logo_rect = product_box_instance.get_node_or_null("Panel/ProductLogo") as TextureRect
			if product_logo_rect:
				emit_signal("image_load_requested", image_url, product_logo_rect)
			# else: print("Panel/ProductLogo nicht gefunden in Instanz.")

		# Zum aktiven Container hinzufügen
		_active_content_container.add_child(product_box_instance)

	var final_child_count = 0
	if is_instance_valid(_active_content_container):
		final_child_count = _active_content_container.get_child_count()
	print("--- ProductList set_products END ---")
	print("Final child count in active container: ", final_child_count)
	
	# Optional: Fokus auf das erste Element setzen, wenn die Liste gefüllt wird?
	# call_deferred("focus_first_product")

func _update_minimum_height():
	# Stelle sicher, dass Nodes gültig sind
	if not is_instance_valid(self) or not is_instance_valid(inner_vbox) or \
	   not is_instance_valid(title_label) or not is_instance_valid(_active_content_container):
		printerr("Nodes für Mindesthöhenberechnung ungültig in '%s'." % title)
		return # Frühzeitig abbrechen

	await get_tree().process_frame # Warte auf nächsten Frame für korrekte Größen

	var calculated_min_height: float = 0.0
	var title_height: float = 0.0

	# Höhe des Titels berücksichtigen (nur wenn sichtbar)
	if title_label.visible:
		# title_height = title_label.size.y # size.y ist oft 0 wenn Label nicht expandiert
		title_height = title_label.get_combined_minimum_size().y # Sicherer Weg

	# Abstand im inneren VBoxContainer
	var vbox_separation = inner_vbox.get_theme_constant("separation", "VBoxContainer")

	# Mindesthöhe des Inhaltsbereichs berechnen
	var content_min_height: float = 0.0
	if display_mode == DisplayMode.MULTI_LINE_WRAP:
		# Höhe basierend auf min_rows
		var num_rows = max(1, min_rows) # Mindestens eine Reihe anzeigen
		var content_v_separation = _active_content_container.get_theme_constant("v_separation", "HFlowContainer")
		# Höhe = (Anzahl Reihen * Box Höhe) + (Anzahl Abstände * Abstand Höhe)
		content_min_height = (_product_box_min_height * num_rows) + (content_v_separation * max(0, num_rows - 1))
	else: # SINGLE_LINE_SCROLL
		# Höhe basiert auf einer Reihe
		content_min_height = _product_box_min_height

	# Gesamte Mindesthöhe = Titel + Abstand (falls Titel da) + Inhalt
	calculated_min_height = title_height + content_min_height
	if title_label.visible:
		calculated_min_height += vbox_separation

	# Füge kleines Padding hinzu, damit es nicht gequetscht aussieht
	calculated_min_height += 10.0 # Optionales Padding

	print("Update Min Height für '%s': %.1f (Title: %.1f, Content: %.1f)" % [title, calculated_min_height, title_height, content_min_height])
	# Setze die berechnete Mindesthöhe für das ProductList Control selbst
	self.custom_minimum_size.y = calculated_min_height


# --- Öffentliche Methode zum Fokussieren des ersten Elements ---
func focus_first_product():
	var first_focusable = _get_first_focusable_product()
	if is_instance_valid(first_focusable):
		first_focusable.grab_focus()
		# Sicherstellen, dass es sichtbar wird (falls gescrollt werden muss)
		if multi_line_scroll.visible: multi_line_scroll.ensure_control_visible(first_focusable)
		elif single_line_scroll.visible: single_line_scroll.ensure_control_visible(first_focusable)


# --- Input Handling (hierher verschoben, angepasst) ---
func _unhandled_input(event: InputEvent):
	# Prüft NUR, ob dieses Control oder eines seiner Kinder den Fokus hat
	if not has_focus() and not get_viewport().gui_get_focus_owner(): # Prüft, ob Fokus innerhalb dieses Controls liegt
		# Wenn Fokus nicht hier ist, Event ignorieren und weitergeben
		return

	# Ab hier hat diese Liste oder ein Kind davon den Fokus

	var action_string = ""
	# Prüfe Keyboard ODER Buttons (D-Pad)
	if event.is_action_pressed("ui_up"): action_string = "ui_up"
	elif event.is_action_pressed("ui_down"): action_string = "ui_down"
	elif event.is_action_pressed("ui_left"): action_string = "ui_left"
	elif event.is_action_pressed("ui_right"): action_string = "ui_right"

	if action_string != "":
		var current_time = Time.get_ticks_msec()
		if current_time - last_nav_time.get(action_string, 0) > NAV_COOLDOWN_MS:
			# print("ProductList Handling Action: ", action_string) # Debug
			if _handle_navigation(action_string):
				last_nav_time[action_string] = current_time
				get_viewport().set_input_as_handled()
				# print("   ProductList handled: ", action_string) # Debug
		else:
			# print("ProductList Action %s on COOLDOWN" % action_string) # Debug
			get_viewport().set_input_as_handled() # Cooldown aktiv, trotzdem behandeln


# --- Core Navigation Logic (hierher verschoben, angepasst) ---
func _handle_navigation(action_string: String) -> bool:
	# Hole das fokussierte Kind *innerhalb* dieses Controls
	var focused_control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused_control) or not _active_content_container.is_ancestor_of(focused_control):
		# Fokus ist nicht auf einem Produkt im aktiven Container
		# Könnte das List-Control selbst sein oder außerhalb
		# print("_handle_navigation: Fokus nicht auf Produktbox.") # Debug
		return false

	var navigation_occurred = false
	var target_node_to_focus: Control = null

	# Fokus ist im Product Container
	var current_index = focused_control.get_index()
	var child_count = _active_content_container.get_child_count()

	if action_string == "ui_up":
		var is_in_first_row = false
		if child_count > 0 and current_index >= 0:
			# Im HBoxContainer ist die Y-Prüfung nicht sinnvoll, prüfe nur Index
			if _active_content_container is HFlowContainer:
				var focused_pos_y = focused_control.global_position.y
				var first_child_pos_y = _active_content_container.get_child(0).global_position.y
				if abs(focused_pos_y - first_child_pos_y) < 10.0: is_in_first_row = true
			elif _active_content_container is HBoxContainer:
				is_in_first_row = true # In einer HBox ist man immer in der "ersten" Reihe

		if is_in_first_row:
			# Signal senden, dass Fokus nach oben verloren geht
			print("ProductList: Emitting focus_exited_up") # Debug
			emit_signal("focus_exited_up")
			# Fokuswechsel wird von main.gd gehandhabt, hier nur Signal
			navigation_occurred = true # Markieren, dass die Aktion hier endet
		else: # Nicht in erster Reihe (nur bei HFlowContainer relevant)
			var num_columns = _get_current_column_count()
			var target_index = current_index - num_columns
			if target_index >= 0:
				target_node_to_focus = _get_child_if_focusable(target_index)
				if target_node_to_focus: navigation_occurred = true

	elif action_string == "ui_down":
		# Nur relevant für HFlowContainer
		if _active_content_container is HFlowContainer:
			var num_columns = _get_current_column_count()
			var target_index = current_index + num_columns
			if target_index < child_count:
				target_node_to_focus = _get_child_if_focusable(target_index)
			if target_node_to_focus: navigation_occurred = true

	elif action_string == "ui_left":
		var target_index = current_index - 1
		if target_index >= 0:
			target_node_to_focus = _get_child_if_focusable(target_index)
			if target_node_to_focus: navigation_occurred = true

	elif action_string == "ui_right":
		var target_index = current_index + 1
		if target_index < child_count:
			target_node_to_focus = _get_child_if_focusable(target_index)
			if target_node_to_focus: navigation_occurred = true

	# Fokus setzen, wenn gültiges Ziel gefunden wurde
	if navigation_occurred and is_instance_valid(target_node_to_focus):
		_focus_product_at_index(target_node_to_focus)
	# elif navigation_occurred: # Navigation endet hier (z.B. focus_exited_up)
	#	 pass

	# Gib true zurück, wenn Aktion hier behandelt wurde (auch wenn kein Fokuswechsel stattfand, z.B. focus_exited_up)
	return navigation_occurred


# --- Helper Functions (hierher verschoben, angepasst) ---

# Gibt Spalten zurück, angepasst für Container-Typen
func _get_current_column_count() -> int:
	if not is_instance_valid(_active_content_container): return 1
	if _active_content_container is GridContainer: # Falls GridContainer jemals verwendet wird
		return max(1, _active_content_container.columns)
	elif _active_content_container is HFlowContainer:
		if _product_box_min_width <= 0: return 1
		var container_width = _active_content_container.size.x
		var h_separation = _active_content_container.get_theme_constant("h_separation", "HFlowContainer")
		var divisor = _product_box_min_width + h_separation
		if divisor <= 0: return 1
		var columns = floor((container_width + h_separation) / divisor)
		return max(1, int(columns))
	elif _active_content_container is HBoxContainer:
		# Eine HBox hat effektiv unendlich Spalten in einer Reihe
		return _active_content_container.get_child_count() # Oder einfach eine sehr große Zahl?
	else: return 1

# Holt Kind-Node am Index, prüft ob fokussierbar
func _get_child_if_focusable(index: int) -> Control:
	if index >= 0 and index < _active_content_container.get_child_count():
		var node = _active_content_container.get_child(index) as Control
		if is_instance_valid(node) and node.focus_mode != Control.FOCUS_NONE:
			return node
	return null

# Fokussiert ein Node
func _focus_product_at_index(target_node: Control):
	if is_instance_valid(target_node):
		if target_node.focus_mode != Control.FOCUS_NONE:
			target_node.grab_focus()
			# Scrollen des AKTIVEN ScrollContainers sicherstellen
			if display_mode == DisplayMode.MULTI_LINE_WRAP and is_instance_valid(multi_line_scroll):
				multi_line_scroll.ensure_control_visible(target_node)
			elif display_mode == DisplayMode.SINGLE_LINE_SCROLL and is_instance_valid(single_line_scroll):
				single_line_scroll.ensure_control_visible(target_node)
				
# Findet das erste fokussierbare Kind
func _get_first_focusable_product() -> Control:
	if not is_instance_valid(_active_content_container): return null
	for child in _active_content_container.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			return child
	return null
