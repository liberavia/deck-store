# product_list.gd
class_name ProductList
extends Control

# --- Configuraton ---
enum DisplayMode { MULTI_LINE_WRAP, SINGLE_LINE_SCROLL }
@export var display_mode: DisplayMode = DisplayMode.MULTI_LINE_WRAP
@export var product_box_scene: PackedScene
@export var title: String = "":
	set(value):
		title = value
		if is_instance_valid(title_label):
			title_label.text = title
			title_label.visible = not title.is_empty()
@export var min_rows: int = 2
@export var use_auto_height: bool = true

# --- Signals ---
signal focus_exited_up
signal image_load_requested(url: String, texture_rect: TextureRect)
signal move_to_details_view(app_id: String, installed: bool)
signal load_new_page(url: String, target_list: ProductList)
signal products_loaded

# --- Nodes ---
@onready var multi_line_scroll: ScrollContainer = $VBoxContainer/MultiLineScroll
@onready var multi_line_content: HFlowContainer = $VBoxContainer/MultiLineScroll/MultiLineContent
@onready var single_line_scroll: ScrollContainer = $VBoxContainer/SingleLineScroll
@onready var single_line_content: HBoxContainer = $VBoxContainer/SingleLineScroll/SingleLineContent
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var inner_vbox: VBoxContainer = $VBoxContainer
@onready var prev_button: Button = $VBoxContainer/PaginationBar/PrevButton
@onready var next_button: Button = $VBoxContainer/PaginationBar/NextButton
@onready var page_label: Label = $VBoxContainer/PaginationBar/PageLabel
@onready var pagination_bar: HBoxContainer = $VBoxContainer/PaginationBar
@onready var pagination_bar_bottom: HBoxContainer = $VBoxContainer/PaginationBarBottom
@onready var page_label_bottom: Label = $VBoxContainer/PaginationBarBottom/PageLabel
@onready var prev_button_bottom: Button = $VBoxContainer/PaginationBarBottom/PrevButton
@onready var next_button_bottom: Button = $VBoxContainer/PaginationBarBottom/NextButton
@onready var l2_glyph: TextureRect = $VBoxContainer/PaginationBar/L2Glyph
@onready var r2_glyph: TextureRect = $VBoxContainer/PaginationBar/R2Glyph
@onready var l2_glyph_bottom: TextureRect = $VBoxContainer/PaginationBarBottom/L2Glyph
@onready var r2_glyph_bottom: TextureRect = $VBoxContainer/PaginationBarBottom/R2Glyph
@onready var no_results_label: Label = $VBoxContainer/NoResultsLabel
@onready var loading_overlay: Control = $LoadingOverlay

# --- Internal Variables ---
var _active_content_container: Container 
var _product_box_min_width: float = 210.0 
var _product_box_min_height: float = 350.0
var installed_ids: Dictionary = {}
var origin_position := Vector2.ZERO
var origin_size := Vector2.ZERO
var current_page = 1
var total_pages = 1
var items_per_page = 10
var total_hits = 0 
var current_query = ""
var current_category = ""
var current_url = ""

# --- Cooldown Variables ---
const NAV_COOLDOWN_MS = 250
var last_nav_time = { "ui_up": 0, "ui_down": 0, "ui_left": 0, "ui_right": 0 }

