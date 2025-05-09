class_name ReviewsPopup
extends Window

@onready var app_name_label: Label = $MainMargin/PopupVBox/AppNameLabel
@onready var status_label: Label = $MainMargin/PopupVBox/StatusLabel
@onready var review_list_container: VBoxContainer = $MainMargin/PopupVBox/ReviewScroll/ReviewListContainer
@onready var review_scroll_container: ScrollContainer = $MainMargin/PopupVBox/ReviewScroll

@export var review_item_scene: PackedScene 

func _ready():
	self.close_requested.connect(hide) # Für den OS-Schließen-Button oder Escape
	status_label.visible = false

func _unhandled_input(event: InputEvent):
	if not visible:
		return	

	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept")):
		hide()
		get_viewport().set_input_as_handled()
		
	var scrolled_by_page_action = false
	if is_instance_valid(review_scroll_container):
		var scroll_value_before = review_scroll_container.scroll_vertical
		
		# Wir scrollen um ca. 90% der sichtbaren Höhe für ein angenehmes "Seiten"-Gefühl
		var page_scroll_amount = review_scroll_container.size.y * 0.9 

		if event.is_action_pressed("ui_page_down"):
			review_scroll_container.scroll_vertical += page_scroll_amount
			scrolled_by_page_action = true
		elif event.is_action_pressed("ui_page_up"):
			review_scroll_container.scroll_vertical -= page_scroll_amount
			scrolled_by_page_action = true
		
		# Prüfen, ob tatsächlich gescrollt wurde, bevor das Event als behandelt markiert wird
		if scrolled_by_page_action and review_scroll_container.scroll_vertical != scroll_value_before:
			get_viewport().set_input_as_handled()
			return # Wichtig, damit das Event nicht weiterverarbeitet wird		

func display_reviews(reviews_data: Array, app_name_str: String, has_error: bool = false):
	app_name_label.text = "Reviews for: " + app_name_str

	for child in review_list_container.get_children():
		child.queue_free()

	if has_error:
		status_label.text = "Error loading reviews."
		status_label.visible = true
		review_list_container.visible = false
	elif reviews_data.is_empty():
		status_label.text = "No reviews available."
		status_label.visible = true
		review_list_container.visible = false
	else:
		status_label.visible = false
		review_list_container.visible = true
		if not review_item_scene:
			printerr("ReviewsPopup: 'review_item_scene' not assigned in inspector!")
			status_label.text = "Fehler: Review-Display not configured."
			status_label.visible = true
			return

		var initial_focus_set = false
		for review_dict in reviews_data:
			if not review_dict is Dictionary: continue

			var review_item_instance = review_item_scene.instantiate()
			review_item_instance.focus_mode = Control.FOCUS_ALL
			if !initial_focus_set:
				review_item_instance.grab_focus()
				initial_focus_set = true
			review_list_container.add_child(review_item_instance)
			
			if review_item_instance.has_method("set_review_data"):
				review_item_instance.set_review_data(review_dict)
			else:
				printerr("ReviewsPopup: Instance of 'review_item_scene' has not method 'set_review_data'.")
