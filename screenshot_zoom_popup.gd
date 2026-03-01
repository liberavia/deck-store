extends Window

@onready var zoomed_texture_rect: TextureRect = $Margin/ZoomedTextureRect
@onready var margin_container: MarginContainer = $Margin 
@onready var background_panel: Panel = $Background 

var original_focused_element: Control = null
var active_tween: Tween = null
var _is_hiding: bool = false
var _zoom_sound_player: AudioStreamPlayer

var _textures: Array[Texture2D] = []
var _current_index: int = 0
var _is_animating: bool = false

func _ready():
	self.transparent_bg = true
	self.borderless = true
	
	self.close_requested.connect(animate_and_hide) 
	self.about_to_popup.connect(_on_about_to_popup)
	self.visibility_changed.connect(_on_visibility_changed)

func _unhandled_input(event: InputEvent):
	if not visible or _is_hiding: return
	
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		animate_and_hide()
		get_viewport().set_input_as_handled()
		return
		
	if _textures.size() > 1 and not _is_animating:
		if event.is_action_pressed("previous_tab"): # L2
			_switch_screenshot(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("next_tab"): # R2
			_switch_screenshot(1)
			get_viewport().set_input_as_handled()

func _switch_screenshot(direction: int):
	var new_index = _current_index + direction
	if new_index < 0: new_index = _textures.size() - 1
	if new_index >= _textures.size(): new_index = 0
	
	if new_index == _current_index: return
	
	_is_animating = true
	var old_tex_rect = zoomed_texture_rect
	var new_tex_rect = zoomed_texture_rect.duplicate()
	margin_container.add_child(new_tex_rect)
	
	var new_texture = _textures[new_index]
	new_tex_rect.texture = new_texture
	
	# Calculate sizes
	var display_size = _calculate_display_size(new_texture)
	new_tex_rect.custom_minimum_size = display_size
	
	# Transition
	var offset_x = size.x * 1.2 * direction
	new_tex_rect.position.x = offset_x
	
	if active_tween and active_tween.is_valid(): active_tween.kill()
	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	active_tween.tween_property(old_tex_rect, "position:x", -offset_x, 0.5)
	active_tween.tween_property(old_tex_rect, "modulate:a", 0.0, 0.3)
	
	active_tween.tween_property(new_tex_rect, "position:x", 0, 0.5)
	active_tween.tween_property(new_tex_rect, "modulate:a", 1.0, 0.3)
	
	# Resize window if needed? Usually screenshots are same aspect, but just in case
	var final_window_width = display_size.x + margin_container.get_theme_constant("margin_left") + margin_container.get_theme_constant("margin_right")
	var final_window_height = display_size.y + margin_container.get_theme_constant("margin_top") + margin_container.get_theme_constant("margin_bottom")
	active_tween.tween_property(self, "size", Vector2i(ceil(final_window_width), ceil(final_window_height)), 0.5)
	
	active_tween.chain().tween_callback(func():
		zoomed_texture_rect = new_tex_rect
		old_tex_rect.queue_free()
		_current_index = new_index
		_is_animating = false
		popup_centered() # Re-center if size changed
	)

func _calculate_display_size(texture: Texture2D) -> Vector2:
	var original_texture_size = texture.get_size()
	var main_window_size = get_tree().root.size 
	var mc_margin_left = margin_container.get_theme_constant("margin_left")
	var mc_margin_right = margin_container.get_theme_constant("margin_right")
	var mc_margin_top = margin_container.get_theme_constant("margin_top")
	var mc_margin_bottom = margin_container.get_theme_constant("margin_bottom")
	
	var max_total_popup_content_width = main_window_size.x * 0.9
	var max_total_popup_content_height = main_window_size.y * 0.9
	
	var max_image_render_width = max_total_popup_content_width - (mc_margin_left + mc_margin_right)
	var max_image_render_height = max_total_popup_content_height - (mc_margin_top + mc_margin_bottom)

	var image_display_size = original_texture_size

	if image_display_size.x > max_image_render_width:
		image_display_size.y = (max_image_render_width / image_display_size.x) * image_display_size.y
		image_display_size.x = max_image_render_width
	
	if image_display_size.y > max_image_render_height:
		image_display_size.x = (max_image_render_height / image_display_size.y) * image_display_size.x
		image_display_size.y = max_image_render_height
		
	return image_display_size

func popup_zoomed_image_list(textures: Array[Texture2D], start_index: int, focused_element: Control):
	_textures = textures
	_current_index = start_index
	popup_zoomed_image(_textures[start_index], focused_element)

func popup_zoomed_image(texture: Texture2D, focused_element_before_popup: Control):
	_set_texture_initial(texture) 
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

func _set_texture_initial(texture: Texture2D):
	if zoomed_texture_rect and texture:
		var display_size = _calculate_display_size(texture)
		zoomed_texture_rect.texture = texture
		zoomed_texture_rect.custom_minimum_size = display_size
		
		var final_window_width = display_size.x + margin_container.get_theme_constant("margin_left") + margin_container.get_theme_constant("margin_right")
		var final_window_height = display_size.y + margin_container.get_theme_constant("margin_top") + margin_container.get_theme_constant("margin_bottom")
		self.size = Vector2i(ceil(final_window_width), ceil(final_window_height))

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
