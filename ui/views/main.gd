extends Control

@export var product_box: PackedScene = preload("res://ui/components/product_box.tscn")
@export var product_list_scene: PackedScene = preload("res://ui/components/product_list.tscn")
@export var settings_modal_scene: PackedScene = preload("res://ui/modals/settings_modal.tscn")
@export var app_menu_modal_scene: PackedScene = preload("res://ui/modals/app_menu_modal.tscn")
@export var downloads_flyout_scene: PackedScene = preload("res://ui/modals/downloads_flyout.tscn")

@onready var details_view: Control = $DetailsView
@onready var main_view: VBoxContainer = $CanvasLayer/VBoxContainer

@onready var section_view_container: Control = $CanvasLayer/VBoxContainer/SectionViewContainer


@onready var toast_container: VBoxContainer = VBoxContainer.new()

@onready var home_button: Button = $CanvasLayer/VBoxContainer/TopButtonBar/ButtonHome
@onready var top_button_bar: HBoxContainer = $CanvasLayer/VBoxContainer/TopButtonBar
@onready var l1_glyph: TextureRect = $CanvasLayer/VBoxContainer/TopButtonBar/L1Glyph
@onready var r1_glyph: TextureRect = $CanvasLayer/VBoxContainer/TopButtonBar/R1Glyph
var global_scroll_container: ScrollContainer = null
@onready var footer_bar: PanelContainer = $CanvasLayer/FooterBar
@onready var select_sound: AudioStreamPlayer = $SelectSoundPlayer
@onready var focus_sound: AudioStreamPlayer = $FocusSoundPlayer
@onready var back_sound: AudioStreamPlayer = $BackSoundPlayer
@onready var switch_sound: AudioStreamPlayer = $SwitchSoundPlayer

var _installed_flatpak_ids: Dictionary = {}
var _flatpak_list_output: String = ""
var _flatpak_thread: Thread = null
var _last_focused_product_box: Control = null
var _current_home_view_instance: Control = null
var _settings_modal_instance: CanvasLayer = null
var _app_menu_modal_instance: CanvasLayer = null
var _downloads_flyout_instance: CanvasLayer = null
var _sections: Array[Dictionary] = [
	{"name": "Home", "scene_path": "res://sections/home_view.tscn", "button_node_name": "ButtonHome", "instance": null},
	{"name": "Categories", "scene_path": "res://sections/categories_view.tscn", "button_node_name": "ButtonCategories", "instance": null},
	{"name": "Installed", "scene_path": "res://sections/installed_view.tscn", "button_node_name": "ButtonInstalled", "instance": null},
	{"name": "Updates", "scene_path": "res://sections/updates_view.tscn", "button_node_name": "ButtonUpdates", "instance": null},
	{"name": "Extensions", "scene_path": "res://sections/extensions_view.tscn", "button_node_name": "ButtonExtensions", "instance": null},
	{"name": "Search", "scene_path": "res://sections/search_view.tscn", "button_node_name": "ButtonSearch", "instance": null}
]
var _current_section_index: int = 0
var _is_switching_section: bool = false
var _suppress_focus_sound: bool = false
var _current_connected_item: Control = null

const DECKSTORE_BASE_DIR_NAME = ".deck-store"
const API_CACHE_SUBDIR = "cache/api"
const IMAGE_CACHE_SUBDIR = "cache/images"

const CACHE_DURATION_SEC: int = 3600
const IMAGE_CACHE_DURATION_SEC: int = 7 * 24 * 60 * 60

var transition_time := 0.5
var transition_time_section_change := 0.2

var _deckstore_abs_base_path: String = ""
var _api_cache_abs_path: String = ""
var _image_cache_abs_path: String = ""

signal installed_apps_updated


