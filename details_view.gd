# details_view.gd
extends Control

signal move_back_to_main_view
signal image_load_requested(url: String, texture_rect: TextureRect)

@export var product_screenshot_scene: PackedScene = preload("res://product_screenshot.tscn")
@export var screenshot_zoom_popup_scene: PackedScene = preload("res://screenshot_zoom_popup.tscn")
@export var reviews_popup_scene: PackedScene = preload("res://reviews_popup.tscn")

@onready var app_icon: TextureRect = $MarginContainer/Panel/DetailsContents/DetailsNavbar/AppIcon
@onready var app_title: RichTextLabel = $MarginContainer/Panel/DetailsContents/DetailsNavbar/TitleGroup/AppTitle
@onready var app_desc: RichTextLabel = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDescription/DetailsDescriptionScroller/AppDescription
@onready var screenshot_container: HBoxContainer = $MarginContainer/Panel/DetailsContents/ScreenshotClipContainer/ScrollContainer/ContainerScreenshots
@onready var app_developer: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerDeveloper/Developer
@onready var website_button: Button = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerWebsite/WebsiteButton
@onready var app_current_version: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerVersion/CurrentVersion
@onready var app_release_date: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerReleaseDate/ReleaseDate
@onready var action_button: Button = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/ActionButton
@onready var add_to_steam_button: Button = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/AddToSteamButton
@onready var app_installed_size: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/ContainerInstalledSize/InstalledSize
@onready var progress_info: VBoxContainer = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/MarginContainer/ProgressInfo
@onready var progress_bar: ProgressBar = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/MarginContainer/ProgressInfo/ProgressBar
@onready var progress_label: Label = $MarginContainer/Panel/DetailsContents/DetailsNavbar/HBoxContainer/MarginContainer/ProgressInfo/ProgressLabel
@onready var screenshot_scroll_container: ScrollContainer = $MarginContainer/Panel/DetailsContents/ScreenshotClipContainer/ScrollContainer
@onready var description_scroll_container: ScrollContainer = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDescription/DetailsDescriptionScroller
@onready var rating_stars_display: RatingStarsDisplay = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/RatingContainer/RatingStars/RatingStarsDisplayNode
@onready var show_reviews_button: Button = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/RatingContainer/ShowReviews
@onready var rating_label: Label = $MarginContainer/Panel/DetailsContents/ContainerDetailsMain/MarginContainerAppDetails/ContainerAppDetails/RatingContainer/RatingStars/MarginContainer/RatingCountLabel
@onready var verified_app: HBoxContainer = $MarginContainer/Panel/DetailsContents/DetailsNavbar/TitleGroup/MarginContainer/VerifiedContainer

# --- Internal State ---
var current_app_id: String = ""
var is_currently_installed: bool = false
var current_app_name: String = ""
var current_website_url: String = ""
var current_icon_url: String = ""
var is_known_to_be_in_steam: bool = true
var steam_check_pending: bool = false
var screenshot_zoom_popup_instance = null
var reviews_popup_instance: Control = null

func is_any_modal_open() -> bool:
	if is_instance_valid(screenshot_zoom_popup_instance) and screenshot_zoom_popup_instance.visible:
		return true
	if is_instance_valid(reviews_popup_instance) and reviews_popup_instance.visible:
		return true
	return false
var current_detailed_reviews: Array = []
var detailed_reviews_request: HTTPRequest = null
var _deckstore_abs_base_path: String = ""
var _api_cache_abs_path: String = ""
var _odrs_reviews_cache_abs_path: String = ""
var pulse_tween: Tween

# --- Constants ---
const DECKSTORE_BASE_DIR_NAME = ".deck-store" 
const API_CACHE_SUBDIR = "cache/api"          
const ODRS_REVIEWS_CACHE_SUBDIR = "cache/odrs_reviews"

const CACHE_DURATION_MSEC: int = 3600 * 1000 # 1 hour
const ODRS_DETAILED_REVIEWS_CACHE_DURATION_SEC = 60 * 60 * 6 # 6 hours
const DEFAULT_REVIEWS_BUTTON_CAPTION: String = "Show Reviews"
const REVIEWS_BUTTON_LOADING_CAPTION: String = "Loading..."

# =============================================================================
# BUILT-IN GODOT METHODS
# =============================================================================

