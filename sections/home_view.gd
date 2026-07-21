# home_view.gd
extends Control

# Exported variable to receive the ProductBox scene from main.gd
@export var product_box_scene: PackedScene

# Node references - ADJUST THESE PATHS to your actual node structure within HomeView.tscn
@onready var hero_carousel = $ContentScrollContainer/VBoxContainer/HeroCarousel
@onready var popular_product_list: ProductList = $ContentScrollContainer/VBoxContainer/PopularProductList # Example path, ADJUST
@onready var trending_product_list: ProductList = $ContentScrollContainer/VBoxContainer/TrendingProductList # Example path, ADJUST
@onready var content_scroll_container: ScrollContainer = $ContentScrollContainer # Example path, ADJUST

# --- Signals to be emitted to main.gd ---
signal move_to_details_view_requested(app_id: String, installed: bool)
signal image_load_requested(url: String, texture_rect: TextureRect)
signal focus_exited_up_from_lists() # Emitted when focus should move to top bar
signal load_new_page_requested(url: String, target_list_node: ProductList)


func _ready():
	# Ensure product_box_scene is set for both lists if provided from main
	if not product_box_scene:
		printerr("HomeView ERROR: product_box_scene was not set by Main!")
		# Optionally, load a default or handle the error
	if is_instance_valid(hero_carousel):
		hero_carousel.move_to_details_view.connect(_on_internal_move_to_details_view)
		hero_carousel.image_load_requested.connect(_on_internal_image_load_requested)
		hero_carousel.focus_entered_carousel.connect(_on_hero_carousel_focus_entered)
	
	if is_instance_valid(popular_product_list):
		if product_box_scene and not popular_product_list.product_box_scene:
			popular_product_list.product_box_scene = product_box_scene
		# Connect signals from popular_product_list
		popular_product_list.move_to_details_view.connect(_on_internal_move_to_details_view)
		popular_product_list.image_load_requested.connect(_on_internal_image_load_requested)
		popular_product_list.focus_exited_up.connect(_on_internal_focus_exited_up)
		popular_product_list.load_new_page.connect(
			func(url: String, _list_node_path: NodePath): # Use a lambda to pass the node itself
				_on_internal_load_new_page(url, popular_product_list)
		)
	else:
		printerr("HomeView ERROR: PopularProductList node not found or invalid at expected path!")
			
	if is_instance_valid(trending_product_list):
		if product_box_scene and not trending_product_list.product_box_scene:
			trending_product_list.product_box_scene = product_box_scene
		# Connect signals from trending_product_list
		trending_product_list.move_to_details_view.connect(_on_internal_move_to_details_view)
		trending_product_list.image_load_requested.connect(_on_internal_image_load_requested)
		trending_product_list.focus_exited_up.connect(_on_internal_focus_exited_up)
		trending_product_list.load_new_page.connect(
			func(url: String, _list_node_path: NodePath): # Use a lambda to pass the node itself
				_on_internal_load_new_page(url, trending_product_list)
		)
	else:
		printerr("HomeView ERROR: TrendingProductList node not found or invalid at expected path!")

func load_popular_products_in_view():
	if is_instance_valid(popular_product_list):
		var main_node = get_node_or_null("/root/App") 
		if main_node and main_node.has_method("_load_product_list"):
			main_node._load_product_list("https://flathub.org/api/v2/collection/popular?page=1&per_page=10&locale=en", popular_product_list)

func load_trending_products_in_view():
	if is_instance_valid(trending_product_list):
		var main_node = get_node_or_null("/root/App") 
		if main_node and main_node.has_method("_load_product_list"):
			main_node._load_product_list("https://flathub.org/api/v2/collection/trending?page=1&per_page=10&locale=en", trending_product_list)

func update_internal_list_install_status(installed_ids: Dictionary):
	print("INFO: Update installed state in home view lists...")
	if is_instance_valid(hero_carousel):
		hero_carousel.update_installed_status(installed_ids)
	if is_instance_valid(popular_product_list):
		popular_product_list.update_installed_status(installed_ids)
	if is_instance_valid(trending_product_list):
		trending_product_list.update_installed_status(installed_ids)
		
# --- Internal signal handlers that re-emit signals for main.gd ---
func _on_internal_move_to_details_view(app_id: String, installed: bool):
	emit_signal("move_to_details_view_requested", app_id, installed)

func _on_internal_image_load_requested(url: String, texture_rect: TextureRect):
	emit_signal("image_load_requested", url, texture_rect)

func _on_internal_focus_exited_up():
	if is_instance_valid(content_scroll_container):
		content_scroll_container.scroll_vertical = 0
	emit_signal("focus_exited_up_from_lists")

func _on_hero_carousel_focus_entered():
	# Ensure the scroll container goes all the way up so the heading is not cut off
	if is_instance_valid(content_scroll_container):
		content_scroll_container.scroll_vertical = 0

func _on_internal_load_new_page(url: String, list_node: ProductList):
	# This function now receives the actual ProductList node
	if is_instance_valid(list_node):
		emit_signal("load_new_page_requested", url, list_node)
	else:
		# This case should ideally not happen if connected correctly with lambda
		printerr("HomeView ERROR: Invalid list_node passed to _on_internal_load_new_page for URL: ", url)

# Method to allow main.gd to set focus to the first product in the popular list
func focus_first_product_in_popular_list():
	if is_instance_valid(popular_product_list):
		popular_product_list.focus_first_product()
	else:
		printerr("HomeView: PopularProductList not available to focus.")

# Placeholder for any specific logic this view might need when it becomes active
func on_view_entered():
	print("HomeView entered")

# Placeholder for any specific logic this view might need when it's about to be hidden
func on_view_exiting():
	print("HomeView exiting")

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("go_back"):
		var focus_owner = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus_owner):
			if popular_product_list.is_ancestor_of(focus_owner) or trending_product_list.is_ancestor_of(focus_owner):
				emit_signal("focus_exited_up_from_lists")
				get_viewport().set_input_as_handled()
	
func scroll_to_top():
	if is_instance_valid(content_scroll_container):
		content_scroll_container.scroll_vertical = 0
		print("HomeView: Scrolled to top.")	
