extends SceneTree

func _init():
	if Engine.has_singleton("Steam"):
		var steam = Engine.get_singleton("Steam")
		for method in steam.get_method_list():
			if "language" in method.name.to_lower():
				print("FOUND STEAM METHOD: ", method.name)
	else:
		print("STEAM NOT FOUND")
	quit()
