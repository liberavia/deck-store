# button_home.gd
extends Button

var _original_modulate = Color(1,1,1)
var _focus_sound_player: AudioStreamPlayer # Variable für den Player

func _ready():
	_original_modulate = self.modulate
	# Verbinde Signale für VISUELLE Änderungen
	focus_entered.connect(_on_focus_entered_visual)
	focus_exited.connect(_on_focus_exited_visual)
	# Verbinde Signal für SOUND Änderung (NEU)
	focus_entered.connect(_on_focus_entered_sound)

	# Finde den zentralen AudioStreamPlayer (gleicher Code wie oben)
	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	if not _focus_sound_player:
		printerr("FocusSoundPlayer nicht unter /root/App/FocusSoundPlayer gefunden!")

	if has_focus():
		_on_focus_entered_visual()

# --- Handler für visuelle Änderungen ---
func _on_focus_entered_visual():
	self.modulate = Color(0.9, 0.9, 1.1)

func _on_focus_exited_visual():
	self.modulate = _original_modulate

# --- Handler für Sound bei Fokus (NEU, identisch zu product_box.gd) ---
func _on_focus_entered_sound():
	if is_instance_valid(_focus_sound_player):
		# _focus_sound_player.stop() # Optional
		_focus_sound_player.play()
	# else: print("FocusSoundPlayer nicht gefunden, kein Sound.")
