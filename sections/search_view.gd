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
	_typing_active = true
	# Trigger virtual keyboard on Steam Deck / Touch devices
	call_deferred("_show_virtual_keyboard")
	if _focus_sound_player:
		_focus_sound_player.play()

func _show_virtual_keyboard():
	print("SearchView: Requesting Virtual Keyboard...")
	DisplayServer.virtual_keyboard_show(search_input.text)

func _unhandled_input(event: InputEvent):
	if not is_visible_in_tree():
		return

	# --- Fix for Double Input (Controller Pass-through) ---
	# We rely on _typing_active state because actual focus is often lost to the OS keyboard overlay.
	if _typing_active:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			# Allow "B" (ui_cancel) to exit focus mode
			if event.is_action_pressed("ui_cancel"):
				_typing_active = false
				search_input.release_focus()
				if _select_sound_player: _select_sound_player.play()
			
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed:
		print("SearchView Debug: Key pressed: ", event.as_text_key_label())
		
		# If we receive a key press and it's a printable character (length 1),
		# and the search input doesn't have focus, we try to help it.
		if event.unicode != 0 and event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER:
			if not search_input.has_focus():
				print("SearchView: Recovering focus for SearchInput and appending: ", event.as_text())
				search_input.grab_focus()
				# Depending on timing, this specific key might be lost to the LineEdit
				# if it didn't have focus *during* the press.
				# We can manually append it.
				var char = char(event.unicode)
				search_input.text += char
				search_input.caret_column = search_input.text.length()
				get_viewport().set_input_as_handled()
		
		# Allow Backspace even if focus lost
		elif event.keycode == KEY_BACKSPACE:
			if not search_input.has_focus():
				search_input.grab_focus()
				var t = search_input.text
				if t.length() > 0:
					search_input.text = t.substr(0, t.length() - 1)
					search_input.caret_column = search_input.text.length()
				get_viewport().set_input_as_handled()

func _on_search_submitted(text: String):
	_typing_active = false
	if text.strip_edges().is_empty():
		return
	
	if _select_sound_player:
		_select_sound_player.play()
		
	search_input.release_focus() # Hide keyboard
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
	_typing_active = false