func _ready():
	var home_dir = OS.get_environment("HOME")
	if home_dir.is_empty():
		printerr("DetailsView FATAL ERROR: Could not determine user's HOME directory. Caching will fail.")
		return

	_deckstore_abs_base_path = home_dir.path_join(DECKSTORE_BASE_DIR_NAME)
	_api_cache_abs_path = _deckstore_abs_base_path.path_join(API_CACHE_SUBDIR)
	_odrs_reviews_cache_abs_path = _deckstore_abs_base_path.path_join(ODRS_REVIEWS_CACHE_SUBDIR)

	print("INFO DetailsView: API Cache Directory (absolute Path): ", _api_cache_abs_path)
	print("INFO DetailsView: ODRS Reviews Cache Directory (absolute Path): ", _odrs_reviews_cache_abs_path)

	var err_api_cache = DirAccess.make_dir_recursive_absolute(_api_cache_abs_path)
	if err_api_cache != OK and err_api_cache != ERR_ALREADY_EXISTS:
		printerr("ERROR DetailsView: Could not create API cache directory: ", _api_cache_abs_path, ", Code: ", err_api_cache)

	var err_odrs_cache = DirAccess.make_dir_recursive_absolute(_odrs_reviews_cache_abs_path)
	if err_odrs_cache != OK and err_odrs_cache != ERR_ALREADY_EXISTS:
		printerr("ERROR DetailsView: Could not create ODRS reviews cache directory: ", _odrs_reviews_cache_abs_path, ", Code: ", err_odrs_cache)
		
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		if DownloadManager.has_signal("task_updated"):
			DownloadManager.task_updated.connect(_on_task_updated_for_progress)
		if DownloadManager.has_signal("task_finished"):
			DownloadManager.task_finished.connect(_on_task_finished_for_progress)
	else:
		printerr("DetailsView: DownloadManager Autoload not found!")

	if ProjectSettings.has_setting("autoload/SteamIntegration"):
		if SteamIntegration.has_signal("shortcut_action_completed"):
			SteamIntegration.shortcut_action_completed.connect(_on_shortcut_action_completed)

	var main_app_node = get_node_or_null("/root/App") 
	if main_app_node and main_app_node.has_signal("installed_apps_updated"):
		main_app_node.installed_apps_updated.connect(_on_installed_apps_refreshed)
		
	if is_instance_valid(show_reviews_button):
		show_reviews_button.pressed.connect(_on_show_reviews_button_pressed)
		show_reviews_button.mouse_entered.connect(func(): show_reviews_button.grab_focus())

	if is_instance_valid(action_button):
		action_button.mouse_entered.connect(func(): action_button.grab_focus())
		
	if is_instance_valid(website_button):
		website_button.pressed.connect(_on_website_button_pressed)
		website_button.mouse_entered.connect(func(): website_button.grab_focus())
		
	if is_instance_valid(add_to_steam_button):
		add_to_steam_button.mouse_entered.connect(func(): add_to_steam_button.grab_focus())

func _on_installed_apps_refreshed():
	print("DEBUG DetailsView: Installed apps refreshed signal received, updating button visibility for ", current_app_id)
	if self.visible and not current_app_id.is_empty():
		var main_app_node = get_node_or_null("/root/App") 
		if main_app_node and main_app_node.has_method("is_app_installed"):
			is_currently_installed = main_app_node.is_app_installed(current_app_id)
		steam_check_pending = false 
		_update_action_buttons_visibility()
		_trigger_steam_check_if_needed()

func _unhandled_input(event: InputEvent):
	# Only handle back button if this view is visible
	if not self.visible:
		return

	if is_any_modal_open():
		return
		
	if event.is_action_pressed("ui_cancel"):
		verified_app.visible = false
		emit_signal("move_back_to_main_view")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_accept"):
		var focused_control = get_viewport().gui_get_focus_owner()
		if focused_control.is_in_group("zoomable_screenshots"):
			var idx = focused_control.get_index()
			_open_screenshot_zoom_popup(idx)
			get_viewport().set_input_as_handled()
			return

# =============================================================================
# PUBLIC METHODS (called from main.gd or elsewhere)
# =============================================================================

func set_initial_state(assigned_id: String, initially_installed: bool, assigned_name: String = ""):
	print("DEBUG DetailsView: set_initial_state - AppID:", assigned_id, "Name:", assigned_name, "Installed:", initially_installed)
	current_app_id = assigned_id
	current_app_name = assigned_name
	is_currently_installed = initially_installed 
	is_known_to_be_in_steam = false 
	steam_check_pending = false 

	if is_instance_valid(action_button) and action_button.has_method("set_app_id_and_initial_state"):
		action_button.set_app_id_and_initial_state(assigned_id, is_currently_installed)
		# If we already have a name, we can set it on the action button too
		if not assigned_name.is_empty():
			action_button.app_name = assigned_name	
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
	current_app_name = ""
	is_known_to_be_in_steam = true
	if is_instance_valid(action_button) and action_button.has_method("_update_ui"): action_button._update_ui({})
	if is_instance_valid(add_to_steam_button): add_to_steam_button.visible = false
	if progress_info: progress_info.visible = false
	_clear_rating_ui() 
	
	if is_instance_valid(detailed_reviews_request):
		if detailed_reviews_request.is_connected("request_completed", Callable(self, "_on_detailed_reviews_request_completed")):
			detailed_reviews_request.request_completed.disconnect(Callable(self, "_on_detailed_reviews_request_completed"))
		detailed_reviews_request.queue_free()
		detailed_reviews_request = null
	current_detailed_reviews = []
	
