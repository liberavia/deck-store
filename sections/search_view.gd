extends Control

# --- Signals (Required by Main) ---
signal move_to_details_view_requested(app_id: String, installed: bool)
signal image_load_requested(url: String, texture_rect: TextureRect)
signal focus_exited_up_from_lists()
signal load_new_page_requested(url: String, target_list: ProductList)

# --- UI Nodes ---
@onready var search_input: LineEdit = $VBoxContainer/TopBar/SearchInput
@onready var search_button: Button = $VBoxContainer/TopBar/SearchButton
@onready var product_list: ProductList = $VBoxContainer/ProductList

# --- Internal State ---
var _focus_sound_player: AudioStreamPlayer
var _select_sound_player: AudioStreamPlayer
var _typing_active: bool = false

func _ready():
	_setup_audio()
	_setup_connections()
	
	# Initial state
	if is_instance_valid(product_list):
		product_list.title = "" # Start empty or with instructions

func _setup_audio():
	_focus_sound_player = AudioStreamPlayer.new()
	_focus_sound_player.stream = load("res://assets/change.mp3")
	_focus_sound_player.bus = "Master"
	add_child(_focus_sound_player)
	
	_select_sound_player = AudioStreamPlayer.new()
	_select_sound_player.stream = load("res://assets/nextprev.wav")
	_select_sound_player.bus = "Master"
	add_child(_select_sound_player)

func _setup_connections():
	# Search Input
	if is_instance_valid(search_input):
		# Disable default handling to avoid conflicts
		search_input.virtual_keyboard_enabled = false
		
		search_input.text_submitted.connect(_on_search_submitted)
		search_input.focus_entered.connect(_on_search_input_focus_entered)
		# We removed focus_exited to prevent hiding keyboard when focus momentarily shifts to overlay
	
	if is_instance_valid(search_button):
		search_button.pressed.connect(func(): _on_search_submitted(search_input.text))

	# Product List
	if is_instance_valid(product_list):
		product_list.move_to_details_view.connect(func(id, installed): emit_signal("move_to_details_view_requested", id, installed))
		product_list.image_load_requested.connect(func(url, rect): emit_signal("image_load_requested", url, rect))
		product_list.focus_exited_up.connect(func(): emit_signal("focus_exited_up_from_lists"))
		product_list.load_new_page.connect(func(url, list): emit_signal("load_new_page_requested", url, list))

# --- Logic ---

func _on_search_input_focus_entered():
	# Do NOT automatically enter typing mode (blocking navigation) on focus.
	# Wait for explicit user activation (e.g. pressing 'A').
	# Just show keyboard as a hint if supported, but don't lock UI.
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
		# Simplest is to remove the specific overrides we added
		search_input.remove_theme_stylebox_override("normal")
		search_input.remove_theme_stylebox_override("focus")

func _set_typing_active(active: bool):
	if _typing_active != active:
		_typing_active = active
		_update_typing_visuals()
		if _typing_active:
			_show_virtual_keyboard()

func _show_virtual_keyboard():
	print("SearchView: Requesting Virtual Keyboard...")
	DisplayServer.virtual_keyboard_show(search_input.text)