func _ready():
	var home_dir = OS.get_environment("HOME")
	if home_dir.is_empty():
		printerr("FATAL ERROR: Could not determine user's HOME directory. Caching will fail.")
		return

	_deckstore_abs_base_path = home_dir.path_join(DECKSTORE_BASE_DIR_NAME)
	_api_cache_abs_path = _deckstore_abs_base_path.path_join(API_CACHE_SUBDIR)
	_image_cache_abs_path = _deckstore_abs_base_path.path_join(IMAGE_CACHE_SUBDIR)
	
	print("INFO: DeckStore Base Path (absolute): ", _deckstore_abs_base_path)
	print("INFO: API Cache Directory (absolute Path): ", _api_cache_abs_path)
	print("INFO: Image Cache Directory (absolute Path): ", _image_cache_abs_path)

	var err_api_cache = DirAccess.make_dir_recursive_absolute(_api_cache_abs_path)
	if err_api_cache != OK and err_api_cache != ERR_ALREADY_EXISTS:
		printerr("ERROR: Could not create API cache directory: ", _api_cache_abs_path, ", Code: ", err_api_cache)
	
	var err_img_cache = DirAccess.make_dir_recursive_absolute(_image_cache_abs_path)
	if err_img_cache != OK and err_img_cache != ERR_ALREADY_EXISTS:
		printerr("ERROR: Could not create image cache directory: ", _image_cache_abs_path, ", Code: ", err_img_cache)
			
	var section_btn_group = ButtonGroup.new()
	
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.627, 0.125, 0.941, 0.6)
	style_pressed.set_border_width_all(3)
	style_pressed.border_color = Color(0.627, 0.125, 0.941, 1)
	
	
	var style_normal = StyleBoxEmpty.new()
	
	home_button.focus_mode = Control.FOCUS_ALL
	for btn in top_button_bar.get_children():
		if btn is Button: 
			btn.focus_mode = Control.FOCUS_ALL
			btn.toggle_mode = true
			btn.button_group = section_btn_group
			btn.add_theme_stylebox_override("pressed", style_pressed)
			btn.add_theme_stylebox_override("normal", style_normal)

	for i in range(_sections.size()):
		var section_data = _sections[i]
		var scene = load(section_data.scene_path) as PackedScene
		if scene:
			var instance = scene.instantiate()
			_sections[i].instance = instance 
			
			if section_data.name == "Home":
				_current_home_view_instance = instance
				if "product_box_scene" in instance:
					instance.product_box_scene = product_box
			
			_connect_section_signals(instance)
			
			instance.visible = (i == 0)
			section_view_container.add_child(instance)
		else:
			printerr("ERROR: Could not load scene for section: ", section_data.name)

	for i in range(_sections.size()):
		var section_data = _sections[i]
		var button_node = top_button_bar.get_node_or_null(section_data.button_node_name) as Button
		if is_instance_valid(button_node):
			button_node.pressed.connect(_on_top_bar_button_pressed.bind(i))
		else:
			printerr("ERROR: Button node not found for section: ", section_data.name)

	for btn_node in top_button_bar.get_children():
		if btn_node is Button:
			btn_node.focus_entered.connect(_on_top_bar_button_focus_entered)
			btn_node.mouse_entered.connect(func(): btn_node.grab_focus())
			
	load_popular_products()
	load_trending_products()
	
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	details_view.move_back_to_main_view.connect(_on_move_back_to_main_view)
	details_view.image_load_requested.connect(_on_product_list_image_load_requested)

	if l1_glyph: l1_glyph.pressed.connect(_apply_glyph_feedback.bind(-1))
	if r1_glyph: r1_glyph.pressed.connect(_apply_glyph_feedback.bind(1))

	get_viewport().gui_focus_changed.connect(_on_focus_changed)

	_check_connected_controllers() 
	print("-----------------------------------------")
	
	_settings_modal_instance = settings_modal_scene.instantiate()
	add_child(_settings_modal_instance)
	
	if app_menu_modal_scene:
		_app_menu_modal_instance = app_menu_modal_scene.instantiate()
		add_child(_app_menu_modal_instance)
		
	if downloads_flyout_scene:
		_downloads_flyout_instance = downloads_flyout_scene.instantiate()
		_downloads_flyout_instance.opened.connect(_update_footer_prompts)
		_downloads_flyout_instance.closed.connect(_update_footer_prompts)
		add_child(_downloads_flyout_instance)
	
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_apply_ui_sounds_setting(SettingsManager.get_setting("play_ui_sounds", true))
	
	if Engine.has_singleton("OnlineStatusManager"):
		var online_mgr = get_node("/root/OnlineStatusManager")
		online_mgr.online_status_changed.connect(_on_online_status_changed)
		_on_online_status_changed(online_mgr.is_online)
	
	$CanvasLayer.add_child(toast_container)
	toast_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toast_container.anchor_left = 0.0
	toast_container.anchor_right = 0.0
	toast_container.offset_left = 20
	toast_container.offset_right = 320
	toast_container.offset_top = 60
	toast_container.grow_horizontal = Control.GROW_DIRECTION_END
	toast_container.add_theme_constant_override("separation", 10)
	
	if ProjectSettings.has_setting("autoload/DownloadManager"):
		var dm = get_node_or_null("/root/DownloadManager")
		if dm:
			if dm.has_signal("task_updated"): dm.task_updated.connect(_on_download_task_updated)
			if dm.has_signal("task_finished"): dm.task_finished.connect(_on_download_task_finished)
			
			var footer = get_node_or_null("CanvasLayer/FooterBar")
			if is_instance_valid(footer) and footer.has_method("set_context_actions"):
				footer.call_deferred("update_context_actions")
				
	if ProjectSettings.has_setting("autoload/SteamIntegration"):
		var steam_int = get_node_or_null("/root/SteamIntegration")
		if steam_int and steam_int.has_signal("shortcut_action_completed"):
			steam_int.shortcut_action_completed.connect(_on_shortcut_action_completed)

	if get_node_or_null("/root/SelfUpdateManager"):
		var sum = get_node("/root/SelfUpdateManager")
		sum.update_available.connect(func(ver, _notes):
			_show_toast("DeckStore Update %s available in Settings!" % ver, true)
		)
	
	_switch_to_section(0)
	
	var current_focus = get_viewport().gui_get_focus_owner()
	if current_focus:
		current_focus.release_focus()
		
	_ensure_user_remote_exists()
	_fetch_installed_apps()
	_update_footer_prompts()
	
	if GlobalBackgroundShader.has_method("transition_to_background"):
		GlobalBackgroundShader.transition_to_background()
		await GlobalBackgroundShader.transition_finished
		
	_suppress_focus_sound = true
	home_button.grab_focus()
	await get_tree().process_frame
	_suppress_focus_sound = false

func _on_shortcut_action_completed(action: String, app_id: String, success: bool):
	if action == "add" and success:
		if SettingsManager.get_setting("show_steam_restart_warning", true):
			await get_tree().create_timer(1.0).timeout
			if not SettingsManager.get_setting("show_steam_restart_warning", true): return
			var popup_scene = load("res://sections/steam_restart_popup.tscn")
			if popup_scene:
				var popup = popup_scene.instantiate()
				var prev_focus = get_viewport().gui_get_focus_owner()
				get_tree().root.add_child(popup)
				popup.popup_closed.connect(func():
					if is_instance_valid(prev_focus):
						prev_focus.grab_focus()
					else:
						home_button.grab_focus()
				)

func _on_settings_changed(key: String, value):
	if key == "play_ui_sounds":
		_apply_ui_sounds_setting(value)

func _on_online_status_changed(is_online: bool):
	var indicator = top_button_bar.get_node_or_null("OfflineIndicator")
	if is_instance_valid(indicator):
		indicator.visible = not is_online

func _apply_ui_sounds_setting(play: bool):
	var vol = 0.0 if play else -80.0
	var players = [
		get_node_or_null("FocusSoundPlayer"),
		get_node_or_null("SelectSoundPlayer"),
		get_node_or_null("BackSoundPlayer"),
		get_node_or_null("ButtonSoundPlayer"),
		get_node_or_null("ZoomSoundPlayer"),
		get_node_or_null("SwitchSoundPlayer")
	]
	for p in players:
		if is_instance_valid(p):
			p.volume_db = vol