# Main entry point to load data for the current_app_id
func load_details():
	if current_app_id.is_empty():
		printerr("ERROR: Cannot load details, app_id is empty.")
		app_title.text = "Error: No App ID" 
		_clear_rating_ui()
		return
	if progress_info: progress_info.visible = false
	_update_and_check_button_visibility()
	_load_details_data(current_app_id)	

func _on_shortcut_action_completed(action: String, app_id: String, success: bool):
	if action == "check" and app_id == current_app_id:
		print("DEBUG DetailsView: Received shortcut 'check' result for ", app_id, ". Found: ", success)
		is_known_to_be_in_steam = success
		steam_check_pending = false
		_update_action_buttons_visibility()
	elif (action == "add" or action == "remove") and app_id == current_app_id:
		print("DEBUG DetailsView: Add/Remove finished for ", app_id, " Re-triggering Steam check.")
		steam_check_pending = false
		_trigger_steam_check_if_needed()

# =============================================================================
# INTERNAL DATA LOADING & CACHING
# =============================================================================

# --- Helper function to get cache file path ---
func _get_api_cache_filepath(url: String) -> String:
	if _api_cache_abs_path.is_empty():
		printerr("ERROR DetailsView: _get_api_cache_filepath - API Cache Path not initialized!")
		return "" 
	var request_hash = url.md5_text()
	return _api_cache_abs_path.path_join(request_hash + ".json")
	
# --- Load details: Check cache or start request ---
func _load_details_data(app_id_to_load: String):
	_fetch_summary(app_id_to_load)
	
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
				
				var online_mgr = get_node_or_null("/root/OnlineStatusManager")
				var is_online = online_mgr.is_online if online_mgr else true

				if (not is_online or cache_age < CACHE_DURATION_MSEC) and api_data != null:
					_display_details(api_data)
					return
				else:
					DirAccess.remove_absolute(cache_filepath)
			else:
				DirAccess.remove_absolute(cache_filepath)
		else:
			printerr("ERROR: Opening cache file %s failed: %s" % [cache_filepath.get_file(), open_error])
			if is_instance_valid(file): file.close()

	# --- Cache MISS or expired: Start HTTP Request ---
	if Engine.has_singleton("OnlineStatusManager") and not get_node("/root/OnlineStatusManager").is_online:
		print("INFO DetailsView: App is offline. Using fallback info for ", current_app_id)
		_show_fallback_product()
		return
		
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(
		_on_product_details_request_completed.bind(http_request, detail_api_url) # Bind URL
	)
	var error = http_request.request(detail_api_url)
	if error != OK:
		printerr("ERROR: Starting details request failed for '%s' (%s): %s" % [app_id_to_load, detail_api_url, error])
		_show_fallback_product()
		if is_instance_valid(http_request): http_request.queue_free()

# --- Handle request completion: Save to cache and display ---
func _on_product_details_request_completed(result, response_code, headers, body, http_request: HTTPRequest, url: String):
	if response_code == 200 and result == HTTPRequest.RESULT_SUCCESS:
		var response_string = body.get_string_from_utf8()
		var api_json = JSON.parse_string(response_string)

		if api_json != null:
			# ... (cache logic remains same)
			_display_details(api_json)
		else:
			printerr("ERROR: JSON parse error for URL '%s'." % url)
			app_title.text = "Error: Invalid Data" 
	elif response_code == 404:
		print("INFO DetailsView: App not found on Flathub (404). Using fallback info for ", current_app_id)
		_show_fallback_product()
	else:
		printerr("ERROR: HTTP Error %d (Result %d) requesting details from '%s'." % [response_code, result, url])
		_show_fallback_product()

	# --- Cleanup ---
	# hide_loading_indicator() # Optional
	if is_instance_valid(http_request):
		http_request.queue_free()

func _fetch_summary(app_id: String):
	app_installed_size.text = "Loading..."
	if Engine.has_singleton("OnlineStatusManager") and not get_node("/root/OnlineStatusManager").is_online:
		app_installed_size.text = "Offline"
		return

	var summary_url = "https://flathub.org/api/v2/summary/%s" % app_id
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(
		_on_summary_request_completed.bind(http_request)
	)
	var error = http_request.request(summary_url)
	if error != OK:
		printerr("ERROR: Starting summary request failed for '%s' (%s): %s" % [app_id, summary_url, error])
		app_installed_size.text = "Unknown"
		if is_instance_valid(http_request): http_request.queue_free()

