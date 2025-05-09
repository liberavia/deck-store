# OdrsRatingsCache.gd
extends Node

const RATINGS_URL = "https://odrs.gnome.org/1.0/reviews/api/ratings"
const CACHE_FILENAME = "user://cache/odrs/all_ratings_cache.json"
const CACHE_DURATION_SEC = 60 * 60 * 24 * 7 # 1 Woche

var all_ratings_data: Dictionary = {}
var http_request: HTTPRequest = null
var _is_fetching: bool = false

func _ready():
	var cache_dir = CACHE_FILENAME.get_base_dir()
	var dir_access = DirAccess.open("user://")
	if dir_access:
		DirAccess.make_dir_recursive_absolute(cache_dir)

	_load_or_fetch_ratings()

func _load_or_fetch_ratings():
	if _is_fetching: return 

	if FileAccess.file_exists(CACHE_FILENAME):
		var file = FileAccess.open(CACHE_FILENAME, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			var cache_content = JSON.parse_string(json_string)
			file.close()
			
			if cache_content is Dictionary:
				var timestamp = cache_content.get("timestamp", 0)
				var cached_data = cache_content.get("ratings_data")
				var cache_age_sec = (Time.get_unix_time_from_system() - timestamp)
				
				if cache_age_sec < CACHE_DURATION_SEC and cached_data is Dictionary:
					print("ODRS Ratings: Loaded valid data from cache.")
					all_ratings_data = cached_data
					return

	print("ODRS Ratings: Cache missing or old. Start Download...")
	_fetch_all_ratings()

func _fetch_all_ratings():
	if _is_fetching: return
	_is_fetching = true

	if is_instance_valid(http_request):
		http_request.queue_free() 

	http_request = HTTPRequest.new()
	add_child(http_request) 
	http_request.request_completed.connect(_on_request_completed)
	
	# http_request.set_timeout(30) # 30 Seconds

	var error = http_request.request(RATINGS_URL)
	if error != OK:
		printerr("ODRS Ratings: Request failed: %s" % error)
		_is_fetching = false
		if is_instance_valid(http_request):
			http_request.queue_free()
			http_request = null

func _on_request_completed(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("ODRS Ratings: Download succesful.")
		var json_string = body.get_string_from_utf8()
		var parse_result = JSON.parse_string(json_string)
		
		if parse_result is Dictionary:
			all_ratings_data = parse_result
			
			var cache_content = {
				"timestamp": Time.get_unix_time_from_system(),
				"ratings_data": all_ratings_data
			}
			var file = FileAccess.open(CACHE_FILENAME, FileAccess.WRITE)
			if file:
				file.store_string(JSON.stringify(cache_content, "\t")) # Mit Einrückung speichern (lesbarer)
				file.close()
				print("ODRS Ratings: Saved data to cache.")
			else:
				printerr("ODRS Ratings: Error writing to cache file: ", FileAccess.get_open_error())
		else:
			printerr("ODRS Ratings: Error parsing JSON-Response.")
	else:
		printerr("ODRS Ratings: Download failed! Result: %s, Code: %s" % [result, response_code])

	if is_instance_valid(http_request):
		http_request.queue_free()
		http_request = null
	_is_fetching = false

func get_rating_summary(desktop_id: String) -> Dictionary:
	if not all_ratings_data.has(desktop_id):
		var fallback_id = desktop_id + ".desktop"
		if all_ratings_data.has(fallback_id):
			return all_ratings_data[fallback_id]
		return {}
		
	return all_ratings_data[desktop_id]

func force_refresh():
	if FileAccess.file_exists(CACHE_FILENAME):
		DirAccess.remove_absolute(CACHE_FILENAME)
	_load_or_fetch_ratings()
