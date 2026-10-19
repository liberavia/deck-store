extends SceneTree

func _init():
	var main_root = self.root
	var vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	main_root.add_child(vp)
	
	var label = Label.new()
	label.text = "DECK STORE"
	label.add_theme_font_size_override("font_size", 120)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0.5, 0.2, 0.8, 1))
	label.add_theme_constant_override("outline_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(label)
	
	await create_timer(0.5).timeout
	
	var img = vp.get_texture().get_image()
	var dest = ProjectSettings.globalize_path("user://logo_1280x720.png")
	img.save_png(dest)
	
	print("Logo saved to: ", dest)
	
	var vp2 = SubViewport.new()
	vp2.size = Vector2i(920, 430)
	vp2.transparent_bg = false
	vp2.render_target_update_mode = SubViewport.UPDATE_ONCE
	main_root.add_child(vp2)
	
	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.1, 0.2, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp2.add_child(bg)
	
	var label2 = Label.new()
	label2.text = "DECK STORE"
	label2.add_theme_font_size_override("font_size", 80)
	label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp2.add_child(label2)
	
	await create_timer(0.5).timeout
	
	var img2 = vp2.get_texture().get_image()
	var dest2 = ProjectSettings.globalize_path("user://header_920x430.png")
	img2.save_png(dest2)
	
	print("Header saved to: ", dest2)
	quit()
