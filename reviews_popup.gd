class_name ReviewsPopup
extends Control

@onready var app_name_label: Label = $MainMargin/Panel/ContentMargin/PopupVBox/Header/AppNameLabel
@onready var status_label: Label = $MainMargin/Panel/ContentMargin/PopupVBox/StatusLabel
@onready var review_list_container: VBoxContainer = $MainMargin/Panel/ContentMargin/PopupVBox/ReviewScroll/ReviewListContainer
@onready var review_scroll_container: ScrollContainer = $MainMargin/Panel/ContentMargin/PopupVBox/ReviewScroll
@onready var close_button: Button = %CloseButton
@onready var background_panel: Panel = $Background

@export var review_item_scene: PackedScene 

var original_focused_element: Control = null

func _ready():
	self.visible = false
	if is_instance_valid(close_button):
		close_button.pressed.connect(hide_modal)
		close_button.mouse_entered.connect(func(): close_button.grab_focus())
	if is_instance_valid(background_panel):
		background_panel.gui_input.connect(_on_background_gui_input)

func _on_background_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hide_modal()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent):
	if not visible:
		return	

	if event.is_action_pressed("ui_cancel"):
		hide_modal()
		get_viewport().set_input_as_handled()
		return
		
	var scrolled_by_page_action = false
	if is_instance_valid(review_scroll_container):
		var scroll_value_before = review_scroll_container.scroll_vertical
		var page_scroll_amount = review_scroll_container.size.y * 0.9 

		if event.is_action_pressed("ui_page_down"):
			review_scroll_container.scroll_vertical += page_scroll_amount
			scrolled_by_page_action = true
		elif event.is_action_pressed("ui_page_up"):
			review_scroll_container.scroll_vertical -= page_scroll_amount
			scrolled_by_page_action = true
		
		if scrolled_by_page_action and review_scroll_container.scroll_vertical != scroll_value_before:
			get_viewport().set_input_as_handled()
			return

func display_reviews(reviews_data: Array, app_name_str: String, has_error: bool = false):
	app_name_label.text = tr("LBL_REVIEWS_FOR") + " " + app_name_str

	for child in review_list_container.get_children():
		child.queue_free()

	if has_error:
		status_label.text = tr("ERR_LOADING_REVIEWS")
		status_label.visible = true
		review_list_container.visible = false
	elif reviews_data.is_empty():
		status_label.text = tr("LBL_NO_REVIEWS")
		status_label.visible = true
		review_list_container.visible = false
	else:
		status_label.visible = false
		review_list_container.visible = true
		
		for review_dict in reviews_data:
			if not review_dict is Dictionary: continue
			var review_item_instance = review_item_scene.instantiate()
			review_item_instance.focus_mode = Control.FOCUS_ALL
			review_list_container.add_child(review_item_instance)
			if review_item_instance.has_method("set_review_data"):
				review_item_instance.set_review_data(review_dict)

func show_modal():
	original_focused_element = get_viewport().gui_get_focus_owner()
	self.visible = true
	# Wait for layout
	await get_tree().process_frame
	if review_list_container.get_child_count() > 0:
		review_list_container.get_child(0).grab_focus()
	else:
		close_button.grab_focus()

func hide_modal():
	self.visible = false
	if is_instance_valid(original_focused_element):
		original_focused_element.grab_focus()
	original_focused_element = null