func _apply_glyph_feedback(is_pressed: bool, direction: int):
	var target_index = _current_section_index + direction
	if target_index < 0: target_index = _sections.size() - 1
	if target_index >= _sections.size(): target_index = 0
	
	var button_name = _sections[target_index].button_node_name
	var btn = top_button_bar.get_node_or_null(button_name) as Button
	
	if is_instance_valid(btn):
		var target_mod = Color(1.5, 1.5, 1.5, 1.0) if is_pressed else Color(1, 1, 1, 1)
		var target_scale = Vector2(1.05, 1.05) if is_pressed else Vector2(1.0, 1.0)
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "modulate", target_mod, 0.1)
		tween.tween_property(btn, "scale", target_scale, 0.1)
		btn.pivot_offset = btn.size / 2.0

func _on_focus_changed(control: Control):
	if is_instance_valid(_current_connected_item):
		if _current_connected_item.has_signal("status_changed"):
			if _current_connected_item.status_changed.is_connected(_update_footer_prompts):
				_current_connected_item.status_changed.disconnect(_update_footer_prompts)
		if _current_connected_item is Button:
			if _current_connected_item.pressed.is_connected(_update_footer_prompts):
				_current_connected_item.pressed.disconnect(_update_footer_prompts)
	
	_current_connected_item = control
	
	if is_instance_valid(_current_connected_item):
		if _current_connected_item.has_signal("status_changed"):
			_current_connected_item.status_changed.connect(_update_footer_prompts)
		
		if _current_connected_item is Button:
			_current_connected_item.pressed.connect(_update_footer_prompts)

	_update_footer_prompts()

func _update_footer_prompts():
	if not is_instance_valid(footer_bar): return
	
	await get_tree().process_frame
	
	var actions = []
	var focus_owner = get_viewport().gui_get_focus_owner()
	
	if is_instance_valid(_downloads_flyout_instance) and _downloads_flyout_instance.visible:
		actions = [
			{"button": "A", "label": tr("LBL_APP_DETAILS")},
			{"button": "B", "label": tr("LBL_BACK")}
		]
		footer_bar.set_actions(actions)
		return
		
	if is_instance_valid(details_view) and details_view.visible:
		actions = [{"button": "B", "label": tr("LBL_BACK")}]
		if is_instance_valid(focus_owner) and details_view.is_ancestor_of(focus_owner):
			if focus_owner == details_view.action_button:
				actions.append({"button": "A", "label": focus_owner.text})
			elif focus_owner == details_view.add_to_steam_button:
				actions.append({"button": "A", "label": tr("BTN_ADD_TO_STEAM")})
			elif details_view.screenshot_container.is_ancestor_of(focus_owner):
				actions.append({"button": "A", "label": tr("LBL_ZOOM_SCREENSHOT")})
				if details_view.screenshot_container.get_child_count() > 1:
					actions.append({"button": "L2 / R2", "label": tr("LBL_SWITCH_SCREENSHOT")})
			elif focus_owner == details_view.show_reviews_button:
				actions.append({"button": "A", "label": tr("BTN_SHOW_REVIEWS")})
			else:
				actions.append({"button": "A", "label": tr("LBL_SELECT")})
		else:
			actions.append({"button": "A", "label": tr("LBL_SELECT")})
	elif is_instance_valid(focus_owner):
		if top_button_bar.is_ancestor_of(focus_owner):
			actions = [
				{"button": "A", "label": tr("LBL_SELECT")},
				{"button": "L1 / R1", "label": tr("LBL_SWITCH_TAB")}
			]
			if _current_section_index != 0:
				actions.append({"button": "B", "label": tr("LBL_GO_HOME")})
		else:
			var custom_a = _get_custom_a_action(focus_owner)
			actions.append(custom_a)
			
			actions.append({"button": "B", "label": tr("LBL_BACK_TO_TOP")})
			actions.append({"button": "L1 / R1", "label": tr("LBL_SWITCH_TAB")})
			
			var pagination_prompts = _get_pagination_prompts(focus_owner)
			actions.append_array(pagination_prompts)
	
	actions.append({"button": "View", "label": tr("LBL_MENU")})
	actions.append({"button": "Menu", "label": tr("LBL_SETTINGS_SHORT")})
	
	var dm = get_node_or_null("/root/DownloadManager")
	var has_downloads = false
	if dm and dm.running_tasks.size() > 0:
		has_downloads = true
		actions.append({"button": "Y", "label": str(dm.running_tasks.size()) + " " + tr("LBL_TASKS")})
	else:
		actions.append({"button": "Y", "label": tr("LBL_TASKS")})
	
	footer_bar.set_actions(actions)
	
	if footer_bar.has_method("set_action_pulsing"):
		footer_bar.set_action_pulsing("Y", has_downloads)

func _get_custom_a_action(focus_owner: Control) -> Dictionary:
	var section_name = _sections[_current_section_index].name
	
	var script_path = ""
	if focus_owner.get_script() != null:
		script_path = focus_owner.get_script().get_path()
		
	var is_product_box = (focus_owner is ProductBox)
	var is_installed_item = script_path.contains("installed_app_item.gd")
	var is_update_item = script_path.contains("update_item.gd")
	var is_extension_item = focus_owner.name.contains("ExtensionItem") or (focus_owner.get_parent() and focus_owner.get_parent().name.contains("ExtensionItem"))

	if is_product_box or is_installed_item:
		return {"button": "A", "label": tr("LBL_APP_DETAILS")}
	
	if is_update_item:
		if "is_selected" in focus_owner:
			return {"button": "A", "label": tr("LBL_UNSELECT_APP") if focus_owner.is_selected else tr("LBL_SELECT_APP")}
		return {"button": "A", "label": tr("LBL_SELECT_UNSELECT")}

	var action = {"button": "A", "label": tr("LBL_OPEN")}
	match section_name:
		"Home", "Categories", "Search":
			if focus_owner is LineEdit:
				action["label"] = tr("LBL_START_TYPING")
			elif focus_owner is Button and "SearchButton" in focus_owner.name:
				action["label"] = tr("BTN_SEARCH")
			elif focus_owner is Button and not focus_owner.text.is_empty():
				action["label"] = focus_owner.text
		
		"Updates":
			if focus_owner is Button and not focus_owner.text.is_empty():
				action["label"] = focus_owner.text
		
		"Extensions":
			if is_extension_item:
				action["label"] = tr("LBL_MANAGE_EXTENSION")
			elif focus_owner is Button and not focus_owner.text.is_empty():
				action["label"] = focus_owner.text
		
		"Installed":
			if focus_owner is Button and not focus_owner.text.is_empty():
				action["label"] = focus_owner.text

	return action