func _on_summary_request_completed(result, response_code, headers, body, http_request: HTTPRequest):
	if response_code == 200 and result == HTTPRequest.RESULT_SUCCESS:
		var response_string = body.get_string_from_utf8()
		var summary_json = JSON.parse_string(response_string)
		if summary_json != null and summary_json is Dictionary:
			var size_bytes = summary_json.get("installed_size", 0)
			if size_bytes > 0:
				app_installed_size.text = String.humanize_size(int(size_bytes))
				if is_instance_valid(action_button):
					action_button.app_size_bytes = int(size_bytes)
			else:
				app_installed_size.text = "Unknown"
		else:
			app_installed_size.text = "Unknown"
	else:
		app_installed_size.text = "Unknown"

	if is_instance_valid(http_request):
		http_request.queue_free()

func _show_fallback_product():
	var fallback_product = {
		"id": current_app_id,
		"name": current_app_name if not current_app_name.is_empty() else current_app_id,
		"description": "Metadata is currently unavailable because the application is not listed on Flathub or you are offline. You can still manage the installation if it is installed locally.",
		"icon": "",
		"developer_name": "Unknown",
		"releases": []
	}
	_display_details(fallback_product)


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
	app_title.text = product.get("name") if product.get("name") != null else "N/A"
	var icon_url = product.get("icon")
	if icon_url and not icon_url.is_empty():
		emit_signal("image_load_requested", icon_url, app_icon)
	else:
		app_icon.texture = null # Clear old icon if none provided

	# verified
	verified_app.visible = false
	var metadata = product.get("metadata", false)
	if metadata:
		print("DEBUG App metadata: ", metadata)
		var verified_flag = metadata.get("flathub::verification::verified", false)
		print("DEBUG App verified_flag: ", verified_flag)
		if verified_flag:
			verified_app.visible = true

	# description
	var description_html = product.get("description", "")
	app_desc.text = limited_html_to_bbcode(description_html) if not description_html.is_empty() else "No description available."

	# screenshots
	# Clear old ones first
	for child in screenshot_container.get_children():
		screenshot_container.remove_child(child)
		child.queue_free()
	# Add new ones
	var screenshots_data = product.get("screenshots", []) 
	if screenshots_data is Array:
		for screenshot_collection in screenshots_data:
			if screenshot_collection is Dictionary and screenshot_collection.has("sizes"):
				var screenshot_sizes = screenshot_collection.get("sizes", []) 
				if screenshot_sizes is Array and not screenshot_sizes.is_empty():
					var screenshot = screenshot_sizes[0] 
					if screenshot is Dictionary:
						var screenshot_url = screenshot.get("src", "")
						if not screenshot_url.is_empty():
							var screenshot_instance = product_screenshot_scene.instantiate()
							if screenshot_instance:
								screenshot_instance.add_to_group("zoomable_screenshots")
								screenshot_container.add_child(screenshot_instance)
								var screenshot_rect = screenshot_instance.find_child("Screenshot", true, false) as TextureRect 
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
			app_current_version.text = latest_release.get("version") if latest_release.get("version") != null else "N/A"
			var timestamp_str = str(latest_release.get("timestamp", ""))
			if not timestamp_str.is_empty() and timestamp_str.is_valid_int():
				var timestamp_int = int(timestamp_str)
				var datetime_dict: Dictionary = Time.get_datetime_dict_from_unix_time(timestamp_int)
				var day = str(datetime_dict["day"]).pad_zeros(2)
				var month = str(datetime_dict["month"]).pad_zeros(2)
				var year = str(datetime_dict["year"])
				app_release_date.text = "%s-%s-%s" % [year, month, day] 
			else:
				app_release_date.text = "N/A"
		else:
			app_current_version.text = "N/A"
			app_release_date.text = "N/A"
	else:
		app_current_version.text = "N/A"
		app_release_date.text = "N/A"
		
	var main_app_node = get_node_or_null("/root/App")
	if main_app_node and main_app_node._installed_flatpak_ids.has(current_app_id):
		app_installed_size.text = main_app_node._installed_flatpak_ids[current_app_id].get("size", "Unknown")
	else:
		app_installed_size.text = "N/A"
		
	current_app_name = product.get("name") if product.get("name") != null else "N/A"
	app_developer.text = product.get("developer_name") if product.get("developer_name") != null else "N/A"
	
	# Extract Website URL
	var urls_dict = product.get("urls", {})
	if typeof(urls_dict) == TYPE_DICTIONARY:
		current_website_url = urls_dict.get("homepage", "")
		if current_website_url.is_empty():
			current_website_url = urls_dict.get("bugtracker", "")
	
	if is_instance_valid(website_button):
		if not current_website_url.is_empty():
			website_button.visible = true
			website_button.get_parent().visible = true
		else:
			website_button.visible = false
			website_button.get_parent().visible = false
	
	var safe_icon_url = icon_url if icon_url != null else ""

	if is_instance_valid(action_button) and action_button.has_method("set_app_info"):
		action_button.set_app_info(current_app_id, current_app_name, safe_icon_url)
			
	if is_instance_valid(add_to_steam_button) and add_to_steam_button.has_method("set_app_info"):
		add_to_steam_button.set_app_info(current_app_id, current_app_name, safe_icon_url)
	_update_action_buttons_visibility()
	_trigger_steam_check_if_needed()
	_clear_rating_ui()
	if not current_app_id.is_empty():
		_update_rating_display(current_app_id) 