func _ready():
	origin_position = Vector2(0, 0)
	origin_size = get_viewport_rect().size
	
	if product_box_scene:
		var temp_box = product_box_scene.instantiate()
		_product_box_min_width = temp_box.custom_minimum_size.x
		_product_box_min_height = temp_box.custom_minimum_size.y
		temp_box.queue_free()
		if _product_box_min_width <= 0: _product_box_min_width = 210.0
		if _product_box_min_height <= 0: _product_box_min_height = 350.0
	else:
		printerr("ProductList: product_box_scene is not assigned!")
		_product_box_min_width = 210.0
		_product_box_min_height = 350.0
			
	if title_label:
		if not title.is_empty():
			title_label.text = title
			title_label.visible = true
		else:
			title_label.visible = false
	else:
		printerr("TitleLabel not found in ProductList!")
		
	if display_mode == DisplayMode.MULTI_LINE_WRAP:
		multi_line_scroll.visible = true
		single_line_scroll.visible = false
		_active_content_container = multi_line_content
		_update_pagination_visibility()
		print("ProductList: Multi-line mode activated.")
	else: # SINGLE_LINE_SCROLL
		multi_line_scroll.visible = false
		single_line_scroll.visible = true
		_active_content_container = single_line_content
		print("ProductList: Single-line mode activated.")

	if product_box_scene:
		var temp_box = product_box_scene.instantiate()
		_product_box_min_width = temp_box.custom_minimum_size.x
		temp_box.queue_free()
		if _product_box_min_width <= 0: _product_box_min_width = 210.0
	else:
		printerr("ProductList: product_box_scene ist nicht zugewiesen!")
		
	call_deferred("_update_minimum_height")
	
	# Connect Top Pagination
	if prev_button: prev_button.pressed.connect(_on_prev_button_pressed)
	if next_button: next_button.pressed.connect(_on_next_button_pressed)
	
	# Connect Bottom Pagination
	if prev_button_bottom: prev_button_bottom.pressed.connect(_on_prev_button_pressed)
	if next_button_bottom: next_button_bottom.pressed.connect(_on_next_button_pressed)
	
	if l2_glyph: l2_glyph.pressed.connect(_apply_button_feedback.bind(prev_button))
	if r2_glyph: r2_glyph.pressed.connect(_apply_button_feedback.bind(next_button))
	if l2_glyph_bottom: l2_glyph_bottom.pressed.connect(_apply_button_feedback.bind(prev_button_bottom))
	if r2_glyph_bottom: r2_glyph_bottom.pressed.connect(_apply_button_feedback.bind(next_button_bottom))
		
	print("--- ProductList _ready END for '", title, "' ---")

func _apply_button_feedback(is_pressed: bool, btn: Button):
	if not is_instance_valid(btn) or btn.disabled: return
	var target_mod = Color(1.5, 1.5, 1.5, 1.0) if is_pressed else Color(1, 1, 1, 1)
	var target_scale = Vector2(1.05, 1.05) if is_pressed else Vector2(1.0, 1.0)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(btn, "modulate", target_mod, 0.1)
	tween.tween_property(btn, "scale", target_scale, 0.1)
	btn.pivot_offset = btn.size / 2.0

func set_url(url: String):
	current_url = url

func set_pagination_data(hitsPerPage: int, page: int, totalPages: int):
	items_per_page = hitsPerPage
	current_page = page
	total_pages = totalPages
	
	var label_text = "Page %s of %s" % [current_page, total_pages]
	page_label.text = label_text
	if page_label_bottom: page_label_bottom.text = label_text
	
	# Disable/Enable Buttons logic
	var can_go_next = current_page < total_pages
	var can_go_prev = current_page > 1
	
	_update_nav_button(next_button, can_go_next)
	_update_nav_button(next_button_bottom, can_go_next)
	_update_nav_button(prev_button, can_go_prev)
	_update_nav_button(prev_button_bottom, can_go_prev)

	# Focus handling if button was disabled while focused (simple fallback)
	if not can_go_next and (next_button.has_focus() or next_button_bottom.has_focus()):
		if can_go_prev: 
			if next_button.has_focus(): prev_button.grab_focus()
			else: prev_button_bottom.grab_focus()
	
	if not can_go_prev and (prev_button.has_focus() or prev_button_bottom.has_focus()):
		if can_go_next: 
			if prev_button.has_focus(): next_button.grab_focus()
			else: next_button_bottom.grab_focus()

