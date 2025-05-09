extends Window

@onready var zoomed_texture_rect: TextureRect = $Margin/ZoomedTextureRect
@onready var margin_container: MarginContainer = $Margin 
@onready var background_panel: Panel = $Background 

var original_focused_element: Control = null
var active_tween: Tween = null
var _is_hiding: bool = false
var _zoom_sound_player: AudioStreamPlayer

func _ready():
	self.transparent_bg = true
	self.borderless = true
	
	self.close_requested.connect(animate_and_hide) 
	self.about_to_popup.connect(_on_about_to_popup)
	self.visibility_changed.connect(_on_visibility_changed)

func _unhandled_input(event: InputEvent):
	if visible and not _is_hiding and \
	   (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept")):
		animate_and_hide()
		get_viewport().set_input_as_handled()

func set_texture(texture: Texture2D):
	# Diese Funktion bleibt wie in der letzten korrekten Version, sie berechnet self.size
	if zoomed_texture_rect and texture:
		zoomed_texture_rect.custom_minimum_size = Vector2.ZERO 

		zoomed_texture_rect.texture = texture
		var original_texture_size = texture.get_size()
		
		if original_texture_size.x <= 0 or original_texture_size.y <= 0:
			original_texture_size = Vector2(100, 100)

		var main_window_size = get_tree().root.size 
		var mc_margin_left = margin_container.get_theme_constant("margin_left", "MarginContainer")
		var mc_margin_right = margin_container.get_theme_constant("margin_right", "MarginContainer")
		var mc_margin_top = margin_container.get_theme_constant("margin_top", "MarginContainer")
		var mc_margin_bottom = margin_container.get_theme_constant("margin_bottom", "MarginContainer")
		var total_mc_margins_h = mc_margin_left + mc_margin_right
		var total_mc_margins_v = mc_margin_top + mc_margin_bottom

		var max_total_popup_content_width = main_window_size.x * 0.9
		var max_total_popup_content_height = main_window_size.y * 0.9
		
		var max_image_render_width = max_total_popup_content_width - total_mc_margins_h
		var max_image_render_height = max_total_popup_content_height - total_mc_margins_v

		var image_display_size = original_texture_size

		if image_display_size.x > max_image_render_width:
			image_display_size.y = (max_image_render_width / image_display_size.x) * image_display_size.y
			image_display_size.x = max_image_render_width
		
		if image_display_size.y > max_image_render_height:
			image_display_size.x = (max_image_render_height / image_display_size.y) * image_display_size.x
			image_display_size.y = max_image_render_height
			
		image_display_size.x = floor(max(image_display_size.x, 1.0))
		image_display_size.y = floor(max(image_display_size.y, 1.0))

		zoomed_texture_rect.custom_minimum_size = image_display_size
		
		var final_window_width = image_display_size.x + total_mc_margins_h
		var final_window_height = image_display_size.y + total_mc_margins_v
		
		self.size = Vector2i(ceil(final_window_width), ceil(final_window_height))

	elif zoomed_texture_rect: 
		zoomed_texture_rect.texture = null
		zoomed_texture_rect.custom_minimum_size = Vector2.ZERO
	else:
		printerr("ScreenshotZoomPopup: Zoomed TextureRect node ($Margin/ZoomedTextureRect) not found.")

func popup_zoomed_image(texture: Texture2D, focused_element_before_popup: Control):
	set_texture(texture) 
	original_focused_element = focused_element_before_popup

	if active_tween and active_tween.is_valid():
		active_tween.kill()
	_is_hiding = false
	
	popup_centered() 

	margin_container.pivot_offset = margin_container.size / 2.0
	margin_container.scale = Vector2(0.7, 0.7)
	margin_container.modulate.a = 0.0 
	
	if is_instance_valid(background_panel):
		background_panel.modulate.a = 0.0

	active_tween = create_tween() 
	active_tween.set_parallel(true)
	active_tween.tween_property(margin_container, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.tween_property(margin_container, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_LINEAR)
	if is_instance_valid(background_panel):
		active_tween.tween_property(background_panel, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_LINEAR)

func animate_and_hide():
	if not self.visible or _is_hiding:
		return
	_is_hiding = true

	if active_tween and active_tween.is_valid():
		active_tween.kill()

	margin_container.pivot_offset = margin_container.size / 2.0

	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.tween_property(margin_container, "scale", Vector2(0.7, 0.7), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.tween_property(margin_container, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_LINEAR)
	if is_instance_valid(background_panel):
		active_tween.tween_property(background_panel, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_LINEAR)
	
	active_tween.tween_callback(_actually_hide)

func _actually_hide():
	hide() 
	_is_hiding = false

func _on_about_to_popup():
	margin_container.scale = Vector2(1.0, 1.0)
	margin_container.modulate = Color(1,1,1,1)
	if is_instance_valid(background_panel):
		background_panel.modulate = Color(1,1,1,1)
	_is_hiding = false
	
	_zoom_sound_player = get_node_or_null("/root/App/ZoomSoundPlayer")
	if _zoom_sound_player:
		_zoom_sound_player.play()

func _on_visibility_changed():
	if not self.visible: 
		if is_instance_valid(original_focused_element):
			original_focused_element.grab_focus()
		original_focused_element = null
		
		margin_container.scale = Vector2(1.0, 1.0)
		margin_container.modulate = Color(1.0, 1.0, 1.0, 1.0)
		if is_instance_valid(background_panel):
			background_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
