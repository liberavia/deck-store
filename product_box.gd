# product_box.gd
extends Control

@onready var panel: Panel = $Panel
var _original_panel_style: StyleBox
var _focus_sound_player: AudioStreamPlayer # Variable für den Player

func _ready():
	if panel: _original_panel_style = panel.get_theme_stylebox("panel")
	else: printerr("Panel node not found in ProductBox!")

	# Verbinde Signale für VISUELLE Änderungen (Namen angepasst)
	self.focus_entered.connect(_on_focus_entered_visual)
	self.focus_exited.connect(_on_focus_exited_visual)

	# Verbinde Signal für SOUND Änderung (NEU)
	self.focus_entered.connect(_on_focus_entered_sound)

	self.focus_mode = Control.FOCUS_ALL

	# Finde den zentralen AudioStreamPlayer
	# Annahme: main.tscn's root ist "App" und der Player ist ein direktes Kind
	# Passe "/root/App/FocusSoundPlayer" an, falls deine Struktur anders ist!
	_focus_sound_player = get_node_or_null("/root/App/FocusSoundPlayer")
	if not _focus_sound_player:
		printerr("FocusSoundPlayer nicht unter /root/App/FocusSoundPlayer gefunden!")


# --- Handler für visuelle Änderungen ---
func _on_focus_entered_visual():
	if not is_instance_valid(panel): return
	if _original_panel_style is StyleBoxFlat:
		var focused_style = _original_panel_style.duplicate() as StyleBoxFlat
		focused_style.border_color = Color.REBECCA_PURPLE
		focused_style.border_width_top = 3 
		focused_style.border_width_left = 3 
		focused_style.border_width_right = 3 
		focused_style.border_width_bottom = 3 
		panel.add_theme_stylebox_override("panel", focused_style)
	else:
		panel.modulate = Color.REBECCA_PURPLE.lightened(0.6)

func _on_focus_exited_visual():
	if not is_instance_valid(panel): return
	panel.remove_theme_stylebox_override("panel")
	panel.modulate = Color(1, 1, 1) # Modulate zurücksetzen, falls als Fallback genutzt

# --- Handler für Sound bei Fokus (NEU) ---
func _on_focus_entered_sound():
	# Spiele Sound ab, wenn der Player gefunden wurde
	if is_instance_valid(_focus_sound_player):
		# Verhindert, dass der Sound überlappt, wenn der Fokus sehr schnell wechselt
		# (kann man je nach Sound auch weglassen)
		# _focus_sound_player.stop()
		_focus_sound_player.play()
	# else: print("FocusSoundPlayer nicht gefunden, kein Sound.") # Optionales Debugging