func _update_nav_button(btn: Button, enabled: bool):
	if not is_instance_valid(btn): return
	btn.disabled = not enabled
	btn.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func set_products(product_data: Array):
	hide_loading()
	
	# Reset scroll position
	if is_instance_valid(multi_line_scroll): multi_line_scroll.scroll_vertical = 0
	if is_instance_valid(single_line_scroll): single_line_scroll.scroll_horizontal = 0
	
	var has_products = product_data.size() > 0
	
	if is_instance_valid(no_results_label):
		no_results_label.visible = not has_products
		
	# Determine target scroll based on mode
	var target_scroll = multi_line_scroll if display_mode == DisplayMode.MULTI_LINE_WRAP else single_line_scroll
	if is_instance_valid(target_scroll): target_scroll.visible = has_products
	
	if not has_products:
		# Hide pagination if no results
		if pagination_bar: pagination_bar.visible = false
		if pagination_bar_bottom: pagination_bar_bottom.visible = false
		print("--- ProductList set_products (Empty) END ---")
		call_deferred("emit_signal", "products_loaded")
		return

	if not is_instance_valid(_active_content_container):
		printerr("ProductList: Active container is invalid!")
		return

	for child in _active_content_container.get_children():
		child.queue_free()

	if not product_box_scene:
		printerr("ProductList: product_box_scene is not assigned!")
		return

	for product in product_data:
		var product_box_instance = product_box_scene.instantiate()
		product_box_instance.focus_mode = Control.FOCUS_ALL

		var product_app_id = product.get("app_id")
		if product_box_instance.has_method("set_app_id"):
			product_box_instance.set_app_id(product_app_id)
		
		var node_product_name = product_box_instance.get_node("Panel/ProductName")
		node_product_name.text = product.get("name", "N/A")

		var image_url = product.get("icon")
		if image_url and not image_url.is_empty():
			var product_logo_rect = product_box_instance.get_node_or_null("Panel/ProductLogo") as TextureRect
			if product_logo_rect:
				emit_signal("image_load_requested", image_url, product_logo_rect)
		product_box_instance.move_to_details_view.connect(_on_emit_move_to_details_view)
		_active_content_container.add_child(product_box_instance)

	var final_child_count = 0
	if is_instance_valid(_active_content_container):
		final_child_count = _active_content_container.get_child_count()
	print("--- ProductList set_products END ---")
	print("Final child count in active container: ", final_child_count)
	
	# Restore pagination visibility if products exist and we are in multi-line mode
	if display_mode == DisplayMode.MULTI_LINE_WRAP:
		_update_pagination_visibility()
	
	var main_node = get_node_or_null("/root/App")
	if main_node and main_node.has_method("get_installed_ids"):
		update_installed_status(main_node.get_installed_ids())
	
	call_deferred("emit_signal", "products_loaded")

func show_loading():
	if is_instance_valid(loading_overlay):
		loading_overlay.show_overlay()
		
func hide_loading():
	if is_instance_valid(loading_overlay):
		loading_overlay.hide_overlay()

func get_base_url(full_url: String) -> String:
	var parts = full_url.split("?", false, 1)
	return parts[0]

func _get_url_params(full_url: String) -> Dictionary:
	var params = {}
	var parts = full_url.split("?")
	if parts.size() > 1:
		var param_pairs = parts[1].split("&")
		for p in param_pairs:
			var kv = p.split("=")
			if kv.size() == 2:
				params[kv[0]] = kv[1]
	return params

func _build_url(base: String, params: Dictionary) -> String:
	var query_string = ""
	var first = true
	for key in params:
		if not first: query_string += "&"
		query_string += key + "=" + str(params[key])
		first = false
	return base + "?" + query_string

func _show_pagination():
	# Do not show pagination for single-line scrolling lists (e.g. on Home View)
	if display_mode == DisplayMode.SINGLE_LINE_SCROLL:
		return false
	return true

func _update_pagination_visibility():
	var show = _show_pagination()
	if pagination_bar: pagination_bar.visible = show
	if pagination_bar_bottom: pagination_bar_bottom.visible = show

func _on_prev_button_pressed():
	show_loading()
	var base_url = get_base_url(current_url)
	var params = _get_url_params(current_url)
	
	params["page"] = str(current_page - 1)
	params["per_page"] = str(items_per_page)
	# Ensure locale is present if it was hardcoded before, though ideally it should be in current_url
	if not params.has("locale"): params["locale"] = "en" 
	
	var target_url = _build_url(base_url, params)
	emit_signal("load_new_page", target_url, self)
	
func _on_next_button_pressed():
	show_loading()
	var base_url = get_base_url(current_url)
	var params = _get_url_params(current_url)
	
	params["page"] = str(current_page + 1)
	params["per_page"] = str(items_per_page)
	if not params.has("locale"): params["locale"] = "en"
	
	var target_url = _build_url(base_url, params)
	emit_signal("load_new_page", target_url, self)
	
func _on_emit_move_to_details_view(app_id: String, installed: bool):
	emit_signal("move_to_details_view", app_id, installed)

