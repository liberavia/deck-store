extends SceneTree

func _init():
	print("Converting capsule to header...")
	var capsule_path = "/home/deck/Desktop/Steam_Assets/capsule_600x900.png"
	var header_path = "/home/deck/Desktop/Steam_Assets/header_920x430_auto.png"
	
	var img = Image.load_from_file(capsule_path)
	if not img:
		print("Error: Could not load capsule from ", capsule_path)
		quit()
		return
	
	print("Loaded capsule: ", img.get_width(), "x", img.get_height())
	
	# Scale width to 920, maintaining aspect ratio
	var scale_factor = 920.0 / 600.0
	var new_height = int(900 * scale_factor)
	img.resize(920, new_height, Image.INTERPOLATE_BILINEAR)
	
	# Crop center to 430 height
	var y_offset = (new_height - 430) / 2
	var final_img = img.get_region(Rect2i(0, y_offset, 920, 430))
	
	final_img.save_png(header_path)
	print("Saved perfect header to: ", header_path)
	quit()
