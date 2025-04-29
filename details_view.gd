# details_view.gd
extends Control

signal move_back_to_main_view
signal image_load_requested(url: String, texture_rect: TextureRect)

@export var product_screenshot_scene: PackedScene = preload("res://product_screenshot.tscn")

# --- @onready vars for UI elements ---
@onready var app_icon: TextureRect = $MarginContainer/Panel/DetailsContents/DetailsNavbar/AppIcon
@onready var app_title: RichTextLabel = $MarginContainer/Panel/DetailsContents/DetailsNavbar/AppTitle
@onready var app_desc: RichTextLabel = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDescription/DetailsDescriptionScroller/AppDescription
@onready var screenshot_container: HBoxContainer = $MarginContainer/Panel/DetailsContents/ScreenshotClipContainer/ScrollContainer/ContainerScreenshots
@onready var app_current_version: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerVersion/CurrentVersion
@onready var app_release_date: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerReleaseDate/ReleaseDate
@onready var button_install: Button = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/ButtonInstall
@onready var button_remove: Button = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/ButtonRemove
@onready var screenshot_scroll_container: ScrollContainer = $MarginContainer/Panel/DetailsContents/ScreenshotClipContainer/ScrollContainer
@onready var description_scroll_container: ScrollContainer = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDescription/DetailsDescriptionScroller # Corrected path based on scene

# --- Internal State ---
var current_app_id: String = ""
var is_currently_installed: bool = false

# --- Constants ---
# Using constants directly here as requested. Consider Autoload for sharing with main.gd
const CACHE_DURATION_MSEC: int = 3600 * 1000 # 1 hour
const API_CACHE_DIR = "user://cache/api/"

# =============================================================================
# BUILT-IN GODOT METHODS
# =============================================================================

func _ready():
	# Ensure cache directory exists (good practice to have it here too)
	var dir_access = DirAccess.open("user://")
	if dir_access:
		DirAccess.make_dir_recursive_absolute(API_CACHE_DIR)

func _unhandled_input(event: InputEvent):
	# Only handle back button if this view is visible
	if not self.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		emit_signal("move_back_to_main_view")
		get_viewport().set_input_as_handled() # Handle it here

# =============================================================================
# PUBLIC METHODS (called from main.gd or elsewhere)
# =============================================================================

func set_app_id(assigned_id: String):
	current_app_id = assigned_id
	button_install.set_app_id(assigned_id)
	#button_remove.set_app_id(assigned_id)

func set_installed(is_installed: bool):
	is_currently_installed = is_installed
	_update_install_buttons() # Update buttons based on passed status

func clear_data():
	current_app_id = ""
	is_currently_installed
	app_title.text = "Loading..."
	app_desc.text = ""
	app_icon.texture = null
	app_current_version.text = "N/A"
	app_release_date.text = "N/A"
	for screenshot in screenshot_container.get_children():
		screenshot_container.remove_child(screenshot)
		screenshot.queue_free()

# Main entry point to load data for the current_app_id
func load_details():
	if current_app_id.is_empty():
		printerr("ERROR: Cannot load details, app_id is empty.")
		app_title.text = "Error: No App ID" # Show error in UI
		return

	_update_install_buttons()
	_load_details_data(current_app_id)


# =============================================================================
# INTERNAL DATA LOADING & CACHING
# =============================================================================

# --- Helper function to get cache file path ---
func _get_api_cache_filepath(url: String) -> String:
	var request_hash = url.md5_text()
	return API_CACHE_DIR.path_join(request_hash + ".json")

# --- Load details: Check cache or start request ---
func _load_details_data(app_id_to_load: String):
	var detail_api_url = "https://flathub.org/api/v2/appstream/%s?locale=en" % app_id_to_load

	# --- File Cache Check ---
	var cache_filepath = _get_api_cache_filepath(detail_api_url)
	if FileAccess.file_exists(cache_filepath):
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
					_display_details(api_data) # Use cached data
					# hide_loading_indicator() # Optional
					return # Data loaded from cache, exit
				else:
					DirAccess.remove_absolute(cache_filepath)
			else:
				DirAccess.remove_absolute(cache_filepath)
		else:
			printerr("ERROR: Opening cache file %s failed: %s" % [cache_filepath.get_file(), open_error])
			if is_instance_valid(file): file.close()

	# --- Cache MISS or expired: Start HTTP Request ---
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(
		_on_product_details_request_completed.bind(http_request, detail_api_url) # Bind URL
	)
	var error = http_request.request(detail_api_url)
	if error != OK:
		printerr("ERROR: Starting details request failed for '%s' (%s): %s" % [app_id_to_load, detail_api_url, error])
		# hide_loading_indicator() # Optional
		app_title.text = "Error: Request Failed" # Show error in UI
		if is_instance_valid(http_request): http_request.queue_free()

