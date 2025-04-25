extends Control

signal move_back_to_main_view
signal image_load_requested(url: String, texture_rect: TextureRect)

@export var product_screenshot_scene: PackedScene = preload("res://product_screenshot.tscn")

@onready var app_icon: TextureRect = $Panel/VBoxContainer/DetailsNavbar/AppIcon
@onready var app_title: RichTextLabel = $Panel/VBoxContainer/DetailsNavbar/AppTitle
@onready var app_desc: RichTextLabel = $Panel/VBoxContainer/ContainerDetailsMain/ScrollContainer/AppDescription
@onready var app_current_version: Label = $Panel/VBoxContainer/ContainerDetailsMain/VBoxContainer/HBoxContainer/CurrentVersion
@onready var screenshot_container: HBoxContainer = $Panel/VBoxContainer/ContainerScreenshots

var app_id: String = ""
var installed: bool = false

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"): 
		emit_signal("move_back_to_main_view")
	
func set_app_id(assigned_id: String):
	app_id = assigned_id

func set_installed(is_installed: bool):
	installed = is_installed
	
func clear_data():
	app_id = ""
	installed = false
	app_title.text = ""
	app_desc.text = ""
	app_icon.texture = null
	
	
func load_details():
	if app_id == "":
		printerr("ERROR: Cannot load details if no app_id is available")
	var url = "https://flathub.org/api/v2/appstream/%s?locale=en" % app_id
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(
		_on_product_details_request_completed.bind(http_request, url)
	)
	var error = http_request.request(url)
	if error != OK:
		printerr("Error starting request for '%s' : %s" % [url, error])
		if is_instance_valid(http_request): http_request.queue_free()
	
func _on_product_details_request_completed(result, response_code, headers, body, http_request_list: HTTPRequest, url: String):
	if response_code == 200:
		var response_string = body.get_string_from_utf8()
		var api_json = JSON.parse_string(response_string)
		_display_details(api_json)
		
	if is_instance_valid(http_request_list):
		http_request_list.queue_free()	

func _display_details(product):
	app_title.text = product.get("name")
	app_desc.text = product.get("description")
	var image_url = product.get("icon")
	if image_url and not image_url.is_empty():
		emit_signal("image_load_requested", image_url, app_icon)
		
	var screenshots = product.get("screenshots")
	var screenshot_sizes = screenshots[0]['sizes']
	for screenshot in screenshot_sizes:
		var screenshot_url = screenshot.get("src")
		var screenshot_instance = product_screenshot_scene.instantiate()
		screenshot_instance.focus_mode = Control.FOCUS_ALL
		var screenshot_rect = screenshot_instance.get_node_or_null("Panel/Screenshot") as TextureRect
		if screenshot_rect:
			print("Load image ", screenshot_url)
			emit_signal("image_load_requested", screenshot_url, screenshot_rect)
		else:
			printerr("Screenshot Element not found")
		screenshot_container.add_child(screenshot_instance)
	