func update_installed_status(new_ids: Dictionary):
	installed_ids = new_ids
	if not is_instance_valid(_active_content_container): return
	for child in _active_content_container.get_children():
		if child.has_method("set_installed_status"):
			var app_id = child.get("app_id") 
			if app_id != null and app_id is String and not app_id.is_empty():
				var is_installed = installed_ids.has(app_id)
				child.set_installed_status(is_installed)

func _update_minimum_height():
	if not use_auto_height: return
	
	if not is_instance_valid(self) or not is_instance_valid(inner_vbox) or \
	   not is_instance_valid(title_label) or not is_instance_valid(_active_content_container):
		printerr("Nodes für Mindesthöhenberechnung ungültig in '%s'." % title)
		return

	await get_tree().process_frame # Wait for next frame for size adjustments

	var calculated_min_height: float = 0.0
	var title_height: float = 0.0

	if title_label.visible:
		title_height = title_label.get_combined_minimum_size().y

	var vbox_separation = inner_vbox.get_theme_constant("separation", "VBoxContainer")

	var content_min_height: float = 0.0
	if display_mode == DisplayMode.MULTI_LINE_WRAP:
		var num_rows = max(1, min_rows)
		var content_v_separation = _active_content_container.get_theme_constant("v_separation", "HFlowContainer")
		# Height = (Amount Rows * Box Height) + (Amount Seperations * Seperation Height)
		content_min_height = (_product_box_min_height * num_rows) + (content_v_separation * max(0, num_rows - 1))
	else: # SINGLE_LINE_SCROLL
		content_min_height = _product_box_min_height

	# Complete min height = Title + Seperation + Content
	calculated_min_height = title_height + content_min_height
	if title_label.visible:
		calculated_min_height += vbox_separation

	# Add padding
	calculated_min_height += 10.0
	
	# Add height for bottom pagination if visible
	if pagination_bar_bottom and pagination_bar_bottom.visible:
		calculated_min_height += pagination_bar_bottom.size.y + vbox_separation

	print("Update Min Height for '%s': %.1f (Title: %.1f, Content: %.1f)" % [title, calculated_min_height, title_height, content_min_height])
	self.custom_minimum_size.y = calculated_min_height


func focus_first_product():
	# Reset scroll explicitly before focusing to prevent jumping to bottom
	if multi_line_scroll.visible: multi_line_scroll.scroll_vertical = 0
	elif single_line_scroll.visible: single_line_scroll.scroll_horizontal = 0

	var first_focusable = _get_first_focusable_product()
	if is_instance_valid(first_focusable):
		first_focusable.grab_focus()
		if multi_line_scroll.visible: multi_line_scroll.ensure_control_visible(first_focusable)
		elif single_line_scroll.visible: single_line_scroll.ensure_control_visible(first_focusable)


func _input(event: InputEvent):
	if not is_visible_in_tree():
		return

	var focused_control = get_viewport().gui_get_focus_owner()
	var has_focus_ownership = has_focus() or (is_instance_valid(focused_control) and is_ancestor_of(focused_control))
	
	if not has_focus_ownership:
		return
		
	# Pagination Shortcuts - only for multi-line wrap lists
	if display_mode == DisplayMode.MULTI_LINE_WRAP:
		if event.is_action_pressed("ui_page_up"):
			if current_page > 1:
				_on_prev_button_pressed()
				get_viewport().set_input_as_handled()
				return
		elif event.is_action_pressed("ui_page_down"):
			if current_page < total_pages:
				_on_next_button_pressed()
				get_viewport().set_input_as_handled()
				return

	var action_string = ""
	if event.is_action_pressed("ui_up"): action_string = "ui_up"
	elif event.is_action_pressed("ui_down"): action_string = "ui_down"
	elif event.is_action_pressed("ui_left"): action_string = "ui_left"
	elif event.is_action_pressed("ui_right"): action_string = "ui_right"

	if action_string != "":
		var current_time = Time.get_ticks_msec()
		if current_time - last_nav_time.get(action_string, 0) > NAV_COOLDOWN_MS:
			if _handle_navigation(action_string):
				last_nav_time[action_string] = current_time
				get_viewport().set_input_as_handled()
		else:
			get_viewport().set_input_as_handled()