# --- Handle request completion: Save to cache and display ---
func _on_product_details_request_completed(result, response_code, headers, body, http_request: HTTPRequest, url: String):
	if response_code == 200 and result == HTTPRequest.RESULT_SUCCESS:
		var response_string = body.get_string_from_utf8()
		var api_json = JSON.parse_string(response_string)

		if api_json != null:
			# --- Save to Cache ---
			var data_to_cache = {
				"timestamp": Time.get_ticks_msec(),
				"api_data": api_json
			}
			var json_string_to_cache = JSON.stringify(data_to_cache) # No need for pretty print in cache
			var cache_filepath = _get_api_cache_filepath(url)
			var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
			var open_error = FileAccess.get_open_error()
			if open_error == OK:
				file.store_string(json_string_to_cache)
				file.close()
			else:
				printerr("ERROR: Writing cache file %s failed: %s" % [cache_filepath.get_file(), open_error])
				if is_instance_valid(file): file.close()

			# --- Process and Display ---
			_display_details(api_json)
		else:
			printerr("ERROR: JSON parse error for URL '%s'." % url)
			app_title.text = "Error: Invalid Data" # Show error in UI
	else:
		printerr("ERROR: HTTP Error %d (Result %d) requesting details from '%s'." % [response_code, result, url])
		app_title.text = "Error: Download Failed" # Show error in UI

	# --- Cleanup ---
	# hide_loading_indicator() # Optional
	if is_instance_valid(http_request):
		http_request.queue_free()


# =============================================================================
# UI DISPLAY & HELPERS
# =============================================================================

# --- Display the fetched/cached details ---
func _display_details(product: Dictionary):
	if not product is Dictionary:
		printerr("ERROR: Invalid data passed to _display_details.")
		app_title.text = "Error: Invalid Data"
		return

	# navbar
	app_title.text = product.get("name", "N/A")
	var icon_url = product.get("icon")
	if icon_url and not icon_url.is_empty():
		emit_signal("image_load_requested", icon_url, app_icon)
	else:
		app_icon.texture = null # Clear old icon if none provided

	# description
	var description_html = product.get("description", "")
	app_desc.text = limited_html_to_bbcode(description_html) if not description_html.is_empty() else "No description available."

	# screenshots
	# Clear old ones first
	for child in screenshot_container.get_children():
		screenshot_container.remove_child(child)
		child.queue_free()
	# Add new ones
	var screenshots_data = product.get("screenshots", []) # Default to empty array
	if screenshots_data is Array:
		for screenshot_collection in screenshots_data:
			if screenshot_collection is Dictionary and screenshot_collection.has("sizes"):
				var screenshot_sizes = screenshot_collection.get("sizes", []) # Default to empty array
				if screenshot_sizes is Array and not screenshot_sizes.is_empty():
					var screenshot = screenshot_sizes[0] # Take the first size available
					if screenshot is Dictionary:
						var screenshot_url = screenshot.get("src", "")
						if not screenshot_url.is_empty():
							var screenshot_instance = product_screenshot_scene.instantiate()
							if screenshot_instance:
								# Add before trying to find child? Safer.
								screenshot_container.add_child(screenshot_instance)
								# Find the TextureRect node within the instance
								var screenshot_rect = screenshot_instance.find_child("Screenshot", true, false) as TextureRect # Use find_child with name
								if screenshot_rect:
									emit_signal("image_load_requested", screenshot_url, screenshot_rect)
								else:
									printerr("ERROR: TextureRect 'Screenshot' not found in instantiated product_screenshot.tscn")
							else:
								printerr("ERROR: Failed to instantiate product_screenshot.tscn")

	# app details (version, release date)
	var releases = product.get("releases", []) # Default to empty array
	if releases is Array and not releases.is_empty():
		var latest_release = releases[0]
		if latest_release is Dictionary:
			app_current_version.text = latest_release.get("version", "N/A")
			var timestamp_str = str(latest_release.get("timestamp", ""))
			if not timestamp_str.is_empty() and timestamp_str.is_valid_int():
				var timestamp_int = int(timestamp_str)
				var datetime_dict: Dictionary = Time.get_datetime_dict_from_unix_time(timestamp_int)
				var day = str(datetime_dict["day"]).pad_zeros(2)
				var month = str(datetime_dict["month"]).pad_zeros(2)
				var year = str(datetime_dict["year"])
				app_release_date.text = "%s-%s-%s" % [year, month, day] # ISO format
			else:
				app_release_date.text = "N/A"
		else:
			app_current_version.text = "N/A"
			app_release_date.text = "N/A"
	else:
		app_current_version.text = "N/A"
		app_release_date.text = "N/A"

# --- Set initial focus when view becomes active ---
func set_initial_focus():
	description_scroll_container.remove_theme_stylebox_override("panel")
	if button_install.visible:
		button_install.grab_focus()
	elif button_remove.visible:
		button_remove.grab_focus()
	else:
		print("Nor install or remove button is visible -> Fallback")
		if is_instance_valid(screenshot_scroll_container):
			screenshot_scroll_container.grab_focus()

