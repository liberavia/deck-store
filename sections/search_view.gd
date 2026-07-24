extends Control

# --- Signals (Required by Main) ---
signal move_to_details_view_requested(app_id: String, installed: bool)
signal image_load_requested(url: String, texture_rect: TextureRect)
signal focus_exited_up_from_lists()
signal load_new_page_requested(url: String, target_list: ProductList)

# --- UI Nodes ---
@onready var search_input: LineEdit = $VBoxContainer/TopBar/SearchInput
@onready var search_button: Button = $VBoxContainer/TopBar/SearchButton
@onready var product_list: ProductList = $VBoxContainer/ListMargin/ProductList

# --- Internal State ---
var _focus_sound_player: AudioStreamPlayer
var _select_sound_player: AudioStreamPlayer
var _typing_active: bool = false
var _debounce_timer: Timer
var _last_search_query: String = ""
var _post_submit_cooldown_timer: Timer
var _cooldown_active: bool = false

func _ready():
	_setup_audio()
	_setup_connections()
	_setup_debounce_timer()
	_setup_cooldown_timer()
	_setup_styling()
	
	# Initial state
	if is_instance_valid(product_list):
		product_list.title = "" 
		product_list.visible = false
		product_list.use_auto_height = false

func _setup_styling():
	# Define Colors (Matching Main/Section Buttons)
	var purple_main = Color(0.627, 0.125, 0.941, 1.0)
	var purple_bg = Color(0.627, 0.125, 0.941, 0.6)
	var white_border = Color(1.0, 1.0, 1.0, 0.8)
	var dark_bg = Color(0.1, 0.1, 0.1, 0.8)
	
	# Normal Style (White Border, Square Corners)
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = dark_bg
	style_normal.set_border_width_all(2)
	style_normal.border_color = white_border
	# No corner radius for square look
	
	# Add Padding (Content Margin)
	style_normal.content_margin_left = 10
	style_normal.content_margin_right = 10
	style_normal.content_margin_top = 5
	style_normal.content_margin_bottom = 5
	
	# Focus/Pressed Style (Purple Border & Background)
	var style_focus = style_normal.duplicate()
	style_focus.bg_color = purple_bg
	style_focus.border_color = purple_main
	
	if is_instance_valid(search_button):
		search_button.add_theme_stylebox_override("normal", style_normal)
		search_button.add_theme_stylebox_override("hover", style_focus)
		search_button.add_theme_stylebox_override("pressed", style_focus)
		search_button.add_theme_stylebox_override("focus", style_focus)
		search_button.add_theme_font_size_override("font_size", 20)

	if is_instance_valid(search_input):
		search_input.add_theme_stylebox_override("normal", style_normal)
		search_input.add_theme_stylebox_override("focus", style_focus)
		search_input.add_theme_color_override("font_color", Color.WHITE)
		search_input.add_theme_font_size_override("font_size", 22)

func _setup_audio():
	_focus_sound_player = AudioStreamPlayer.new()
	_focus_sound_player.stream = load("res://assets/change.mp3")
	_focus_sound_player.bus = "Master"
	add_child(_focus_sound_player)
	
	_select_sound_player = AudioStreamPlayer.new()
	_select_sound_player.stream = load("res://assets/nextprev.wav")
	_select_sound_player.bus = "Master"
	add_child(_select_sound_player)

func _setup_debounce_timer():
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = 0.8 # 800ms delay
	_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(_debounce_timer)

func _setup_cooldown_timer():
	_post_submit_cooldown_timer = Timer.new()
	_post_submit_cooldown_timer.one_shot = true
	_post_submit_cooldown_timer.wait_time = 0.3 # 300ms block
	_post_submit_cooldown_timer.timeout.connect(func(): _cooldown_active = false)
	add_child(_post_submit_cooldown_timer)

func _reset_debounce_timer():
	if is_instance_valid(_debounce_timer):
		_debounce_timer.start()

func _on_debounce_timeout():
	if not is_instance_valid(search_input): return
	var text = search_input.text.strip_edges()
	
	# Only search if length >= 3 and it's a new query
	if text.length() >= 3 and text != _last_search_query:
		print("SearchView: Live search triggering for: ", text)
		_perform_search(text)
		_last_search_query = text

