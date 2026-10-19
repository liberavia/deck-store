extends Node

signal update_available(latest_version: String, release_notes: String)
signal update_check_completed(is_available: bool, latest_version: String)
signal update_download_progress(percent: int, status_text: String)
signal update_ready_to_restart(version: String)
signal update_failed(error_message: String)

const GITHUB_LATEST_RELEASE_URL = "https://api.github.com/repos/liberavia/deck-store/releases/latest"
const RELEASE_ASSET_NAME = "deck-store-linux.zip"
const EXIT_CODE_UPDATE_RESTART = 42

var current_version: String = "v0.0.0"
var latest_version: String = ""
var latest_release_notes: String = ""
var download_url: String = ""
var is_update_available: bool = false
var is_downloading: bool = false
var is_update_staged: bool = false

var _check_http: HTTPRequest = null
var _download_http: HTTPRequest = null
var _extract_thread: Thread = null
var _staged_dir: String = ""
var _zip_path: String = ""
var _bin_dir: String = ""

func _ready():
	_setup_paths()
	_load_current_version()
	_setup_http_nodes()
	if not OS.has_feature("editor"):
		call_deferred("check_for_self_update")

func _exit_tree():
	if _extract_thread != null and _extract_thread.is_started():
		_extract_thread.wait_to_finish()

func _setup_paths():
	var home = OS.get_environment("HOME")
	if home.is_empty():
		home = "/home/deck"
	var base_dir = home.path_join(".deck-store")
	_bin_dir = base_dir.path_join("bin")
	var tmp_dir = base_dir.path_join("tmp")
	_staged_dir = tmp_dir.path_join("staged_update")
	_zip_path = tmp_dir.path_join("deck-store-update.zip")
	DirAccess.make_dir_recursive_absolute(tmp_dir)

func _load_current_version():
	var exe_dir = OS.get_executable_path().get_base_dir()
	var candidates = [
		exe_dir.path_join("version.txt"),
		_bin_dir.path_join("version.txt"),
		"res://version.txt"
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			if f:
				var v = f.get_as_text().strip_edges()
				f.close()
				if not v.is_empty():
					current_version = v
					print("SelfUpdateManager: Loaded current version '", current_version, "' from ", path)
					return
	var proj_ver = str(ProjectSettings.get_setting("application/config/version", ""))
	if not proj_ver.is_empty():
		current_version = proj_ver

func _setup_http_nodes():
	_check_http = HTTPRequest.new()
	add_child(_check_http)
	_check_http.request_completed.connect(_on_check_request_completed)

	_download_http = HTTPRequest.new()
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download_request_completed)

func _process(_delta):
	if is_downloading and is_instance_valid(_download_http):
		var total = _download_http.get_body_size()
		var downloaded = _download_http.get_downloaded_bytes()
		if total > 0:
			var pct = clampi(int((float(downloaded) / float(total)) * 85.0), 1, 85)
			emit_signal("update_download_progress", pct, "Downloading update (%d%%)..." % pct)

func check_for_self_update():
	if not is_instance_valid(_check_http):
		return
	if _check_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var headers = ["User-Agent: GodotDeckStore/1.0", "Accept: application/vnd.github.v3+json"]
	_check_http.request(GITHUB_LATEST_RELEASE_URL, headers)

func _on_check_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		emit_signal("update_check_completed", false, current_version)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		emit_signal("update_check_completed", false, current_version)
		return

	var tag = str(parsed.get("tag_name", "")).strip_edges()
	if tag.is_empty():
		emit_signal("update_check_completed", false, current_version)
		return

	latest_version = tag
	latest_release_notes = str(parsed.get("body", ""))
	download_url = ""

	var assets = parsed.get("assets", [])
	if assets is Array:
		for asset in assets:
			if asset is Dictionary and asset.get("name") == RELEASE_ASSET_NAME:
				download_url = str(asset.get("browser_download_url", ""))
				break

	is_update_available = _is_newer_version(current_version, latest_version) and not download_url.is_empty()
	emit_signal("update_check_completed", is_update_available, latest_version)

	if is_update_available:
		print("SelfUpdateManager: New update available: ", latest_version, " (current: ", current_version, ")")
		emit_signal("update_available", latest_version, latest_release_notes)