func _update_rating_display(app_id_for_rating: String):
	if app_id_for_rating.is_empty():
		_clear_rating_ui()
		return

	if not ProjectSettings.has_setting("autoload/OdrsRatingsCache"):
		printerr("DetailsView: OdrsRatingsCache Autoload not found!")
		_clear_rating_ui()
		return
		
	var summary = OdrsRatingsCache.get_rating_summary(app_id_for_rating)

	if summary.is_empty():
		_clear_rating_ui()
		return

	var s1 = summary.get("star1", 0)
	var s2 = summary.get("star2", 0)
	var s3 = summary.get("star3", 0)
	var s4 = summary.get("star4", 0)
	var s5 = summary.get("star5", 0)
	var total_score = float(s1*1 + s2*2 + s3*3 + s4*4 + s5*5)
	var total_valid_votes = s1 + s2 + s3 + s4 + s5
	
	var avg_rating = -1.0
	if total_valid_votes > 0:
		avg_rating = total_score / float(total_valid_votes)
	
	var total_reviews_from_summary = summary.get("total", 0)

	if is_instance_valid(rating_stars_display):
		if rating_stars_display.has_method("set_stars"):
			rating_stars_display.set_stars(avg_rating)
		else: 
			rating_stars_display.visible = (avg_rating >= 0) 
	
	if is_instance_valid(rating_label):
		if total_reviews_from_summary > 0:
			rating_label.text = "(%d)" % total_reviews_from_summary
			rating_label.visible = true
		else:
			rating_label.visible = false
			
	if is_instance_valid(show_reviews_button):
		show_reviews_button.disabled = (total_reviews_from_summary == 0)
		show_reviews_button.visible = true

func _clear_rating_ui():
	if is_instance_valid(rating_stars_display):
		if rating_stars_display.has_method("set_stars"):
			rating_stars_display.set_stars(-1.0)
		else:
			rating_stars_display.visible = false
	if is_instance_valid(rating_label):
		rating_label.visible = false
		rating_label.text = ""
	if is_instance_valid(show_reviews_button):
		show_reviews_button.visible = false
		show_reviews_button.disabled = true

func _on_website_button_pressed():
	if not current_website_url.is_empty():
		var steam_integration = get_node_or_null("/root/SteamIntegration")
		if steam_integration and steam_integration.has_method("open_url"):
			steam_integration.open_url(current_website_url)
		else:
			OS.shell_open(current_website_url)

func _open_screenshot_zoom_popup(start_index: int):
	if not screenshot_zoom_popup_scene:
		printerr("DetailsView: ScreenshotZoomPopup scene not preloaded!")
		return

	var textures: Array[Texture2D] = []
	for child in screenshot_container.get_children():
		var tex_rect = child.get_node_or_null("MarginContainer/Panel/MarginContainer/Screenshot") as TextureRect
		if tex_rect and tex_rect.texture:
			textures.append(tex_rect.texture)

	if textures.is_empty(): return

	if not is_instance_valid(screenshot_zoom_popup_instance):
		screenshot_zoom_popup_instance = screenshot_zoom_popup_scene.instantiate()
		add_child(screenshot_zoom_popup_instance) 
	
	if screenshot_zoom_popup_instance.has_method("popup_zoomed_image_list"):
		var focused_element_before_popup = get_viewport().gui_get_focus_owner()
		screenshot_zoom_popup_instance.popup_zoomed_image_list(textures, start_index, focused_element_before_popup)
	else:
		printerr("DetailsView: ScreenshotZoomPopup instance does not have 'popup_zoomed_image_list' method.")

# --- Set initial focus when view becomes active ---
func set_initial_focus():
	description_scroll_container.remove_theme_stylebox_override("panel")
	if is_instance_valid(action_button) and action_button.visible and not action_button.disabled:
		action_button.grab_focus()
	elif is_instance_valid(add_to_steam_button) and add_to_steam_button.visible and not add_to_steam_button.disabled:
		add_to_steam_button.grab_focus()
	else:
		if is_instance_valid(screenshot_scroll_container):
			screenshot_scroll_container.grab_focus()

