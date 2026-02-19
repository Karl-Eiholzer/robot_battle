extends Node

# All HTTP communication with the Robot Battle backend.
# Uses a single HTTPRequest node with a pending request queue.
# All responses are returned via signals.

const BASE_URL = "https://robotbattle-production.up.railway.app"

# ==================== Signals ====================

signal game_created(data: Dictionary)
signal game_joined(data: Dictionary)
signal game_status_received(data: Dictionary)
signal roles_assigned(data: Dictionary)
signal robots_spawned(data: Dictionary)
signal initial_state_received(data: Dictionary)
signal moves_submitted(data: Dictionary)
signal results_received(data: Dictionary)
signal request_failed(endpoint: String, status_code: int, body: String)

# ==================== Internal State ====================

var _http: HTTPRequest
var _pending_endpoint: String = ""
var _request_queue: Array = []  # Array of {endpoint, method, body, signal_name}
var _is_requesting: bool = false

# ==================== Setup ====================

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

# ==================== Public API Methods ====================

func create_game(player_name: String, team_size: int) -> void:
	var body = {
		"max_players": team_size * 2,
		"map_config": {"width": 15, "height": 15},
		"game_variables": {"team_size": team_size}
	}
	_enqueue("/game/create", HTTPClient.METHOD_POST, body, "game_created")

func join_game(game_id: String, player_name: String) -> void:
	var body = {"player_name": player_name}
	_enqueue("/game/" + game_id + "/join", HTTPClient.METHOD_POST, body, "game_joined")

func get_status(game_id: String) -> void:
	_enqueue("/game/" + game_id + "/status", HTTPClient.METHOD_GET, {}, "game_status_received")

func assign_roles(game_id: String, team: int, assignments: Dictionary) -> void:
	var body = {
		"team": team,
		"role_assignments": assignments
	}
	_enqueue("/game/" + game_id + "/team/" + str(team) + "/assign_roles",
			HTTPClient.METHOD_POST, body, "roles_assigned")

func spawn_robots(game_id: String) -> void:
	_enqueue("/game/" + game_id + "/spawn_robots", HTTPClient.METHOD_POST, {}, "robots_spawned")

func get_initial_state(game_id: String) -> void:
	_enqueue("/game/" + game_id + "/initial_state", HTTPClient.METHOD_GET, {}, "initial_state_received")

func submit_actions(game_id: String, turn: int, actions: Array) -> void:
	var body = {
		"turn": turn,
		"actions": actions
	}
	_enqueue("/game/" + game_id + "/submit", HTTPClient.METHOD_POST, body, "moves_submitted")

func get_results(game_id: String, turn: int) -> void:
	_enqueue("/game/" + game_id + "/results?turn=" + str(turn),
			HTTPClient.METHOD_GET, {}, "results_received")

# ==================== Request Queue ====================

func _enqueue(endpoint: String, method: int, body: Dictionary, signal_name: String) -> void:
	_request_queue.append({
		"endpoint": endpoint,
		"method": method,
		"body": body,
		"signal_name": signal_name
	})
	if not _is_requesting:
		_process_next_request()

func _process_next_request() -> void:
	if _request_queue.is_empty():
		_is_requesting = false
		return
	_is_requesting = true
	var req = _request_queue.pop_front()
	_pending_endpoint = req.endpoint
	_pending_signal = req.signal_name
	_do_request(req.method, req.endpoint, req.body)

var _pending_signal: String = ""

func _do_request(method: int, endpoint: String, body: Dictionary) -> void:
	var headers: Array = ["Content-Type: application/json"]
	if GameState.api_key != "":
		headers.append("X-API-Key: " + GameState.api_key)

	var json_body: String = ""
	if body.size() > 0:
		json_body = JSON.stringify(body)

	var url = BASE_URL + endpoint
	var error = _http.request(url, headers, method, json_body)
	if error != OK:
		push_error("HTTPRequest error %d for %s" % [error, endpoint])
		request_failed.emit(endpoint, -1, "Request setup failed")
		_is_requesting = false
		_process_next_request()

# ==================== Response Handler ====================

func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:

	var endpoint = _pending_endpoint
	var signal_name = _pending_signal

	# Parse JSON body
	var text = body.get_string_from_utf8()
	var data: Dictionary = {}
	if text != "":
		var parsed = JSON.parse_string(text)
		if parsed != null and parsed is Dictionary:
			data = parsed

	# Handle HTTP errors
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		var error_msg = data.get("detail", "HTTP %d" % response_code)
		push_error("API error [%d] %s: %s" % [response_code, endpoint, error_msg])
		request_failed.emit(endpoint, response_code, error_msg)
		_is_requesting = false
		_process_next_request()
		return

	# Emit the appropriate signal
	match signal_name:
		"game_created":
			game_created.emit(data)
		"game_joined":
			game_joined.emit(data)
		"game_status_received":
			game_status_received.emit(data)
		"roles_assigned":
			roles_assigned.emit(data)
		"robots_spawned":
			robots_spawned.emit(data)
		"initial_state_received":
			initial_state_received.emit(data)
		"moves_submitted":
			moves_submitted.emit(data)
		"results_received":
			results_received.emit(data)
		_:
			push_warning("Unknown signal: " + signal_name)

	_is_requesting = false
	_process_next_request()
