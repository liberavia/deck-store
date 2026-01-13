extends Button

signal item_pressed(app_id: String)

@onready var icon_rect: TextureRect = $MarginContainer/HBoxContainer/IconRect
@onready var name_label: Label = $MarginContainer/HBoxContainer/NameLabel
@onready var size_label: Label = $MarginContainer/HBoxContainer/SizeLabel

var app_id: String = ""
var audio_player: AudioStreamPlayer
var stream_focus = preload("res://assets/change.mp3")
var stream_select = preload("res://assets/nextprev.wav")

func setup(p_app_id: String, p_name: String, p_size: String):
	app_id = p_app_id
	name_label.text = p_name
	size_label.text = p_size
	_load_icon()

func _ready():
	pressed.connect(_on_pressed)
	focus_entered.connect(_on_focus_entered)
	
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)

func _on_pressed():
	if audio_player and stream_select:
		audio_player.stream = stream_select
		audio_player.play()
	emit_signal("item_pressed", app_id)

func _on_focus_entered():
	if audio_player and stream_focus:
		audio_player.stream = stream_focus
		audio_player.play()

func _load_icon():
	# So we fetch metadata to get the URL.
	var metadata_url = "https://flathub.org/api/v2/appstream/%s" % app_id
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_metadata_received.bind(http))
	var err = http.request(metadata_url)
	if err != OK:
		http.queue_free()

func _on_metadata_received(result, response_code, headers, body, http_request):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json is Dictionary:
			var icon_url = ""
			
			# 1. Try top-level "icon" field (String)
			if json.has("icon") and json["icon"] is String:
				icon_url = json["icon"]
			
			# 2. Fallback: "icons" field (Array of Objects)
			elif json.has("icons") and json["icons"] is Array:
				var icons_list = json["icons"]
				for icon_data in icons_list:
					if icon_data is Dictionary and icon_data.has("url"):
						icon_url = icon_data["url"]
						# Valid sizing? prefer 128 or 64, but taking the first valid one is often fine as fallback
						if icon_data.get("width") == 128:
							break 

			if not icon_url.is_empty():
				_fetch_icon_image(icon_url)
	
	http_request.queue_free()

func _fetch_icon_image(url: String):
	# Use Main's caching logic if available, or just fetch
	var main_node = get_node_or_null("/root/App")
	if main_node and main_node.has_method("get_cached_image_path"):
		var cached_path = main_node.get_cached_image_path(url)
		if not cached_path.is_empty():
			var texture = _load_texture_from_path(cached_path)
			if texture:
				icon_rect.texture = texture
				return

	# If not in cache, request it
	if main_node and main_node.has_signal("image_load_requested"):
		main_node.emit_signal("image_load_requested", url, icon_rect)
	else:
		var http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(_on_icon_downloaded.bind(http))
		http.request(url)

func _on_icon_downloaded(result, response_code, headers, body, http_request):
	if response_code == 200:
		var image = Image.new()
		var err = image.load_png_from_buffer(body) # Assume PNG for Flathub icons usually
		if err != OK:
			err = image.load_webp_from_buffer(body) # Try WebP
		
		if err == OK:
			var texture = ImageTexture.create_from_image(image)
			icon_rect.texture = texture
	http_request.queue_free()

func _load_texture_from_path(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var image = Image.new()
		var err = image.load(path)
		if err == OK:
			return ImageTexture.create_from_image(image)
	return null