func _update_action_buttons_visibility():
	print("DEBUG DetailsView: Updating button visibility. Current AppID=", current_app_id) 

	if current_app_id.is_empty():
		if is_instance_valid(action_button): action_button.visible = false
		if is_instance_valid(add_to_steam_button): add_to_steam_button.visible = false
		return

	var main_app_node = get_node_or_null("/root/App") 
	var is_installed = false
	if main_app_node and main_app_node.has_method("is_app_installed"):
		is_installed = main_app_node.is_app_installed(current_app_id)

	var task_status_data = DownloadManager.get_task_status(current_app_id)
	var task_status = task_status_data.get("status", null)
	var task_is_active = task_status != null and not ["completed", "failed", "cancelled"].has(task_status)
	print("DEBUG DetailsView: Is task active? ", task_is_active, " (Status: ", task_status, ")") 
	if is_instance_valid(action_button):
		action_button.visible = true
		print("DEBUG DetailsView: Setting ActionButton visible: ", action_button.visible)

	if is_instance_valid(add_to_steam_button):
		add_to_steam_button.visible = not task_is_active and is_installed and not is_known_to_be_in_steam
		print("DEBUG DetailsView: Setting 'Add to Steam' visibility: ", add_to_steam_button.visible) # DEBUG

func _trigger_steam_check_if_needed():
	if is_currently_installed and not steam_check_pending:
		print("DEBUG DetailsView: Triggering async Steam check for ", current_app_id)
		if ProjectSettings.has_setting("autoload/SteamIntegration") and SteamIntegration.has_method("check_in_steam_async"):
			var started = SteamIntegration.check_in_steam_async(current_app_id)
			if started:
				steam_check_pending = true 
			else:
				print("WARN DetailsView: Could not start async Steam check.")
		else:
			printerr("DetailsView: Cannot trigger Steam status check (SteamIntegration missing?).")

func _update_and_check_button_visibility():
	var main_app_node = get_node_or_null("/root/App") 
	var is_installed = false
	if main_app_node and main_app_node.has_method("is_app_installed"):
		is_installed = main_app_node.is_app_installed(current_app_id)
	else:
		printerr("DetailsView: Cannot check installed status from main node!")
		if is_instance_valid(action_button): action_button.visible = true
		if is_instance_valid(add_to_steam_button): add_to_steam_button.visible = false
		return

	_set_button_visibility(is_installed, is_known_to_be_in_steam)

	if is_installed:
		if ProjectSettings.has_setting("autoload/SteamIntegration") and SteamIntegration.has_method("check_in_steam_async"):
			print("DEBUG DetailsView: App is installed, triggering async check if needed...")
			SteamIntegration.check_in_steam_async(current_app_id)
		else:
			printerr("DetailsView: Cannot trigger Steam status check!")


func _set_button_visibility(is_installed : bool, is_in_steam : bool):
	if is_instance_valid(action_button):
		action_button.visible = true

	if is_instance_valid(add_to_steam_button):
		add_to_steam_button.visible = is_installed and not is_in_steam
		print("DEBUG DetailsView: Setting 'Add to Steam' visibility: ", add_to_steam_button.visible, " (Installed=", is_installed, ", InSteam=", is_in_steam, ")")

func _on_task_updated_for_progress(operation_id: String, status_data: Dictionary):
	if is_instance_valid(action_button) and operation_id == action_button.current_operation_id:
		var status = status_data.get("status", "unknown")
		var progress = status_data.get("progress", null)
		var op_type = status_data.get("operation_type", "unknown")

		var should_show_progress = false
		if status == "downloading" or status == "installing":
			should_show_progress = true

		if should_show_progress:
			if progress_info: progress_info.visible = true
			if progress_bar: 
				progress_bar.value = progress
				if progress >= 100.0 and status == "installing":
					_start_pulse()
				else:
					_stop_pulse()
			if progress_label:
				var label_text = ""
				var current_idx = status_data.get("current_idx", -1)
				var total_idx = status_data.get("total_idx", -1)
				var step_info = ""
				if current_idx != -1 and total_idx != -1:
					step_info = " (Step %d/%d)" % [current_idx, total_idx]

				match status:
					"downloading": 
						label_text = "Downloading (%d%%)" % progress if progress != null else "Downloading..."
						label_text += step_info
						var speed = status_data.get("speed", null)
						var eta = status_data.get("eta", null)
						if speed: label_text += " [%s]" % speed
						if eta: label_text += " (%s)" % eta
					"installing": 
						label_text = "Installing..." + step_info
					_: label_text = "Status: %s" % status + step_info
				progress_label.text = label_text
		else:
			_stop_pulse()
			if progress_info: progress_info.visible = false

