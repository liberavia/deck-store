extends Node

signal online_status_changed(is_online: bool)

var is_online: bool = true
var _http_request: HTTPRequest
var _timer: Timer

func _ready():
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	_timer = Timer.new()
	_timer.wait_time = 30.0
	_timer.autostart = true
	_timer.timeout.connect(check_status)
	add_child(_timer)
	
	check_status()

func check_status():
	if _http_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		var error = _http_request.request("https://flathub.org/api/v2/stats", ["Cache-Control: no-cache"], HTTPClient.METHOD_GET)
		if error != OK:
			_set_online(false)

func _on_request_completed(result, response_code, _headers, _body):
	var new_status = (result == HTTPRequest.RESULT_SUCCESS and response_code == 200)
	_set_online(new_status)

func _set_online(status: bool):
	var steam_online = true
	if Engine.has_singleton("Steam"):
		steam_online = Steam.loggedOn()
		
	var new_status = status and steam_online
	if new_status != is_online:
		is_online = new_status
		emit_signal("online_status_changed", is_online)
