extends SceneTree

func _init():
	var user_path = ProjectSettings.globalize_path("user://")
	print("USER PATH IS: ", user_path)
	var err = DirAccess.make_dir_recursive_absolute("user://tmp_scripts_test")
	print("MAKE DIR ERR: ", err)
	quit()