func _start_pulse():
	if pulse_tween and pulse_tween.is_valid(): return
	pulse_tween = create_tween().bind_node(progress_bar).set_loops()
	pulse_tween.tween_property(progress_bar, "modulate:a", 0.3, 0.6).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(progress_bar, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

func _stop_pulse():
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
	if is_instance_valid(progress_bar):
		progress_bar.modulate.a = 1.0
			
func _on_task_finished_for_progress(operation_id: String, final_status: String, op_type: String = ""):
	if is_instance_valid(action_button) and operation_id == action_button.current_operation_id:
		_stop_pulse()
		if progress_info: progress_info.visible = false
		if progress_bar: progress_bar.value = 0

		var main_app_node = get_node_or_null("/root/App")
		if main_app_node and main_app_node.has_method("is_app_installed"):
			is_currently_installed = main_app_node.is_app_installed(current_app_id)

		steam_check_pending = false
		_update_action_buttons_visibility()
		_trigger_steam_check_if_needed()


# Function to convert a limited subset of HTML to Godot-compatible BBCode
func limited_html_to_bbcode(html_string: String) -> String:
	# print("--- Incoming HTML ---")
	# print(html_string)
	# print("-------------------------")
	var work_string: String = html_string

	var regex_p_open = RegEx.new()
	regex_p_open.compile("\\s*<p>\\s*")
	work_string = regex_p_open.sub(work_string, "\n", true)
	var regex_p_close = RegEx.new()
	regex_p_close.compile("\\s*</p>\\s*")
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
	var regex_ul_open = RegEx.new()
	regex_ul_open.compile("\\s*<ul>\\s*")
	work_string = regex_ul_open.sub(work_string, "<LIST_START>", true)
	var regex_ol_open = RegEx.new()
	regex_ol_open.compile("\\s*<ol>\\s*")
	work_string = regex_ol_open.sub(work_string, "<LIST_START>", true) # Treat ol like ul for now

	var regex_ul_close = RegEx.new()
	regex_ul_close.compile("\\s*</ul>\\s*")
	work_string = regex_ul_close.sub(work_string, "<LIST_END>", true)
	var regex_ol_close = RegEx.new()
	regex_ol_close.compile("\\s*</ol>\\s*")
	work_string = regex_ol_close.sub(work_string, "<LIST_END>", true)

	var regex_li_open = RegEx.new()
	regex_li_open.compile("\\s*<li>\\s*")
	work_string = regex_li_open.sub(work_string, "<ITEM_START>", true)
	var regex_li_close = RegEx.new()
	regex_li_close.compile("\\s*</li>\\s*")
	work_string = regex_li_close.sub(work_string, "<ITEM_END>", true)

	var regex_tags = RegEx.new()
	regex_tags.compile("<(?!LIST_START|LIST_END|ITEM_START|ITEM_END)[^>]*>") # Remove HTML tags EXCEPT our placeholders
	work_string = regex_tags.sub(work_string, "", true)
	work_string = work_string.xml_unescape()

	var regex_item_start = RegEx.new()
	regex_item_start.compile("\\s*<ITEM_START>\\s*")
	work_string = regex_item_start.sub(work_string, "[indent]\u2022  ", true) # Bullet + two spaces
	var regex_item_end = RegEx.new()
	regex_item_end.compile("\\s*<ITEM_END>\\s*")
	work_string = regex_item_end.sub(work_string, "[/indent]\n", true) # Close indent + newline

	# Replace list container placeholders, adding the definitive spacing HERE
	var regex_list_start = RegEx.new()
	regex_list_start.compile("\\s*<LIST_START>\\s*")
	work_string = regex_list_start.sub(work_string, "\n\n", true) # Force blank line before list
	var regex_list_end = RegEx.new()
	regex_list_end.compile("\\s*<LIST_END>\\s*")
	work_string = regex_list_end.sub(work_string, "\n\n", true) # Force blank line after list
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

func _on_show_reviews_button_pressed():
	print("DetailsView: 'Show reviews' clicked for App ID: ", current_app_id)
	if current_app_id.is_empty(): 
		printerr("DetailsView: No current_app_id for loading reviews.")
		return
	const DEFAULT_REVIES_BUTTON_CAPTION: String = "Show Reviews"
	show_reviews_button.disabled = true
	show_reviews_button.text = REVIEWS_BUTTON_LOADING_CAPTION
	
	var cache_filepath = _get_detailed_reviews_cache_filepath(current_app_id)

	if FileAccess.file_exists(cache_filepath):
		print("DEBUG Using existing cache file")
		var file = FileAccess.open(cache_filepath, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			var cache_content = JSON.parse_string(json_string)
			file.close()
			
			if cache_content is Dictionary:
				var timestamp = cache_content.get("timestamp", 0)
				var cached_reviews_array = cache_content.get("reviews_data")
				var cache_age_sec = (Time.get_unix_time_from_system() - timestamp)
				
				if cache_age_sec < ODRS_DETAILED_REVIEWS_CACHE_DURATION_SEC and cached_reviews_array is Array:
					print("DetailsView: Loaded detailed reviews from cache ", current_app_id)
					current_detailed_reviews = cached_reviews_array
					_show_reviews_popup(current_detailed_reviews)
					return

	print("DetailsView: No valid cache for detailed reviews. Starting to fetch ratings for ", current_app_id)
	_fetch_detailed_reviews(current_app_id)

func _get_detailed_reviews_cache_filepath(app_id: String) -> String:
	if _odrs_reviews_cache_abs_path.is_empty():
		printerr("ERROR DetailsView: _get_detailed_reviews_cache_filepath - ODRS Reviews Cache Path not initialized!")
		return ""
	var request_hash = app_id.md5_text()
	return _odrs_reviews_cache_abs_path.path_join(request_hash + ".json")

func _fetch_detailed_reviews(app_id: String):
	if app_id.is_empty(): return

	var odrs_reviews_url = "https://odrs.gnome.org/1.0/reviews/api/app/%s" % app_id

	print("DetailsView: Fetching detailed reviews from: ", odrs_reviews_url)

	if is_instance_valid(detailed_reviews_request):
		if detailed_reviews_request.is_connected("request_completed", Callable(self, "_on_detailed_reviews_request_completed")):
			detailed_reviews_request.request_completed.disconnect(Callable(self, "_on_detailed_reviews_request_completed"))
		detailed_reviews_request.queue_free()

	detailed_reviews_request = HTTPRequest.new()
	add_child(detailed_reviews_request)
	detailed_reviews_request.request_completed.connect(
		_on_detailed_reviews_request_completed.bind(odrs_reviews_url, app_id) # URL und app_id für Kontext binden
	)
	
	var error = detailed_reviews_request.request(odrs_reviews_url)
	if error != OK:
		printerr("DetailsView: Starten des Detailed Reviews Request fehlgeschlagen für '%s': %s" % [odrs_reviews_url, error])
		if is_instance_valid(detailed_reviews_request):
			detailed_reviews_request.queue_free()
			detailed_reviews_request = null
		# Optional: Fehlermeldung im Popup anzeigen
		var popup_instance = get_node_or_null("ReviewsPopupInstance") # Annahme: Popup ist schon da und heißt so
		if is_instance_valid(popup_instance) and popup_instance.has_method("show_error"):
			popup_instance.show_error("Fehler beim Laden der Bewertungen.")


func _on_detailed_reviews_request_completed(result, response_code, headers, body, url: String, app_id_ctx: String):
	var reviews_to_display: Array = []
	var success = false

	if response_code == 200 and result == HTTPRequest.RESULT_SUCCESS:
		var response_string = body.get_string_from_utf8()
		var odrs_json = JSON.parse_string(response_string)
		if odrs_json is Array:
			reviews_to_display = odrs_json
			current_detailed_reviews = reviews_to_display # Für sofortige Anzeige merken
			success = true
			
			# Daten für diese App im Cache speichern
			var cache_content = {
				"timestamp": Time.get_unix_time_from_system(),
				"reviews_data": reviews_to_display
			}
			var cache_filepath = _get_detailed_reviews_cache_filepath(app_id_ctx) # app_id_ctx ist die gebundene app_id
			var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
			if file:
				file.store_string(JSON.stringify(cache_content))
				file.close()
				print("DetailsView: Detaillierte Reviews für ", app_id_ctx, " gecached.")
			else:
				printerr("DetailsView: Fehler beim Schreiben der Cache-Datei für detaillierte Reviews: ", cache_filepath)
		else:
			printerr("DetailsView: JSON Parse-Fehler für detaillierte Reviews URL '%s'." % url)
	elif response_code == 404:
		printerr("DetailsView: Detaillierte Reviews nicht gefunden (404) für URL '%s'." % url)
		current_detailed_reviews = [] # Leeren, falls vorher was drin war
	else:
		printerr("DetailsView: HTTP Fehler %d (Result %d) bei Abfrage von detaillierten Reviews von '%s'." % [response_code, result, url])
		current_detailed_reviews = []

	_show_reviews_popup(current_detailed_reviews, not success and response_code != 404) # error_flag übergeben, außer bei 404

	if is_instance_valid(detailed_reviews_request):
		detailed_reviews_request.queue_free()
		detailed_reviews_request = null

func _show_reviews_popup(reviews_array: Array, has_error: bool = false):
	print("DEBUG Called _show_reviews_popup")
	
	if not is_instance_valid(reviews_popup_instance):
		print("DEBUG Instance not yet valid. Create instance...")
		if not reviews_popup_scene:
			printerr("DetailsView: reviews_popup_scene not loaded!")
			return
		reviews_popup_instance = reviews_popup_scene.instantiate()
		add_child(reviews_popup_instance)
		
		show_reviews_button.disabled = false
		show_reviews_button.text = DEFAULT_REVIEWS_BUTTON_CAPTION

	if not is_instance_valid(reviews_popup_instance):
		printerr("DetailsView: Could not instantiate Review-Popup.")
		return
	
	if reviews_popup_instance.has_method("display_reviews"):
		reviews_popup_instance.display_reviews(reviews_array, current_app_name, has_error)
	
	if reviews_popup_instance.has_method("show_modal"):
		reviews_popup_instance.show_modal()
	else:
		reviews_popup_instance.visible = true
