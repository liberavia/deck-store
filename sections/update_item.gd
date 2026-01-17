extends Button

signal selection_toggled(app_id: String, selected: bool)
signal image_load_requested(url: String, texture_rect: TextureRect)

@onready var checkbox: CheckBox = $MarginContainer/HBoxContainer/CheckBox
@onready var icon_rect: TextureRect = $MarginContainer/HBoxContainer/IconRect
@onready var name_label: Label = $MarginContainer/HBoxContainer/InfoContainer/NameLabel
@onready var version_label: Label = $MarginContainer/HBoxContainer/InfoContainer/VersionLabel
@onready var size_label: Label = $MarginContainer/HBoxContainer/SizeLabel

var app_id: String = ""
var is_selected: bool = false
var audio_player: AudioStreamPlayer
var stream_focus = preload("res://assets/change.mp3")
var stream_select = preload("res://assets/select.mp3")

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
	version_label.text = "%s -> %s" % [p_old_version, p_new_version]
	size_label.text = p_size
	
	if not p_icon_url.is_empty():
		emit_signal("image_load_requested", p_icon_url, icon_rect)

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

func _on_focus_entered():
	if audio_player and stream_focus:
		audio_player.stream = stream_focus
		audio_player.play()
