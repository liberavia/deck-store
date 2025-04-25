extends Control

signal move_back_to_main_view
signal image_load_requested(url: String, texture_rect: TextureRect)

@export var product_screenshot_scene: PackedScene = preload("res://product_screenshot.tscn")

@onready var app_icon: TextureRect = $MarginContainer/Panel/DetailsContents/DetailsNavbar/AppIcon
@onready var app_title: RichTextLabel = $MarginContainer/Panel/DetailsContents/DetailsNavbar/AppTitle
@onready var app_desc: RichTextLabel = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDescription/ScrollContainer/AppDescription
@onready var screenshot_container: HBoxContainer = $MarginContainer/Panel/DetailsContents/ScreenshotClipContainer/ScrollContainer/ContainerScreenshots
@onready var app_current_version: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerVersion/CurrentVersion
@onready var app_release_date: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerReleaseDate/ReleaseDate
@onready var button_install: Button = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/ButtonInstall
@onready var button_remove: Button = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/ButtonRemove
@onready var screenshot_scroll_container: ScrollContainer = $MarginContainer/Panel/DetailsContents/ScreenshotClipContainer/ScrollContainer
@onready var description_scroll_container: ScrollContainer = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDescription/ScrollContainer

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
	
func set_initial_focus():
	if button_install.visible:
		button_install.grab_focus()
	elif button_remove.visible:
		button_remove.grab_focus()
	else:
		screenshot_scroll_container.grab_focus()
	
func load_details():
	if installed:
		button_install.visible = false
		button_remove.visible = true
	else:
		button_install.visible = true
		button_remove.visible = false
		
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
	app_desc.text = limited_html_to_bbcode(product.get("description"))

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
	
	set_initial_focus()
	
	
# Function to convert a limited subset of HTML to Godot-compatible BBCode
func limited_html_to_bbcode(html_string: String) -> String:
	# print("--- Incoming HTML ---")
	# print(html_string)
	# print("-------------------------")

	# Make a mutable copy
	var bbcode: String = html_string

	# --- Basic Tag Replacements (Order can matter!) ---
	# Paragraphs (replace with double newlines for separation)
	var regex_p_open = RegEx.new(); regex_p_open.compile("\\s*<p>\\s*")
	bbcode = regex_p_open.sub(bbcode, "\n", true) # Start with one newline
	var regex_p_close = RegEx.new(); regex_p_close.compile("\\s*</p>\\s*")
	bbcode = regex_p_close.sub(bbcode, "\n", true) # Add the second newline

	# Bold
	bbcode = bbcode.replace("<b>", "[b]").replace("</b>", "[/b]")
	bbcode = bbcode.replace("<strong>", "[b]").replace("</strong>", "[/b]")
	# Italics
	bbcode = bbcode.replace("<i>", "[i]").replace("</i>", "[/i]")
	bbcode = bbcode.replace("<em>", "[i]").replace("</em>", "[/i]")

	# --- Lists (Godot 4 Syntax: Items separated by newlines) ---
	# Use Regex to replace list tags AND surrounding whitespace (\s*)
	# Adding extra newlines before opening and after closing tags for spacing
	var regex_ul_open = RegEx.new(); regex_ul_open.compile("\\s*<ul>\\s*")
	bbcode = regex_ul_open.sub(bbcode, "\n\n[ul]\n", true) # Two \n before
	var regex_ol_open = RegEx.new(); regex_ol_open.compile("\\s*<ol>\\s*")
	bbcode = regex_ol_open.sub(bbcode, "\n\n[ol]\n", true) # Two \n before

	var regex_ul_close = RegEx.new(); regex_ul_close.compile("\\s*</ul>\\s*")
	bbcode = regex_ul_close.sub(bbcode, "\n[/ul]\n\n", true) # Two \n after
	var regex_ol_close = RegEx.new(); regex_ol_close.compile("\\s*</ol>\\s*")
	bbcode = regex_ol_close.sub(bbcode, "\n[/ol]\n\n", true) # Two \n after

	# Replace <li> opening tag and surrounding whitespace WITH a single space
	var regex_li_open = RegEx.new(); regex_li_open.compile("\\s*<li>\\s*")
	bbcode = regex_li_open.sub(bbcode, " ", true) # CHANGED: Replace with space
	# Replace </li> closing tag and surrounding whitespace with just a newline
	var regex_li_close = RegEx.new(); regex_li_close.compile("\\s*</li>\\s*")
	bbcode = regex_li_close.sub(bbcode, "\n", true)


	# --- Links ---
	# Convert <a href="URL">TEXT</a> to [url=URL]TEXT[/url]
	var regex_a = RegEx.new()
	regex_a.compile("<a\\s+[^>]*?href\\s*=\\s*[\"']?([^\"'\\s>]+)[\"']?[^>]*>(.*?)</a>")
	bbcode = regex_a.sub(bbcode, "[url=$1]$2[/url]", true)


	# --- Cleanup ---
	# Remove any remaining HTML tags that weren't handled
	var regex_tags = RegEx.new()
	regex_tags.compile("<[^>]*>")
	bbcode = regex_tags.sub(bbcode, "", true)

	# Decode HTML/XML entities (e.g., &amp; -> &) using the built-in method
	bbcode = bbcode.xml_unescape()

	# Reduce multiple consecutive newlines (more than 2) down to 2
	var regex_newlines = RegEx.new()
	regex_newlines.compile("\n{3,}")
	bbcode = regex_newlines.sub(bbcode, "\n\n", true)

	# Trim leading/trailing whitespace and newlines from the final result
	bbcode = bbcode.strip_edges()

	# --- Debug Output (Optional) ---
	# print("--- Generated BBCode ---")
	# print(bbcode)
	# print("-------------------------")

	return bbcode
