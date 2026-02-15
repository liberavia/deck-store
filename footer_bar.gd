extends PanelContainer

@onready var container: HBoxContainer = %ActionContainer

# Example: [{"button": "A", "label": "Select"}, {"button": "B", "label": "Back"}]
func set_actions(actions: Array):
	# Clear existing children
	for child in container.get_children():
		child.queue_free()
	
	for action in actions:
		var action_node = _create_action_item(action["button"], action["label"])
		container.add_child(action_node)

func _create_action_item(button_text: String, label_text: String) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Add spacing before item (except first one handled by alignment)
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	hbox.add_child(spacer)
	
	# Button Icon (Simulated with a Label in a Panel)
	var btn_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.627, 0.125, 0.941, 1.0) # Purple
	style.set_corner_radius_all(20) # Rounded
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	btn_panel.add_theme_stylebox_override("panel", style)
	
	var btn_label = Label.new()
	btn_label.text = button_text
	btn_label.add_theme_font_size_override("font_size", 18)
	btn_label.add_theme_color_override("font_color", Color.WHITE)
	btn_panel.add_child(btn_label)
	
	# Action Label
	var action_label = Label.new()
	action_label.text = label_text
	action_label.add_theme_font_size_override("font_size", 18)
	
	hbox.add_child(btn_panel)
	hbox.add_child(action_label)
	
	return hbox