func _extract_numeric_parts(ver_str: String) -> PackedInt32Array:
	var cleaned = ver_str.strip_edges().lstrip("vV")
	var dash_idx = cleaned.find("-")
	if dash_idx != -1:
		cleaned = cleaned.substr(0, dash_idx)
	var parts = cleaned.split(".")
	var nums = PackedInt32Array()
	for p in parts:
		if p.is_valid_int():
			nums.append(p.to_int())
	return nums

func _is_newer_version(curr: String, latest: String) -> bool:
	if curr.is_empty() or curr == "v0.0.0" or curr == "0.0.0":
		return false
	if curr == latest:
		return false
	var c_parts = _extract_numeric_parts(curr)
	var l_parts = _extract_numeric_parts(latest)
	var count = maxi(c_parts.size(), l_parts.size())
	for i in range(count):
		var c_val = c_parts[i] if i < c_parts.size() else 0
		var l_val = l_parts[i] if i < l_parts.size() else 0
		if l_val > c_val:
			return true
		elif l_val < c_val:
			return false
	return false

func start_self_update():
	if is_downloading or download_url.is_empty():
		return
	is_downloading = true
	is_update_staged = false
	if FileAccess.file_exists(_zip_path):
		DirAccess.remove_absolute(_zip_path)
	emit_signal("update_download_progress", 1, "Starting download...")
	_download_http.download_file = _zip_path
	var headers = ["User-Agent: GodotDeckStore/1.0"]
	var err = _download_http.request(download_url, headers)
	if err != OK:
		is_downloading = false
		emit_signal("update_failed", "Could not start update download (Code %d)" % err)

func _on_download_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		is_downloading = false
		emit_signal("update_failed", "Download failed (HTTP %d)" % response_code)
		return

	emit_signal("update_download_progress", 90, "Extracting update...")
	if _extract_thread != null and _extract_thread.is_started():
		_extract_thread.wait_to_finish()
	_extract_thread = Thread.new()
	_extract_thread.start(_extract_update_in_thread)

func _extract_update_in_thread():
	var cmd = "rm -rf '%s' && mkdir -p '%s' && unzip -o -q '%s' -d '%s' && rm -f '%s'" % [
		_staged_dir, _staged_dir, _zip_path, _staged_dir, _zip_path
	]
	var exit_code = OS.execute(SystemUtils.get_host_sh_cmd(), SystemUtils.get_host_sh_args(cmd), [], true, false)
	if exit_code == 0:
		var ver_file = FileAccess.open(_staged_dir.path_join("version.txt"), FileAccess.WRITE)
		if ver_file:
			ver_file.store_string(latest_version + "\n")
			ver_file.close()
	call_deferred("_on_extract_finished", exit_code)

func _on_extract_finished(exit_code: int):
	if _extract_thread != null and _extract_thread.is_started():
		_extract_thread.wait_to_finish()
	_extract_thread = null
	is_downloading = false

	if exit_code != 0:
		emit_signal("update_failed", "Failed to extract update archive.")
		return

	is_update_staged = true
	is_update_available = false
	emit_signal("update_download_progress", 100, "Update ready! Restart to apply.")
	emit_signal("update_ready_to_restart", latest_version)

func apply_and_restart():
	if not is_update_staged:
		return
	if OS.get_environment("DECKSTORE_WRAPPER_ACTIVE") != "1":
		var target_dir = OS.get_executable_path().get_base_dir()
		if not FileAccess.file_exists(target_dir.path_join("deck-store.x86_64")) and DirAccess.dir_exists_absolute(_bin_dir):
			target_dir = _bin_dir
		var fallback_cmd = "(sleep 1 && cp -rf '%s'/* '%s'/ && chmod +x '%s/deck-store.x86_64' && rm -rf '%s' && exec '%s/deck-store.x86_64') >/dev/null 2>&1 &" % [
			_staged_dir, target_dir, target_dir, _staged_dir, target_dir
		]
		OS.create_process(SystemUtils.get_host_sh_cmd(), SystemUtils.get_host_sh_args(fallback_cmd))
	get_tree().quit(EXIT_CODE_UPDATE_RESTART)
