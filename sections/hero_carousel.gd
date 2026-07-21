extends Control

signal image_load_requested(url: String, texture_rect: TextureRect)
signal move_to_details_view(app_id: String, installed: bool)
signal focus_entered_carousel()

@onready var container = $VBoxContainer/ScrollContainer/MarginContainer/HBoxContainer
@onready var scroll = $VBoxContainer/ScrollContainer

var apps: Array = []
var active_requests := 0
var _focus_sound_player: AudioStreamPlayer

func _ready():
	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	_load_json()
	_fetch_apps_data()

func _load_json():
	var file_path = "res://must_haves.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var content = file.get_as_text()
		var json = JSON.new()
		if json.parse(content) == OK:
			var data = json.get_data()
			if data is Dictionary and data.has("must_have_apps"):
				apps = data["must_have_apps"]

func _fetch_apps_data():
	for app_id in apps:
		var url = "https://flathub.org/api/v2/appstream/" + app_id + "?locale=en"
		var http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(self._on_request_completed.bind(http, app_id))
		http.request(url)
		active_requests += 1

func _on_request_completed(result, response_code, headers, body, http_node, app_id):
	http_node.queue_free()
	active_requests -= 1
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var app_data = json.get_data()
			_create_card(app_id, app_data)

func _create_card(app_id: String, app_data: Dictionary):
	var name = app_data.get("name", "Unknown")
	var icon = app_data.get("icon", "")
	var summary = app_data.get("summary", "")
	
	var card = Button.new()
	card.custom_minimum_size = Vector2(400, 200)
	card.focus_mode = Control.FOCUS_ALL
	card.pivot_offset = Vector2(200, 100)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0, 0, 0, 0.45)
	style_normal.border_width_left = 1
	style_normal.border_width_top = 1
	style_normal.border_width_right = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.638, 0.480, 0.698, 1)

	var style_focus = style_normal.duplicate()
	style_focus.border_color = Color.PURPLE
	style_focus.border_width_left = 3
	style_focus.border_width_top = 3
	style_focus.border_width_right = 3
	style_focus.border_width_bottom = 3

	card.add_theme_stylebox_override("normal", style_normal)
	card.add_theme_stylebox_override("focus", style_focus)
	card.add_theme_stylebox_override("hover", style_focus)
	card.add_theme_stylebox_override("pressed", style_focus)
	
	card.focus_entered.connect(func():
		var tw = create_tween()
		tw.tween_property(card, "scale", Vector2(1.05, 1.05), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if is_instance_valid(_focus_sound_player) and SettingsManager.get_setting("play_ui_sounds", true):
			_focus_sound_player.play()
		if card.get_index() == 0 and is_instance_valid(scroll):
			scroll.scroll_horizontal = 0
		emit_signal("focus_entered_carousel")
	)
	card.focus_exited.connect(func():
		var tw = create_tween()
		tw.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	)
	
	var screenshots = app_data.get("screenshots", [])
	var bg_url = ""
	if screenshots.size() > 0:
		var sizes = screenshots[0].get("sizes", [])
		if sizes.size() > 0:
			bg_url = sizes[0].get("src", "")
	
	var bg_rect = TextureRect.new()
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.show_behind_parent = true
	card.add_child(bg_rect)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(80, 80)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_rect)
	
	var title = Label.new()
	title.text = name
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	
	card.pressed.connect(func(): emit_signal("move_to_details_view", app_id, false))
	card.set_meta("app_id", app_id)
	
	var status_indicator = TextureRect.new()
	status_indicator.texture = load("res://assets/check_green.png")
	status_indicator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status_indicator.layout_mode = 1 # 1 = LAYOUT_MODE_ANCHORS
	status_indicator.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status_indicator.offset_left = -35.0
	status_indicator.offset_right = -10.0
	status_indicator.offset_top = 10.0
	status_indicator.offset_bottom = 35.0
	status_indicator.name = "StatusIndicator"
	
	var main_app_node = get_node_or_null("/root/App")
	if main_app_node and main_app_node.has_method("is_app_installed"):
		status_indicator.visible = main_app_node.is_app_installed(app_id)
	else:
		status_indicator.visible = false
		
	card.add_child(status_indicator)
	container.add_child(card)
	
	if icon != "":
		emit_signal("image_load_requested", icon, icon_rect)
	if bg_url != "":
		emit_signal("image_load_requested", bg_url, bg_rect)

func update_installed_status(installed_ids: Dictionary):
	for card in container.get_children():
		if card is Button and card.has_meta("app_id"):
			var app_id = card.get_meta("app_id")
			var status_indicator = card.get_node_or_null("StatusIndicator")
			if status_indicator:
				status_indicator.visible = installed_ids.has(app_id)