func _setup_connections():
	# Search Input
	if is_instance_valid(search_input):
		# Disable default handling to avoid conflicts
		search_input.virtual_keyboard_enabled = false
		
		search_input.text_submitted.connect(_on_search_submitted)
		search_input.focus_entered.connect(_on_search_input_focus_entered)
	
	if is_instance_valid(search_button):
		search_button.pressed.connect(func(): _on_search_submitted(search_input.text))
		search_button.mouse_entered.connect(func(): search_button.grab_focus())

	# Product List
	if is_instance_valid(product_list):
		product_list.move_to_details_view.connect(func(id, installed): emit_signal("move_to_details_view_requested", id, installed))
		product_list.image_load_requested.connect(func(url, rect): emit_signal("image_load_requested", url, rect))
		product_list.focus_exited_up.connect(func(): emit_signal("focus_exited_up_from_lists"))
		product_list.load_new_page.connect(func(url, list): emit_signal("load_new_page_requested", url, list))
		product_list.products_loaded.connect(_on_products_loaded)

func _on_products_loaded():
	if is_instance_valid(product_list) and is_visible_in_tree():
		await get_tree().create_timer(0.05).timeout
		if product_list.has_method("has_products") and product_list.has_products():
			product_list.focus_first_product()
		elif is_instance_valid(search_input):
			search_input.grab_focus()

	if Engine.has_singleton("Steam") and Steam.has_signal("floating_gamepad_text_input_dismissed"):
		Steam.floating_gamepad_text_input_dismissed.connect(_on_floating_keyboard_dismissed)

func _on_floating_keyboard_dismissed():
	print("SearchView: Steam floating keyboard dismissed callback received")
	# We exit typing mode and allow inputs to resume natively.
	# But we only do it if typing was actually active.
	if _typing_active:
		_set_typing_active(false)

# --- Logic ---

func _on_search_input_focus_entered():
	if _focus_sound_player:
		_focus_sound_player.play()

func _update_typing_visuals():
	if not is_instance_valid(search_input): return
	
	# We can use theme overrides to change appearance
	if _typing_active:
		# Active Typing: Green Border (or distinct color)
		var style = search_input.get_theme_stylebox("normal").duplicate()
		if style is StyleBoxFlat:
			style.border_color = Color(0, 1, 0, 1) # Green
			style.set_border_width_all(2)
			search_input.add_theme_stylebox_override("normal", style)
			search_input.add_theme_stylebox_override("focus", style) # Keep it green even if focused
	else:
		# Inactive: Revert to default (remove overrides or set back)
		search_input.remove_theme_stylebox_override("normal")
		search_input.remove_theme_stylebox_override("focus")

func _set_typing_active(active: bool):
	if _typing_active != active:
		print("SearchView DEBUG: Typing Mode Changed to: ", active)
		_typing_active = active
		_update_typing_visuals()
		if _typing_active:
			# Ensure we have focus so we don't end up in limbo after typing
			if is_instance_valid(search_input):
				search_input.grab_focus()
			_show_virtual_keyboard()
		else:
			# Stop timer if we leave typing mode
			if is_instance_valid(_debounce_timer): _debounce_timer.stop()
			if Engine.has_singleton("Steam") and Steam.has_method("dismissFloatingGamepadTextInput"):
				Steam.dismissFloatingGamepadTextInput()
			DisplayServer.virtual_keyboard_hide()

func _show_virtual_keyboard():
	print("SearchView: Requesting Virtual Keyboard...")
	if Engine.has_singleton("Steam") and get_node_or_null("/root/SteamIntegration") and get_node("/root/SteamIntegration").is_steam_initialized:
		var rect = search_input.get_global_rect()
		# EFloatingGamepadTextInputMode 0 = ModeSingleLine
		Steam.showFloatingGamepadTextInput(Steam.FLOATING_GAMEPAD_TEXT_INPUT_MODE_SINGLE_LINE, int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y))
	else:
		DisplayServer.virtual_keyboard_show(search_input.text)