func _get_pagination_prompts(focus_owner: Control) -> Array:
	var prompts = []
	var pl: ProductList = null
	
	var current_node = focus_owner
	while is_instance_valid(current_node):
		if current_node is ProductList:
			pl = current_node
			break
		current_node = current_node.get_parent()
	
	if is_instance_valid(pl) and pl.total_pages > 1 and pl.display_mode == pl.DisplayMode.MULTI_LINE_WRAP:
		prompts.append({"button": "L2 / R2", "label": tr("LBL_SWITCH_PAGE")})
			
	return prompts

func is_any_section_typing() -> bool:
	var current_section_node = _sections[_current_section_index].instance
	return is_instance_valid(current_section_node) and current_section_node.has_method("is_typing") and current_section_node.is_typing()

func _input(event: InputEvent):
	if ControllerManager.is_input_blocked():
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			return
	var current_section_node = _sections[_current_section_index].instance
	if is_instance_valid(current_section_node) and current_section_node.has_method("is_typing") and current_section_node.is_typing():
		if event.is_action("ui_cancel") or event.is_action("ui_accept"):
			return

		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			return

func _unhandled_input(event: InputEvent):
	if ControllerManager.is_input_blocked():
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("open_settings"):
		if is_instance_valid(_settings_modal_instance):
			if _settings_modal_instance.visible:
				_settings_modal_instance.close_modal()
			else:
				_settings_modal_instance.open_modal()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("open_app_menu"):
		if is_instance_valid(_app_menu_modal_instance):
			if _app_menu_modal_instance.visible:
				_app_menu_modal_instance.close_modal()
			else:
				_app_menu_modal_instance.open_modal()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("open_downloads"):
		if is_instance_valid(_downloads_flyout_instance):
			if _downloads_flyout_instance.visible:
				_downloads_flyout_instance.close_flyout()
			else:
				_downloads_flyout_instance.open_flyout()
		get_viewport().set_input_as_handled()
		return

	if is_instance_valid(details_view) and details_view.visible:
		if event.is_action_pressed("section_next") or event.is_action_pressed("section_previous"):
			get_viewport().set_input_as_handled()
			return
			
	if is_instance_valid(_downloads_flyout_instance) and _downloads_flyout_instance.visible:
		if event.is_action_pressed("section_next") or event.is_action_pressed("section_previous"):
			get_viewport().set_input_as_handled()
			return

	var new_section_index = _current_section_index
	var switched = false
	if event.is_action_pressed("section_next"):
		new_section_index += 1
		if new_section_index >= _sections.size():
			new_section_index = 0
		switched = true
		
	elif event.is_action_pressed("section_previous"):
		new_section_index -= 1
		if new_section_index < 0:
			new_section_index = _sections.size() - 1
		switched = true
	
	if switched:
		_on_top_bar_button_pressed(new_section_index)
		get_viewport().set_input_as_handled()
		return
			
	var focused_control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focused_control): return

	if top_button_bar.is_ancestor_of(focused_control):
		if event.is_action_pressed("go_back"):
			if _current_section_index != 0:
				_on_top_bar_button_pressed(0)
				get_viewport().set_input_as_handled()
				return

		var action_string = ""
		if event.is_action_pressed("ui_down"): action_string = "ui_down"
		elif event.is_action_pressed("ui_left"): action_string = "ui_left"
		elif event.is_action_pressed("ui_right"): action_string = "ui_right"

		if action_string == "ui_down":
			if is_instance_valid(_current_home_view_instance) and _current_home_view_instance.has_method("focus_first_product_in_popular_list"):
				_current_home_view_instance.focus_first_product_in_popular_list()
			get_viewport().set_input_as_handled()
		elif action_string == "ui_left" or action_string == "ui_right":
			pass
	
func _on_top_bar_button_focus_entered():
	var focus_owner = get_viewport().gui_get_focus_owner()
	print("Main DEBUG: Top Bar Button Focus Entered: ", focus_owner.name if is_instance_valid(focus_owner) else "unknown")
	
	if _suppress_focus_sound or _is_switching_section:
		return

	if is_instance_valid(focus_sound):
		focus_sound.play()

func load_popular_products():
	var home_view_node = _sections[0].instance
	if is_instance_valid(home_view_node) and home_view_node.has_node("ContentScrollContainer/ListMargin/VBoxContainer/PopularProductList"):
		var popular_list = home_view_node.get_node("ContentScrollContainer/ListMargin/VBoxContainer/PopularProductList")
		_load_product_list("https://flathub.org/api/v2/collection/popular?page=1&per_page=10&locale=en", popular_list)
	else:
		printerr("ERROR: Could not find PopularProductList in HomeView instance.")

func load_trending_products():
	var home_view_node = _sections[0].instance
	if is_instance_valid(home_view_node) and home_view_node.has_node("ContentScrollContainer/ListMargin/VBoxContainer/TrendingProductList"):
		var trending_list = home_view_node.get_node("ContentScrollContainer/ListMargin/VBoxContainer/TrendingProductList")
		_load_product_list("https://flathub.org/api/v2/collection/trending?page=1&per_page=10&locale=en", trending_list)
	else:
		printerr("ERROR: Could not find TrendingProductList in HomeView instance.")

func get_image_cache_dir():
	return _image_cache_abs_path

func get_api_cache_dir() -> String:
	return _api_cache_abs_path
	
func is_app_installed(app_id: String) -> bool:
	return _installed_flatpak_ids.has(app_id)

func get_app_scope(app_id: String) -> String:
	if _installed_flatpak_ids.has(app_id):
		return _installed_flatpak_ids[app_id].get("scope", "user")
	return ""

func get_installed_ids() -> Dictionary:
	return _installed_flatpak_ids

func _get_api_cache_filepath(url: String) -> String:
	var hash = url.md5_text() 
	return get_api_cache_dir().path_join(hash + ".json")

func _get_image_cache_filepath(image_url: String, file_extension: String) -> String:
	if _image_cache_abs_path.is_empty():
		printerr("ERROR: _get_image_cache_filepath - Image Cache Path not initialized!")
		return ""
	var url_hash = image_url.md5_text()
	return _image_cache_abs_path.path_join(url_hash + file_extension)
	
