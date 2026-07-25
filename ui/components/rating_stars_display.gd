class_name RatingStarsDisplay
extends Control

@export var star_full_texture: Texture2D
@export var star_half_texture: Texture2D 
@export var star_empty_texture: Texture2D

@export var max_stars: int = 5
@export var star_size: Vector2 = Vector2(24, 24) # Passen Sie dies an Ihre Texturgröße an

@onready var stars_container: HBoxContainer = $StarsContainer

var star_nodes: Array[TextureRect] = []

func _ready():
	for child in stars_container.get_children():
		child.queue_free()
	
	star_nodes.clear()
	
	for i in range(max_stars):
		var star_rect = TextureRect.new()
		star_rect.name = "Star" + str(i)
		star_rect.texture = star_empty_texture
		star_rect.custom_minimum_size = star_size
		star_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE 
		star_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		stars_container.add_child(star_rect)
		star_nodes.append(star_rect)
	
	set_stars(-1.0) 

func set_stars(rating_value: float):
	if not star_full_texture or not star_empty_texture:
		printerr("RatingStarsDisplay: 'star_full_texture' und 'star_empty_texture' have to be added via inspector!")
		visible = false
		return

	if rating_value < 0.0:
		visible = false
		return
	else:
		visible = true

	var clamped_rating = clampf(rating_value, 0.0, float(max_stars))

	for i in range(star_nodes.size()):
		var star_node: TextureRect = star_nodes[i]
		if not is_instance_valid(star_node):
			continue

		var current_star_value = float(i + 1)

		if clamped_rating >= current_star_value:
			star_node.texture = star_full_texture
		elif star_half_texture != null and clamped_rating >= (current_star_value - 0.5):
			star_node.texture = star_half_texture
		else:
			star_node.texture = star_empty_texture
