extends CanvasLayer

signal popup_closed

@onready var dont_show_checkbutton: CheckButton = $DependencyPopup/MarginContainer/VBoxContainer/DontShowCheckButton
@onready var confirm_button: Button = $DependencyPopup/MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton

var audio_player: AudioStreamPlayer
var stream_focus = preload("res://assets/change.mp3")
var stream_select = preload("res://assets/nextprev.wav")
var _suppress_focus_sound = true

func _ready():
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	dont_show_checkbutton.button_pressed = SettingsManager.get_setting("show_steam_restart_warning", true)
	
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button.focus_entered.connect(_on_focus_entered)
	dont_show_checkbutton.focus_entered.connect(_on_focus_entered)
	dont_show_checkbutton.toggled.connect(func(toggled_on): 
		_play_select_sound()
		SettingsManager.set_setting("show_steam_restart_warning", toggled_on)
	)

	_suppress_focus_sound = true
	confirm_button.grab_focus()
	await get_tree().process_frame
	_suppress_focus_sound = false

func _on_confirm_pressed():
	_play_select_sound()
	emit_signal("popup_closed")
	queue_free()

func _on_focus_entered():
	if not _suppress_focus_sound and audio_player and stream_focus and SettingsManager.get_setting("play_ui_sounds", true):
		audio_player.stream = stream_focus
		audio_player.play()

func _play_select_sound():
	if audio_player and stream_select and SettingsManager.get_setting("play_ui_sounds", true):
		audio_player.stream = stream_select
		audio_player.play()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("go_back"):
		_on_confirm_pressed()
		get_viewport().set_input_as_handled()
