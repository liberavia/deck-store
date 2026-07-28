extends Control

signal transition_finished

@onready var background_layer: CanvasLayer = $BackgroundLayer
@onready var fog_background: ColorRect = $BackgroundLayer/FogBackground

var foreground_layer: CanvasLayer
var foreground_fog: ColorRect

func _ready():
	foreground_layer = CanvasLayer.new()
	foreground_layer.layer = 100
	add_child(foreground_layer)
	
	foreground_fog = fog_background.duplicate()
	foreground_layer.add_child(foreground_fog)

func transition_to_background(duration: float = 3.5):
	if not is_instance_valid(foreground_fog):
		return
		
	var tween = create_tween()
	var audio_player = AudioStreamPlayer.new()
	var stream = load("res://assets/welcome.wav")
	if stream:
		audio_player.stream = stream
		audio_player.volume_db = 8.0
		add_child(audio_player)
		audio_player.play()
		
	tween.tween_interval(1.5)
	tween.tween_property(foreground_fog, "modulate:a", 0.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		if is_instance_valid(foreground_layer):
			foreground_layer.queue_free()
		emit_signal("transition_finished")
	)

	if is_instance_valid(audio_player):
		var audio_tween = create_tween()
		audio_tween.tween_property(audio_player, "volume_db", -40.0, 3.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		audio_tween.tween_callback(func():
			if is_instance_valid(audio_player):
				audio_player.queue_free()
		)
