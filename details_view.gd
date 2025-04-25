extends Control

signal move_back_to_main_view
signal image_load_requested(url: String, texture_rect: TextureRect)

@export var product_screenshot_scene: PackedScene = preload("res://product_screenshot.tscn")

@onready var app_icon: TextureRect = $MarginContainer/Panel/DetailsContents/DetailsNavbar/AppIcon
@onready var app_title: RichTextLabel = $MarginContainer/Panel/DetailsContents/DetailsNavbar/AppTitle
@onready var app_desc: RichTextLabel = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/ScrollContainer/AppDescription
@onready var screenshot_container: HBoxContainer = $MarginContainer/Panel/DetailsContents/ScreenshotClipContainer/ContainerScreenshots
@onready var app_current_version: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/ContainerAppDetails/ContainerVersion/CurrentVersion
@onready var app_release_date: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/ContainerAppDetails/ContainerReleaseDate/ReleaseDate

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
	for screenshot in screenshot_container.get_children():
		screenshot_container.remove_child(screenshot)
	
	
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
	# navbar
	app_title.text = product.get("name")
	var image_url = product.get("icon")
	if image_url and not image_url.is_empty():
		emit_signal("image_load_requested", image_url, app_icon)

	# description
	app_desc.text = product.get("description")

	# screenshots
	var screenshots = product.get("screenshots")
	for screenshot_collection in screenshots:
		var screenshot_sizes = screenshot_collection.get("sizes")
		var screenshot = screenshot_sizes[0] 
		var screenshot_url = screenshot.get("src")
		var screenshot_instance = product_screenshot_scene.instantiate()
		screenshot_instance.focus_mode = Control.FOCUS_ALL
		var screenshot_rect = screenshot_instance.get_node_or_null("MarginContainer/Panel/Screenshot") as TextureRect
		if screenshot_rect:
			print("Load image ", screenshot_url)
			emit_signal("image_load_requested", screenshot_url, screenshot_rect)
		else:
			printerr("Screenshot Element not found")
		screenshot_container.add_child(screenshot_instance)
		
	# app details
	
	# releases -> current version and release date
	var releases = product.get("releases")
	var latest_release = releases[0]
	var timestamp_released = int(latest_release.get("timestamp"))
	app_current_version.text = latest_release.get("version")
	var datetime_dict: Dictionary = Time.get_datetime_dict_from_unix_time(timestamp_released)
	var day = str(datetime_dict["day"]).pad_zeros(2)
	var month = str(datetime_dict["month"]).pad_zeros(2)
	var year = str(datetime_dict["year"])
	app_release_date.text = "%s-%s-%s" % [year, month, day]
	
	
		
	
