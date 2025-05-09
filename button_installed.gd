extends Button

var _focus_sound_player: AudioStreamPlayer 

func _ready():
	focus_entered.connect(_on_focus_entered_sound)

	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	if not _focus_sound_player:
		printerr("FocusSoundPlayer not found at /root/App/FocusSoundPlayer!")

func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		_focus_sound_player.play()
