extends SceneTree

func _init():
	print("Generating Steam Library Assets...")
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("user://steam_assets"):
		DirAccess.open("user://").make_dir("steam_assets")
	
	_generate_rect("user://steam_assets/capsule_600x900.png", 600, 900, "Deck Store", true)
	_generate_rect("user://steam_assets/header_920x430.png", 920, 430, "Deck Store", true)
	_generate_rect("user://steam_assets/hero_3840x1240.png", 3840, 1240, "", true)
	_generate_logo("user://steam_assets/logo_1280x720.png", 1280, 720, "Deck Store")
	
	print("Assets generated in user://steam_assets/")
	print("Path on disk: ", ProjectSettings.globalize_path("user://steam_assets/"))
	quit()

func _generate_rect(path: String, w: int, h: int, text: String, fill_bg: bool):
	var img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	if fill_bg:
		for y in range(h):
			for x in range(w):
				var r = lerpf(0.1, 0.4, float(x)/w)
				var g = lerpf(0.1, 0.2, float(y)/h)
				var b = lerpf(0.3, 0.6, float(x+y)/(w+h))
				img.set_pixel(x, y, Color(r, g, b, 1.0))
	
	img.save_png(path)

func _generate_logo(path: String, w: int, h: int, text: String):
	# Transparent background
	var img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.save_png(path)