func _unhandled_input(event: InputEvent):
	if not is_visible_in_tree():
		return

	# --- Cooldown Block ---
	if _cooldown_active:
		get_viewport().set_input_as_handled()
		return

	# --- Manual Trigger Detection (Steam + Back) ---
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_BACK:
			if Input.is_joy_button_pressed(event.device, JOY_BUTTON_GUIDE):
				print("SearchView: Manual Keyboard Trigger Detected (Guide+Back)")
				_set_typing_active(true)
				get_viewport().set_input_as_handled()
				return

	# User can navigate away (Down) or Start Typing (A).
	if not _typing_active:
		if event.is_action_pressed("go_back"):
			var focus_owner = get_viewport().gui_get_focus_owner()
			if is_instance_valid(focus_owner):
				# If we are in the product list, go back to the search bar
				if product_list.is_ancestor_of(focus_owner):
					focus_default_element() # focus_default_element grabs focus on search_input
					get_viewport().set_input_as_handled()
					return
				
				# If we are already on the search input or button, exit to top bar
				if focus_owner == search_input or focus_owner == search_button:
					emit_signal("focus_exited_up_from_lists")
					get_viewport().set_input_as_handled()
					return

		if search_input.has_focus():
			if event.is_action_pressed("ui_accept"):
				print("SearchView: Starting Typing Mode (A pressed)")
				_set_typing_active(true)
				get_viewport().set_input_as_handled()
				return
			
	# Case 2: Typing Mode Active (Keyboard assumed open).
	if _typing_active:
		# 1. Allow exiting typing mode
		if event.is_action_pressed("ui_cancel"):
			print("SearchView: Exiting typing mode via ui_cancel")
			_set_typing_active(false)
			if _select_sound_player: _select_sound_player.play()
			get_viewport().set_input_as_handled()
			return

		# 1b. Block Section Switching
		if event.is_action_pressed("section_next") or event.is_action_pressed("section_previous"):
			print("SearchView DEBUG: Blocking section switch during typing: ", event.as_text())
			get_viewport().set_input_as_handled()
			return

		# 2. Block ALL navigation actions
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or \
		   event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or \
		   event.is_action_pressed("ui_page_up") or event.is_action_pressed("ui_page_down") or \
		   event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
			get_viewport().set_input_as_handled()
			return

		# 3. Block raw Joypad inputs
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			return
			
		# 4. Text Handling
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_on_search_submitted(search_input.text)
				get_viewport().set_input_as_handled()
				return

			if event.unicode != 0:
				if not search_input.has_focus(): search_input.grab_focus()
				search_input.text += char(event.unicode)
				search_input.caret_column = search_input.text.length()
				_reset_debounce_timer()
				get_viewport().set_input_as_handled()
			
			elif event.keycode == KEY_BACKSPACE:
				if not search_input.has_focus(): search_input.grab_focus()
				var t = search_input.text
				if t.length() > 0:
					search_input.text = t.substr(0, t.length() - 1)
					search_input.caret_column = search_input.text.length()
					_reset_debounce_timer()
				get_viewport().set_input_as_handled()

# We can remove the old _input completely as it's now handled by _unhandled_input
func _input(_event: InputEvent):
	pass

func _on_search_submitted(text: String):
	_set_typing_active(false)
	if text.strip_edges().is_empty():
		return
	
	if _select_sound_player:
		_select_sound_player.play()
	
	# Start cooldown to block lingering joypad inputs (e.g. RT axis)
	_cooldown_active = true
	if is_instance_valid(_post_submit_cooldown_timer):
		_post_submit_cooldown_timer.start()
		
	# search_input.release_focus() # Keep focus on input
	
	_last_search_query = text.strip_edges() # Update last query to prevent re-search if timer was running
	_perform_search(text)

func _perform_search(query: String):
	if not is_instance_valid(product_list): return
	
	print("SearchView: Searching for: ", query)
	product_list.visible = true
	product_list.show_loading()
	product_list.title = "Results for '" + query + "'"
	
	# Construct Flathub Search URL
	var url = "https://flathub.org/api/v2/search?q=%s&page=1&per_page=24" % query.uri_encode()
	
	emit_signal("load_new_page_requested", url, product_list)

# --- Interface for Main ---

func update_internal_list_install_status(installed_ids: Dictionary):
	if is_instance_valid(product_list):
		product_list.update_installed_status(installed_ids)

func focus_default_element():
	if is_instance_valid(search_input):
		search_input.grab_focus()

func on_view_entered():
	pass

func on_view_exiting():
	_set_typing_active(false)

func is_typing() -> bool:
	return _typing_active