func _on_product_list_image_load_requested(url: String, texture_rect: TextureRect):
	if not is_instance_valid(texture_rect):
		printerr("ERROR: Image request for invalid texture_rect, URL: ", url)
		return
	if url.is_empty():
		printerr("ERROR: Empty image URL provided.")
		return

	var url_hash = url.md5_text()
	var cache_filepath_png = _get_image_cache_filepath(url, ".png")
	var cache_filepath_webp = _get_image_cache_filepath(url, ".webp")

	var cache_filepath_to_load = ""
	var file_extension = ""

	if FileAccess.file_exists(cache_filepath_png):
		cache_filepath_to_load = cache_filepath_png
		file_extension = ".png"
	elif FileAccess.file_exists(cache_filepath_webp):
		cache_filepath_to_load = cache_filepath_webp
		file_extension = ".webp"

	if not cache_filepath_to_load.is_empty():
		var modification_time = FileAccess.get_modified_time(cache_filepath_to_load)
		var current_time = Time.get_unix_time_from_system()
		var cache_age = current_time - modification_time

		if cache_age < IMAGE_CACHE_DURATION_SEC:
			var file = FileAccess.open(cache_filepath_to_load, FileAccess.READ)
			if file:
				var file_size = file.get_length()
				if file_size > 0:
					var buffer = file.get_buffer(file_size)
					file.close()

					var image = Image.new()
					var error = ERR_CANT_OPEN

					if file_extension == ".png":
						error = image.load_png_from_buffer(buffer)
					elif file_extension == ".webp":
						error = image.load_webp_from_buffer(buffer)

					if error == OK:
						var texture = ImageTexture.create_from_image(image)
						texture_rect.texture = texture
						return
					else:
						printerr("ERROR: Failed to load image from cache buffer: ", cache_filepath_to_load, ", Error: ", error)
						DirAccess.remove_absolute(cache_filepath_to_load)
				else:
					printerr("ERROR: Cache file is empty: ", cache_filepath_to_load)
					file.close()
					DirAccess.remove_absolute(cache_filepath_to_load)
			else:
				printerr("ERROR: Could not open cache file for reading: ", cache_filepath_to_load, " Error code: ", FileAccess.get_open_error())
		else:
			DirAccess.remove_absolute(cache_filepath_to_load)

	var http_request_image = HTTPRequest.new()
	add_child(http_request_image)
	http_request_image.request_completed.connect(
		_on_image_request_completed.bind(texture_rect, url, http_request_image)
	)

	var error = http_request_image.request(url)
	if error != OK:
		printerr("ERROR: Starting image request failed for %s: %s" % [url, error])
		if is_instance_valid(http_request_image):
			http_request_image.queue_free()

		
func _on_product_list_focus_exited_up():
	var current_section = _sections[_current_section_index]
	var button_node = top_button_bar.get_node_or_null(current_section.button_node_name) as Button
	
	if is_instance_valid(button_node):
		print("Main: Received focus_exited_up, focusing current section button: ", button_node.name)
		button_node.grab_focus()

		if is_instance_valid(_current_home_view_instance) and \
			_current_home_view_instance.name == "HomeView" and \
			_current_home_view_instance.has_method("scroll_to_top"):
			
			_current_home_view_instance.scroll_to_top()
		else:
			if is_instance_valid(global_scroll_container):
				global_scroll_container.scroll_vertical = 0
				print("Main: Reset global scroll position to top (fallback).") 
			