# --- Update Install/Remove buttons visibility ---
func _update_install_buttons():
	button_install.visible = not is_currently_installed
	button_remove.visible = is_currently_installed
	# TODO: Connect pressed signals dynamically or ensure they are connected elsewhere

# Function to convert a limited subset of HTML to Godot-compatible BBCode
func limited_html_to_bbcode(html_string: String) -> String:
	# print("--- Incoming HTML ---")
	# print(html_string)
	# print("-------------------------")

	# Make a mutable copy
	var work_string: String = html_string

	# --- Step 1: Basic Tags & List Placeholders ---
	# Handle paragraphs first to establish basic newlines
	var regex_p_open = RegEx.new(); regex_p_open.compile("\\s*<p>\\s*")
	work_string = regex_p_open.sub(work_string, "\n", true)
	var regex_p_close = RegEx.new(); regex_p_close.compile("\\s*</p>\\s*")
	work_string = regex_p_close.sub(work_string, "\n", true)

	# Basic inline tags
	work_string = work_string.replace("<b>", "[b]").replace("</b>", "[/b]")
	work_string = work_string.replace("<strong>", "[b]").replace("</strong>", "[/b]")
	work_string = work_string.replace("<i>", "[i]").replace("</i>", "[/i]")
	work_string = work_string.replace("<em>", "[i]").replace("</em>", "[/i]")

	# Links
	var regex_a = RegEx.new()
	regex_a.compile("<a\\s+[^>]*?href\\s*=\\s*[\"']?([^\"'\\s>]+)[\"']?[^>]*>(.*?)</a>")
	work_string = regex_a.sub(work_string, "[url=$1]$2[/url]", true)

	# -- Replace HTML list tags with placeholders --
	# Use regex to consume whitespace around tags
	var regex_ul_open = RegEx.new(); regex_ul_open.compile("\\s*<ul>\\s*")
	work_string = regex_ul_open.sub(work_string, "<LIST_START>", true)
	var regex_ol_open = RegEx.new(); regex_ol_open.compile("\\s*<ol>\\s*")
	work_string = regex_ol_open.sub(work_string, "<LIST_START>", true) # Treat ol like ul for now

	var regex_ul_close = RegEx.new(); regex_ul_close.compile("\\s*</ul>\\s*")
	work_string = regex_ul_close.sub(work_string, "<LIST_END>", true)
	var regex_ol_close = RegEx.new(); regex_ol_close.compile("\\s*</ol>\\s*")
	work_string = regex_ol_close.sub(work_string, "<LIST_END>", true)

	var regex_li_open = RegEx.new(); regex_li_open.compile("\\s*<li>\\s*")
	work_string = regex_li_open.sub(work_string, "<ITEM_START>", true)
	var regex_li_close = RegEx.new(); regex_li_close.compile("\\s*</li>\\s*")
	work_string = regex_li_close.sub(work_string, "<ITEM_END>", true)

	# --- Step 2: Cleanup remaining HTML Tags & Entities ---
	var regex_tags = RegEx.new()
	regex_tags.compile("<(?!LIST_START|LIST_END|ITEM_START|ITEM_END)[^>]*>") # Remove HTML tags EXCEPT our placeholders
	work_string = regex_tags.sub(work_string, "", true)
	work_string = work_string.xml_unescape()


	# --- Step 3: Convert Placeholders to BBCode with desired spacing ---
	# Replace list item placeholders
	# Use regex again to handle potential whitespace introduced around placeholders
	var regex_item_start = RegEx.new(); regex_item_start.compile("\\s*<ITEM_START>\\s*")
	work_string = regex_item_start.sub(work_string, "[indent]\u2022  ", true) # Bullet + two spaces
	var regex_item_end = RegEx.new(); regex_item_end.compile("\\s*<ITEM_END>\\s*")
	work_string = regex_item_end.sub(work_string, "[/indent]\n", true) # Close indent + newline

	# Replace list container placeholders, adding the definitive spacing HERE
	var regex_list_start = RegEx.new(); regex_list_start.compile("\\s*<LIST_START>\\s*")
	work_string = regex_list_start.sub(work_string, "\n\n", true) # Force blank line before list
	var regex_list_end = RegEx.new(); regex_list_end.compile("\\s*<LIST_END>\\s*")
	work_string = regex_list_end.sub(work_string, "\n\n", true) # Force blank line after list


	# --- Step 4: Final Newline Cleanup ---
	# Now, reduce sequences of 3 or more newlines down to 2 (one blank line)
	# This should respect the \n\n we just added around the lists.
	var regex_newlines = RegEx.new()
	regex_newlines.compile("\n{3,}")
	work_string = regex_newlines.sub(work_string, "\n\n", true)

	# Final trim
	work_string = work_string.strip_edges()


	# --- Debug Output (Optional) ---
	# print("--- Generated BBCode ---")
	# print(work_string)
	# print("-------------------------")

	return work_string