func _input(event: InputEvent):
	if not is_visible_in_tree():
		return

	# --- Manual Trigger Detection (Steam + Back) ---
	# Button 4 is usually Back/Select. Button 5/Guide might not be caught here if OS swallows it, 
	# but we check if it is pressed.
	# Note: On Steam Deck, Guide+Back is a system shortcut. If it reaches us, we use it.
	if event is InputEventJoypadButton and event.pressed:
		# Check for Back button (usually index 4 or 6) + Guide held
		# Godot 4: JOY_BUTTON_BACK=4, JOY_BUTTON_GUIDE=16. 
		# But logs showed Button 5 as Guide? That's confusing. Let's trust standard constants first.
		if event.button_index == JOY_BUTTON_BACK:
			# Check if Guide is held (Input singleton checks physical state)
			if Input.is_joy_button_pressed(event.device, JOY_BUTTON_GUIDE):
				print("SearchView: Manual Keyboard Trigger Detected (Guide+Back)")
				_set_typing_active(true)
				get_viewport().set_input_as_handled()
				return

	# --- Fix for Double Input & Background Navigation ---
	
	# Case 1: NOT Typing yet, but focused.
	# User can navigate away (Down) or Start Typing (A).
	if not _typing_active and search_input.has_focus():
		if event.is_action_pressed("ui_accept"):
			print("SearchView: Starting Typing Mode (A pressed)")
			_set_typing_active(true)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("ui_cancel"):
			print("SearchView: Leaving Search Input (B pressed)")
			search_input.release_focus()
			get_viewport().set_input_as_handled()
			return
			
	# Case 2: Typing Mode Active (Keyboard assumed open).
	# We block navigation to prevent "double input".
	if _typing_active:
		# Debug: Print what we are seeing
		if event.is_pressed():
			print("SearchView Input Debug: ", event.as_text())

		# 1. Allow exiting typing mode
		if event.is_action_pressed("ui_cancel"):
			print("SearchView: Exiting typing mode via ui_cancel")
			_set_typing_active(false)
			# Do NOT release focus here. We want to stay focused on the input box
			# so the user can navigate downwards to the list.
			# search_input.release_focus() 
			if _select_sound_player: _select_sound_player.play()
			get_viewport().set_input_as_handled()
			return

		# 2. Block ALL navigation actions to prevent background focus changes
		# Note: We removed ui_accept/ui_select from here to allow Keyboard ENTER to submit search.
		# Controller 'A' (ui_accept) is blocked by the JoypadButton check below.
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or \
		   event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or \
		   event.is_action_pressed("ui_page_up") or event.is_action_pressed("ui_page_down") or \
		   event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
			
			print("SearchView: Blocking navigation input during typing: ", event.as_text())
			get_viewport().set_input_as_handled()
			return

		# 3. Block raw Joypad inputs
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
			return
			
		# 4. Text Recovery (if focus lost)
		if event is InputEventKey and event.pressed:
			# Handle Enter key explicitly if focus is lost (overlay prevents signal emission)
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				print("SearchView: Enter detected during typing (Manual Submit)")
				_on_search_submitted(search_input.text)
				get_viewport().set_input_as_handled()
				return

			# If we receive a key press and it's a printable character
			if event.unicode != 0:
				if not search_input.has_focus():
					print("SearchView: Recovering focus for SearchInput and appending: ", event.as_text())
					search_input.grab_focus()
					var char = char(event.unicode)
					search_input.text += char
					search_input.caret_column = search_input.text.length()
					get_viewport().set_input_as_handled()
			
			# Allow Backspace
			elif event.keycode == KEY_BACKSPACE:
				if not search_input.has_focus():
					search_input.grab_focus()
					var t = search_input.text
					if t.length() > 0:
						search_input.text = t.substr(0, t.length() - 1)
						search_input.caret_column = search_input.text.length()
					get_viewport().set_input_as_handled()

# Removed _unhandled_input as logic moved to _input
# func _unhandled_input(event: InputEvent): ... deleted

func _on_search_submitted(text: String):
	_set_typing_active(false)
	if text.strip_edges().is_empty():
		return
	
	if _select_sound_player:
		_select_sound_player.play()
		
	# search_input.release_focus() # Keep focus on input
	DisplayServer.virtual_keyboard_hide()
	
	_perform_search(text)

func _perform_search(query: String):
	if not is_instance_valid(product_list): return
	
	print("SearchView: Searching for: ", query)
	product_list.show_loading()
	product_list.title = "Results for '" + query + "'"
	
	# Construct Flathub Search URL
	# We use a "fake" GET URL with query parameters that main.gd will intercept and convert to a POST request
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
	focus_default_element()

func on_view_exiting():
	_set_typing_active(false)
