extends Control

@onready var zoomed_texture_rect: TextureRect = %ZoomedTextureRect
@onready var margin_container: MarginContainer = $Margin 
@onready var background_panel: Panel = $Background 
@onready var l2_container: Control = %L2Container
@onready var r2_container: Control = %R2Container
@onready var layout: HBoxContainer = %Layout # Using % since it's unique now
@onready var animation_container: Control = %AnimationContainer
@onready var close_button: Button = %CloseButton

var original_focused_element: Control = null
var active_tween: Tween = null
var _is_hiding: bool = false
var _zoom_sound_player: AudioStreamPlayer

var _textures: Array[Texture2D] = []
var _current_index: int = 0
var _is_animating: bool = false

func _ready():
	self.visible = false
	if is_instance_valid(background_panel):
		background_panel.gui_input.connect(_on_background_gui_input)
	if is_instance_valid(close_button):
		close_button.pressed.connect(animate_and_hide)
		close_button.mouse_entered.connect(func(): close_button.grab_focus())

func _on_background_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		animate_and_hide()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent):
	if not visible or _is_hiding: return
	
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		animate_and_hide()
		get_viewport().set_input_as_handled()
		return
		
	if _textures.size() > 1 and not _is_animating:
		if event.is_action_pressed("ui_page_up"): # L2
			_switch_screenshot(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_page_down"): # R2
			_switch_screenshot(1)
			get_viewport().set_input_as_handled()
	elif _textures.size() <= 1:
		# Consume tab actions even if only one screenshot, to prevent background navigation
		if event.is_action_pressed("ui_page_up") or event.is_action_pressed("ui_page_down"):
			get_viewport().set_input_as_handled()

func _switch_screenshot(direction: int):
	var new_index = _current_index + direction
	if new_index < 0: new_index = _textures.size() - 1
	if new_index >= _textures.size(): new_index = 0
	
	if new_index == _current_index: return
	
	_is_animating = true
	var old_tex_rect = zoomed_texture_rect
	var new_tex_rect = zoomed_texture_rect.duplicate()
	
	animation_container.add_child(new_tex_rect)
	
	var new_texture = _textures[new_index]
	new_tex_rect.texture = new_texture
	
	# Transition setup
	var container_width = animation_container.size.x
	# New image starts at the edge (right if direction=1, left if direction=-1)
	new_tex_rect.position.x = container_width * direction
	new_tex_rect.modulate.a = 1.0 # Ensure full visibility
	
	if active_tween and active_tween.is_valid(): active_tween.kill()
	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Current image slides out in opposite direction
	active_tween.tween_property(old_tex_rect, "position:x", -container_width * direction, 0.4)
	active_tween.tween_property(old_tex_rect, "modulate:a", 0.0, 0.3)
	
	# New image slides into center
	active_tween.tween_property(new_tex_rect, "position:x", 0, 0.4)
	
	active_tween.chain().tween_callback(func():
		zoomed_texture_rect = new_tex_rect
		old_tex_rect.queue_free()
		_current_index = new_index
		_is_animating = false
	)

func popup_zoomed_image_list(textures: Array[Texture2D], start_index: int, focused_element: Control):
	_textures = textures
	_current_index = start_index
	popup_zoomed_image(_textures[start_index], focused_element)

func popup_zoomed_image(texture: Texture2D, focused_element_before_popup: Control):
	original_focused_element = focused_element_before_popup
	_is_hiding = false
	
	_set_texture_initial(texture) 
	
	var has_multiple = _textures.size() > 1
	if is_instance_valid(l2_container): l2_container.visible = has_multiple
	if is_instance_valid(r2_container): r2_container.visible = has_multiple

	self.visible = true
	_on_about_to_popup()

	margin_container.pivot_offset = margin_container.size / 2.0
	margin_container.scale = Vector2(0.9, 0.9)
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
		zoomed_texture_rect.texture = texture

func animate_and_hide():
	if not self.visible or _is_hiding:
		return
	_is_hiding = true

	if active_tween and active_tween.is_valid():
		active_tween.kill()

	margin_container.pivot_offset = margin_container.size / 2.0

	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.tween_property(margin_container, "scale", Vector2(0.9, 0.9), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.tween_property(margin_container, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_LINEAR)
	if is_instance_valid(background_panel):
		active_tween.tween_property(background_panel, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_LINEAR)
	
	active_tween.chain().tween_callback(_actually_hide)

func _actually_hide():
	self.visible = false
	_is_hiding = false
	if is_instance_valid(original_focused_element):
		original_focused_element.grab_focus()

func _on_about_to_popup():
	_zoom_sound_player = get_node_or_null("/root/App/ZoomSoundPlayer")
	if _zoom_sound_player:
		_zoom_sound_player.play()

func _on_visibility_changed():
	# This might be redundant now but keeping it safe
	pass