func _on_move_to_details_view(app_id: String, installed: bool, app_name: String = ""):
	var focused_control = get_viewport().gui_get_focus_owner()
	_last_focused_product_box = null

	if is_instance_valid(focused_control):
		var current_section_node = _sections[_current_section_index].instance
		if is_instance_valid(current_section_node) and current_section_node.is_ancestor_of(focused_control):
			var candidate = focused_control
			while is_instance_valid(candidate):
				if candidate is ProductBox:
					_last_focused_product_box = candidate
					print("INFO Main: Stored last focused ProductBox: ", candidate.name if "name" in candidate else "Unnamed ProductBox")
					break
				
				var parent = candidate.get_parent()
				if not is_instance_valid(parent) or parent == current_section_node:
					if _last_focused_product_box == null:
						print("WARN Main: Focused control was not a ProductBox or child of one. Storing direct focused_control for fallback: ", focused_control)
						_last_focused_product_box = focused_control
					break 
				candidate = parent
	
	if not is_instance_valid(_last_focused_product_box):
		print("INFO Main: Could not determine a specific control to re-focus within the current section.")

	details_view.set_initial_state(app_id, installed, app_name)
	details_view.load_details()
	if is_instance_valid(select_sound): select_sound.play()
	
	var tween = create_tween()
	var main_view_height = main_view.size.y
	var target_y_main_out = -main_view_height
	
	tween.tween_property(main_view, "position:y", target_y_main_out, transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	main_view.visible = false

	details_view.position.y = 0
	details_view.visible = true
	details_view.set_initial_focus()
		
func _on_move_back_to_main_view():
	back_sound.play()
	var tween = create_tween()
	var main_view_height = main_view.size.y
	print("Main view height back: ", main_view_height)
	var target_y = 0
	tween.tween_property(main_view, "position:y", target_y, transition_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	details_view.visible = false
	main_view.visible = true
	await tween.finished
	details_view.clear_data()
	
	if is_instance_valid(_last_focused_product_box) and _last_focused_product_box.is_inside_tree():
		_last_focused_product_box.grab_focus()
		print("INFO Main: Restored focus to: ", _last_focused_product_box.name if _last_focused_product_box and "name" in _last_focused_product_box else "unnamed or null")
	else:
		print("INFO Main: _last_focused_product_box is invalid or not in tree. Focusing default.")
		var current_section_instance = _sections[_current_section_index].instance
		if is_instance_valid(current_section_instance) and current_section_instance.has_method("focus_default_element"):
			current_section_instance.focus_default_element()
		elif is_instance_valid(home_button):
			home_button.grab_focus()
	_last_focused_product_box = null 

func _on_image_request_completed(result, response_code, headers, body: PackedByteArray, texture_rect: TextureRect, image_url: String, http_request_node: HTTPRequest):
	if not is_instance_valid(texture_rect):
		printerr("ERROR: TextureRect invalid in image callback for URL: ", image_url)
		if is_instance_valid(http_request_node): http_request_node.queue_free()
		return

	if response_code == 200 and result == HTTPRequest.RESULT_SUCCESS:
		var image = Image.new()
		var error = ERR_FILE_UNRECOGNIZED
		var content_type = ""
		var file_extension = ""

		for header in headers:
			if header.findn("Content-Type:") == 0:
				content_type = header.get_slice(":", 1).strip_edges().to_lower()
				break

		if content_type == "image/png":
			error = image.load_png_from_buffer(body)
			file_extension = ".png"
		elif content_type == "image/webp":
			error = image.load_webp_from_buffer(body)
			file_extension = ".webp"
		else:
			printerr("ERROR: Unknown or unsupported image type '%s' for URL: %s" % [content_type, image_url])
			error = ERR_FILE_UNRECOGNIZED

		if error == OK:
			var texture = ImageTexture.create_from_image(image)
			texture_rect.texture = texture

			if not file_extension.is_empty():
				var url_hash = image_url.md5_text()
				var cache_filepath = _get_image_cache_filepath(image_url, file_extension)
				if not cache_filepath.is_empty():
					var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
				var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
				var open_error = FileAccess.get_open_error()
				if open_error == OK:
					file.store_buffer(body)
					file.close()
				else:
					printerr("ERROR: Could not open cache file for writing: ", cache_filepath, " Code: ", open_error)
					if is_instance_valid(file): file.close()
		else:
			printerr("ERROR: Failed loading image buffer. Type: '%s', Error: %s, URL: %s" % [content_type, error, image_url])
	else:
		printerr("ERROR: HTTP Error %d (Result %d) downloading image: %s" % [response_code, result, image_url])

	if is_instance_valid(http_request_node):
		http_request_node.queue_free()
				


func _load_product_list(url: String, target_list: ProductList):
	if not is_instance_valid(target_list):
		printerr("ERROR Invalid target list, URL: ", url)
		return

	if url.begins_with("https://flathub.org/api/v2/search"):
		_perform_search_post(url, target_list)
		return

	var cache_filepath = _get_api_cache_filepath(url)
	if FileAccess.file_exists(cache_filepath):
		print("-> Cache-Datei gefunden: ", cache_filepath.get_file())
		var file = FileAccess.open(cache_filepath, FileAccess.READ)
		var open_error = FileAccess.get_open_error()

		if open_error == OK:
			var json_string = file.get_as_text()
			file.close()
			var cache_content = JSON.parse_string(json_string)

			if cache_content is Dictionary:
				var timestamp = cache_content.get("timestamp", 0) 
				var api_data = cache_content.get("api_data")
				var current_time = Time.get_unix_time_from_system() 
				var cache_age = current_time - timestamp

				if cache_age < CACHE_DURATION_SEC and api_data != null:
					print("--> Cache HIT for %s (Age: %d sec)" % [target_list.title, cache_age])
					_process_product_list_data(api_data, target_list, url)
					return
				else:
					print("--> Cache EXPIRED or invalid for %s (Age: %d sec)" % [target_list.title, cache_age])
					DirAccess.remove_absolute(cache_filepath)
			else:
				print("--> Cache-File corrupt (No Dictionary) for %s: %s" % [target_list.title, cache_filepath.get_file()])
				DirAccess.remove_absolute(cache_filepath)
		else:
			printerr("--> Error opening cahce file %s: %s" % [cache_filepath.get_file(), open_error])
			if is_instance_valid(file): file.close()
	else:
		print("-> Cache MISS for  %s" % target_list.title)

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(
		_on_product_list_request_completed.bind(http_request, url, target_list)
	)	
	var error = http_request.request(url)
	if error != OK:
		printerr("Error starting request for '%s' (%s): %s" % [target_list.title, url, error])
		if is_instance_valid(http_request): http_request.queue_free()

func _perform_search_post(url: String, target_list: ProductList):
	print("DEBUG: Performing POST search for URL: ", url)
	
	var query_string = ""
	var page = 1
	var per_page = 24
	
	var parts = url.split("?")
	if parts.size() > 1:
		var params = parts[1].split("&")
		for p in params:
			var kv = p.split("=")
			if kv.size() == 2:
				var key = kv[0]
				var val = kv[1].uri_decode()
				match key:
					"q", "query": query_string = val
					"page": page = int(val)
					"per_page": per_page = int(val)
	
	if query_string.is_empty():
		printerr("ERROR: No query found in search URL: ", url)
		return

	var api_url = "https://flathub.org/api/v2/search"
	var headers = ["Content-Type: application/json"]
	var body_data = {
		"query": query_string,
		"page": page,
		"per_page": per_page
	}
	var body_json = JSON.stringify(body_data)
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(
		_on_search_request_completed.bind(http_request, url, target_list)
	)
	
	print("DEBUG: Sending POST to ", api_url, " with body: ", body_json)
	var error = http_request.request(api_url, headers, HTTPClient.METHOD_POST, body_json)
	if error != OK:
		printerr("Error starting SEARCH request: ", error)
		http_request.queue_free()

func _on_search_request_completed(result, response_code, headers, body, http_request_list: HTTPRequest, url: String, target_list: ProductList):
	if not is_instance_valid(target_list):
		if is_instance_valid(http_request_list): http_request_list.queue_free()
		return
		
	if response_code == 200:
		var response_string = body.get_string_from_utf8()
		var api_json = JSON.parse_string(response_string)
		
		if api_json != null:
			_process_product_list_data(api_json, target_list, url)
		else:
			printerr("JSON parse error for Search Response.")
	else:
		printerr("HTTP Error %d while searching." % response_code)
		if body.size() > 0:
			print("Response Body: ", body.get_string_from_utf8())

	if is_instance_valid(http_request_list):
		http_request_list.queue_free()

func _on_product_list_request_completed(result, response_code, headers, body, http_request_list: HTTPRequest, url: String, target_list: ProductList):
	if not is_instance_valid(target_list):
		printerr("Ziel-ProductList ungültig im Callback für URL: ", url)
		if is_instance_valid(http_request_list): http_request_list.queue_free(); return

	if response_code == 200:
		var response_string = body.get_string_from_utf8()
		var api_json = JSON.parse_string(response_string)

		if api_json != null:
			var data_to_cache = {
				"timestamp": Time.get_unix_time_from_system(),
				"api_data": api_json
			}
			var json_string_to_cache = JSON.stringify(data_to_cache, "  ")
			var cache_filepath = _get_api_cache_filepath(url)

			var file = FileAccess.open(cache_filepath, FileAccess.WRITE)
			var open_error = FileAccess.get_open_error()
			if open_error == OK:
				file.store_string(json_string_to_cache)
				file.close()
				print("-> Data for  '%s' saved in cache file: %s" % [url.get_file(), cache_filepath.get_file()])
			else:
				printerr("--> Error writing cache file %s: %s" % [cache_filepath.get_file(), open_error])
				if is_instance_valid(file): file.close()

			_process_product_list_data(api_json, target_list, url)
		else:
			printerr("JSON parse error for URL '%s'." % url)
	else:
		printerr("HTTP Error %d while requesting from '%s'." % [response_code, url])

	if is_instance_valid(http_request_list):
		http_request_list.queue_free()
		
func _process_product_list_data(json_data, target_list: ProductList, url: String):
	print("DEBUG Process product list data of url: ", url)
	if not is_instance_valid(target_list): printerr("Invalid target list in _process_product_list_data"); return
	if json_data is Dictionary and json_data.has('hits') and json_data['hits'] is Array:
		target_list.set_url(url)
		target_list.set_products(json_data['hits'])
		target_list.set_pagination_data(int(json_data['hitsPerPage']), int(json_data['page']), int(json_data['totalPages']))
		print("Productlist '%s' updated." % target_list.title)
	else: printerr("Unexpected data structure for list '%s'." % target_list.title)


func _check_connected_controllers():
	var connected_joypads = Input.get_connected_joypads()
	if connected_joypads.size() > 0:
		print("Controllers at start:")
		for device_id in connected_joypads: print("  Device ID: ", device_id, ", Name: ", Input.get_joy_name(device_id))
	else: print("no controllers detected at start.")

func _on_joy_connection_changed(device_id: int, connected: bool):
	if connected: print("CONTROLLER CONNECTED:\n  Device ID: ", device_id, ", Name: ", Input.get_joy_name(device_id))
	else: print("CONTROLLER DISCONNECTED:\n  Device ID: ", device_id)
	print("-----------------------------------------")

func _ensure_user_remote_exists():
	var check_cmd = "LC_ALL=C flatpak remotes --user --columns=name"
	var output = []
	var exit_code = OS.execute(SystemUtils.get_host_sh_cmd(), SystemUtils.get_host_sh_args(check_cmd), output)
	var out_str = output[0] if output.size() > 0 else ""
	
	var flathub_exists = false
	if exit_code == 0 and out_str.length() > 0:
		for line in out_str.split("\n"):
			if line.strip_edges() == "flathub":
				flathub_exists = true
				break
	
	if not flathub_exists:
		print("INFO: Flathub user-remote missing. Attempting to add it...")
		var add_cmd = "LC_ALL=C flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
		var output_add = []
		var exit_code_add = OS.execute(SystemUtils.get_host_sh_cmd(), SystemUtils.get_host_sh_args(add_cmd), output_add)
		if exit_code_add == 0:
			print("INFO: Successfully added flathub user-remote.")
		else:
			printerr("ERROR: Failed to add flathub user-remote. Exit code: ", exit_code_add)
	else:
		print("INFO: Flathub user-remote already exists.")


func _fetch_installed_apps():
	if _flatpak_thread != null:
		if _flatpak_thread.is_alive():
			return
		elif _flatpak_thread.is_started():
			_flatpak_thread.wait_to_finish()
		_flatpak_thread = null

	print("INFO: Start Thread for fetching installed flatpaks...")
	_flatpak_thread = Thread.new()
	var callable = Callable(self, "_execute_flatpak_in_thread")
	var err = _flatpak_thread.start(callable)
	if err != OK:
		printerr("ERROR: Could not start flatpak thread! Code: ", err)
		_flatpak_thread = null


func _execute_flatpak_in_thread():
	var host_command = "LC_ALL=C flatpak list --app --columns=application,name,size,installation"
	
	var run_cmd = SystemUtils.get_host_sh_cmd()
	var spawn_args = SystemUtils.get_host_sh_args(host_command)
	var output_array = []

	print("INFO: Thread: Execute '%s %s' ..." % [run_cmd, " ".join(spawn_args)])

	var exit_code = OS.execute(run_cmd, spawn_args, output_array)


	var output_string = ""
	if output_array.size() > 0:
		output_string = output_array[0]

	Callable(self, "_process_flatpak_result").call_deferred(output_string, exit_code)

func get_cached_image_path(image_url: String) -> String:
	if image_url.is_empty():
		return ""

	var url_hash = image_url.md5_text()
	var path_png = _get_image_cache_filepath(image_url, ".png")
	var path_webp = _get_image_cache_filepath(image_url, ".webp")

	if FileAccess.file_exists(path_png):
		return path_png
	elif FileAccess.file_exists(path_webp):
		print("WARN: Found cached image as WebP, Python Pillow needs libwebp support: ", path_webp)
		return path_webp
	else:
		print("DEBUG Main: Image not found in cache for URL: ", image_url)
		return ""

func _process_flatpak_result(output: String, exit_code: int):
	print("INFO: Process flatpak result...")
	if exit_code == 0:
		_installed_flatpak_ids.clear() 
		var lines = output.strip_edges().split("\n")
		var count = 0
		for line in lines:
			line = line.strip_edges()
			if line.is_empty(): continue
			
			var parts = line.split("\t")
			if parts.size() >= 4:
				var app_id = parts[0].strip_edges()
				var app_name = parts[1].strip_edges()
				var app_size = parts[2].strip_edges()
				var scope = parts[3].strip_edges()
				
				_installed_flatpak_ids[app_id] = {
					"name": app_name,
					"size": app_size,
					"scope": scope
				}
				count += 1
			else:
				printerr("WARN: Could not parse flatpak line: ", line)
				
		print("INFO: %d installed flatpaks found and processed." % count)
		_update_all_lists_install_status()
		emit_signal("installed_apps_updated")
	else:
		printerr("ERROR: 'flatpak list' failed with code: ", exit_code)
		printerr("Flatpak Output: ", output)

	if _flatpak_thread != null and _flatpak_thread.is_started():
		_flatpak_thread.wait_to_finish()
	_flatpak_thread = null

func _update_all_lists_install_status():
	print("INFO Main: Updating install status in all sections...")
	for section in _sections:
		var current_section_node = section.instance
		if is_instance_valid(current_section_node) and current_section_node.has_method("update_internal_list_install_status"):
			current_section_node.update_internal_list_install_status(_installed_flatpak_ids)
			print("INFO Main: Called update_internal_list_install_status on: ", current_section_node.name)

func _switch_to_section(target_index: int):
	if _is_switching_section: return
	if target_index < 0 or target_index >= _sections.size(): return
	if target_index == _current_section_index and is_instance_valid(_sections[target_index].instance): return

	_is_switching_section = true

	var old_section_index = _current_section_index
	var old_section_instance = _sections[old_section_index].instance
	
	var new_section_instance = _sections[target_index].instance
	
	var direction = 1
	
	if target_index < old_section_index:
		direction = -1
	
	if old_section_index == _sections.size() - 1 and target_index == 0:
		direction = 1
	elif old_section_index == 0 and target_index == _sections.size() - 1:
		direction = -1
	
	var container_width = section_view_container.size.x

	if is_instance_valid(new_section_instance):
		new_section_instance.position.x = container_width * direction
		new_section_instance.visible = true
		if new_section_instance.has_method("on_view_entered"):
			new_section_instance.on_view_entered()
	else:
		printerr("ERROR: New section instance is invalid for index: ", target_index)
		_is_switching_section = false
		return
		
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(new_section_instance, "position:x", 0.0, transition_time_section_change)

	if is_instance_valid(old_section_instance):
		if old_section_instance.has_method("on_view_exiting"):
			old_section_instance.on_view_exiting()
		tween.tween_property(old_section_instance, "position:x", -container_width * direction, transition_time_section_change)
		tween.chain().tween_callback(func(): old_section_instance.visible = false)
	
	_current_section_index = target_index
	
	await tween.finished
	await _update_top_bar_button_focus()
	_is_switching_section = false
	
func _on_top_bar_button_pressed(target_index: int):
	print("Main DEBUG: Top Bar Button Pressed for index: ", target_index, " (", _sections[target_index].name, ")")
	if is_instance_valid(switch_sound) and _is_switching_section == false:
		switch_sound.play()
	_switch_to_section(target_index)

func _connect_section_signals(view_node: Control):
	if not is_instance_valid(view_node): return

	if view_node.has_signal("move_to_details_view_requested"):
		if not view_node.move_to_details_view_requested.is_connected(_on_move_to_details_view):
			view_node.move_to_details_view_requested.connect(_on_move_to_details_view)
			
	if view_node.has_signal("image_load_requested"):
		if not view_node.image_load_requested.is_connected(_on_product_list_image_load_requested):
			view_node.image_load_requested.connect(_on_product_list_image_load_requested)
			
	if view_node.has_signal("focus_exited_up_from_lists"):
		if not view_node.focus_exited_up_from_lists.is_connected(_on_product_list_focus_exited_up):
			view_node.focus_exited_up_from_lists.connect(_on_product_list_focus_exited_up)
			
	if view_node.has_signal("load_new_page_requested"):
		if not view_node.load_new_page_requested.is_connected(_load_product_list):
			view_node.load_new_page_requested.connect(_load_product_list)

func _update_top_bar_button_focus():
	_suppress_focus_sound = true
	
	for i in range(_sections.size()):
		var button_name = _sections[i].button_node_name
		var button_node = top_button_bar.get_node_or_null(button_name) as Button

		if not is_instance_valid(button_node):
			continue

		if i == _current_section_index:
			button_node.grab_focus()
			button_node.set_pressed_no_signal(true)
		else:
			button_node.set_pressed_no_signal(false)
			
	await get_tree().process_frame
	_suppress_focus_sound = false
			
func refresh_installed_apps_list():
	print("INFO Main: Refreshing installed apps list due to recent install/uninstall.")
	_fetch_installed_apps()

func _on_download_task_updated(operation_id: String, status_data: Dictionary):
	_update_footer_prompts()

func _on_download_task_finished(operation_id: String, final_status: String, op_type: String):
	_update_footer_prompts()
	var success = (final_status == "completed")
	var msg = operation_id
	var app_name = operation_id
	
	var dm = get_node_or_null("/root/DownloadManager")
	if dm and dm.running_tasks.has(operation_id):
		app_name = dm.running_tasks[operation_id].status_data.get("name", operation_id)
		
	var msg_key = ""
	if success:
		if op_type == "install": msg_key = "MSG_SUCCESS_INSTALL"
		elif op_type == "uninstall": msg_key = "MSG_SUCCESS_UNINSTALL"
		elif op_type == "update": msg_key = "MSG_SUCCESS_UPDATE"
		else: msg_key = "MSG_SUCCESS_PROCESS"
	else:
		if op_type == "install": msg_key = "MSG_FAIL_INSTALL"
		elif op_type == "uninstall": msg_key = "MSG_FAIL_UNINSTALL"
		elif op_type == "update": msg_key = "MSG_FAIL_UPDATE"
		else: msg_key = "MSG_FAIL_PROCESS"
	
	msg = tr(msg_key) % app_name
	_show_toast(msg, success)

func _show_toast(message: String, success: bool = true):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.6, 0.2, 0.9) if success else Color(0.8, 0.2, 0.2, 0.9)
	style.set_corner_radius_all(8)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	
	var lbl = Label.new()
	lbl.text = message
	lbl.add_theme_font_size_override("font_size", 16)
	panel.add_child(lbl)
	
	toast_container.add_child(panel)
	
	panel.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(3.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(panel.queue_free)