# --- Core Navigation Logic  ---
func _handle_navigation(action_string: String) -> bool:
	var focused_control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused_control) or not _active_content_container.is_ancestor_of(focused_control):
		return false

	var navigation_occurred = false
	var target_node_to_focus: Control = null

	# Focus is in current product container
	var current_index = focused_control.get_index()
	var child_count = _active_content_container.get_child_count()

	if action_string == "ui_up":
		var is_in_first_row = false
		if child_count > 0 and current_index >= 0:
			if _active_content_container is HFlowContainer:
				var focused_pos_y = focused_control.global_position.y
				var first_valid_child = _get_first_focusable_product()
				if first_valid_child:
					var first_child_pos_y = first_valid_child.global_position.y
					if abs(focused_pos_y - first_child_pos_y) < 10.0: is_in_first_row = true
			elif _active_content_container is HBoxContainer:
				is_in_first_row = true

		if is_in_first_row:
			# Check if there is anything focusable above this list before exiting
			var neighbor = focused_control.find_valid_focus_neighbor(SIDE_TOP)
			if is_instance_valid(neighbor):
				# Let Godot handle the focus switch to the neighbor above
				return false
			else:
				# Nothing above, exit to top bar
				emit_signal("focus_exited_up")
				navigation_occurred = true
		else:
			var num_columns = _get_current_column_count()
			var target_index = current_index - num_columns
			if target_index >= 0:
				target_node_to_focus = _get_child_if_focusable(target_index)
				if target_node_to_focus: navigation_occurred = true

	elif action_string == "ui_down":
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

	if navigation_occurred and is_instance_valid(target_node_to_focus):
		_focus_product_at_index(target_node_to_focus)

	return navigation_occurred

# --- Helper Functions ---

func _get_current_column_count() -> int:
	if not is_instance_valid(_active_content_container): return 1
	if _active_content_container is GridContainer:
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
		# Count only valid children
		var valid_count = 0
		for child in _active_content_container.get_children():
			if not child.is_queued_for_deletion():
				valid_count += 1
		return valid_count
	else: return 1

func _get_child_if_focusable(index: int) -> Control:
	if index >= 0 and index < _active_content_container.get_child_count():
		var node = _active_content_container.get_child(index) as Control
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.focus_mode != Control.FOCUS_NONE:
			return node
	return null

func _focus_product_at_index(target_node: Control):
	if is_instance_valid(target_node):
		if target_node.focus_mode != Control.FOCUS_NONE:
			target_node.grab_focus()
			
			# Wait one frame for layout to stabilize and positions to be accurate
			await get_tree().process_frame
			if not is_instance_valid(target_node) or not target_node.has_focus():
				return

			var scroll_container: ScrollContainer = null
			if display_mode == DisplayMode.MULTI_LINE_WRAP:
				scroll_container = multi_line_scroll
			elif display_mode == DisplayMode.SINGLE_LINE_SCROLL:
				scroll_container = single_line_scroll
				
			if is_instance_valid(scroll_container):
				var margin = 30.0 # Slightly larger margin for better visibility
				
				if display_mode == DisplayMode.MULTI_LINE_WRAP:
					var node_y = target_node.position.y
					var node_h = target_node.size.y
					var viewport_h = scroll_container.size.y
					var current_scroll = scroll_container.scroll_vertical
					
					if node_y < current_scroll + margin:
						scroll_container.scroll_vertical = max(0, node_y - margin)
					elif node_y + node_h > current_scroll + viewport_h - margin:
						scroll_container.scroll_vertical = node_y + node_h - viewport_h + margin
				
				elif display_mode == DisplayMode.SINGLE_LINE_SCROLL:
					var node_x = target_node.position.x
					var node_w = target_node.size.x
					var viewport_w = scroll_container.size.x
					var current_scroll = scroll_container.scroll_horizontal
					
					if node_x < current_scroll + margin:
						scroll_container.scroll_horizontal = max(0, node_x - margin)
					elif node_x + node_w > current_scroll + viewport_w - margin:
						scroll_container.scroll_horizontal = node_x + node_w - viewport_w + margin
				
func _get_first_focusable_product() -> Control:
	if not is_instance_valid(_active_content_container): return null
	for child in _active_content_container.get_children():
		if child is Control and not child.is_queued_for_deletion() and child.focus_mode != Control.FOCUS_NONE:
			return child
	return null
