extends Control

@onready var spinner: TextureRect = $Spinner

var _is_spinning: bool = false
var _rotation_speed: float = 5.0

func _ready():
	visible = false
	_is_spinning = false

func _process(delta):
	if _is_spinning and is_instance_valid(spinner):
		spinner.rotation += _rotation_speed * delta

func show_overlay():
	visible = true
	_is_spinning = true
	# Reset rotation if desired, or keep spinning
	
func hide_overlay():
	visible = false
	_is_spinning = false
