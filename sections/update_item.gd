extends Button

signal selection_toggled(app_id: String, selected: bool)
signal status_changed
signal image_load_requested(url: String, texture_rect: TextureRect)

@onready var checkbox: CheckBox = $MarginContainer/HBoxContainer/CheckBox
@onready var icon_rect: TextureRect = $MarginContainer/HBoxContainer/IconRect
@onready var name_label: Label = $MarginContainer/HBoxContainer/InfoContainer/NameLabel
@onready var version_label: RichTextLabel = $MarginContainer/HBoxContainer/InfoContainer/VersionLabel
@onready var size_label: Label = $MarginContainer/HBoxContainer/SizeLabel
@onready var progress_bar: ProgressBar = $MarginContainer/HBoxContainer/InfoContainer/ProgressBar
@onready var status_label: Label = $MarginContainer/HBoxContainer/InfoContainer/StatusLabel

var app_id: String = ""
var is_selected: bool = false
var audio_player: AudioStreamPlayer
var stream_focus = preload("res://assets/change.mp3")
var stream_select = preload("res://assets/select.mp3")

var pulse_tween: Tween

func _ready():
	toggle_mode = true
	pressed.connect(_on_main_button_pressed)
	checkbox.toggled.connect(_on_checkbox_toggled)
	focus_entered.connect(_on_focus_entered)
	
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)

func setup(p_app_id: String, p_name: String, p_old_version: String, p_new_version: String, p_size: String, p_icon_url: String):
	app_id = p_app_id
	name_label.text = p_name
	version_label.text = tr("LBL_UPDATE_VERSION_FROM_TO") % [p_old_version, p_new_version]
	size_label.text = p_size
	
	if not p_icon_url.is_empty():
		emit_signal("image_load_requested", p_icon_url, icon_rect)
	else:
		_load_icon()

func set_progress(value, message: String = ""):
	if value == null: value = 0.0
	var float_value = float(value)
	
	if not progress_bar.visible: progress_bar.visible = true
	progress_bar.value = float_value
	
	if not message.is_empty():
		if not status_label.visible: status_label.visible = true
		status_label.text = message
	
	# Indeterminate / Pulse mode for finishing installation
	if float_value >= 100.0 and message.begins_with("Installing") or message.begins_with(tr("LBL_INSTALLING").replace("...", "")):
		_start_pulse()
	else:
		_stop_pulse()

func _start_pulse():
	if pulse_tween and pulse_tween.is_valid(): return
	pulse_tween = create_tween().bind_node(progress_bar).set_loops()
	pulse_tween.tween_property(progress_bar, "modulate:a", 0.3, 0.6).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(progress_bar, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

func _stop_pulse():
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
	progress_bar.modulate.a = 1.0

func reset_progress():
	_stop_pulse()
	progress_bar.visible = false
	status_label.visible = false
	progress_bar.value = 0

func set_selected(selected: bool):
	is_selected = selected
	checkbox.set_pressed_no_signal(selected)
	# Optionally update visual style for selection

func _on_main_button_pressed():
	# Toggle checkbox when the whole row is clicked
	checkbox.button_pressed = not checkbox.button_pressed

func _on_checkbox_toggled(toggled_on: bool):
	is_selected = toggled_on
	emit_signal("selection_toggled", app_id, is_selected)
	emit_signal("status_changed")

func _on_focus_entered():
	if audio_player and stream_focus:
		audio_player.stream = stream_focus
		audio_player.play()

func _load_icon():
	# Fetch metadata to get the URL
	var metadata_url = "https://flathub.org/api/v2/appstream/%s" % app_id
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_metadata_received.bind(http))
	var err = http.request(metadata_url)
	if err != OK:
		http.queue_free()

func _on_metadata_received(_result, response_code, _headers, body, http_request):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json is Dictionary:
			var icon_url = ""
			
			if json.has("icon") and json["icon"] is String:
				icon_url = json["icon"]
			elif json.has("icons") and json["icons"] is Array:
				var icons_list = json["icons"]
				for icon_data in icons_list:
					if icon_data is Dictionary and icon_data.has("url"):
						icon_url = icon_data["url"]
						if icon_data.get("width") == 128:
							break 

			if not icon_url.is_empty():
				_fetch_icon_image(icon_url)
	
	http_request.queue_free()

func _fetch_icon_image(url: String):
	emit_signal("image_load_requested", url, icon_rect)
