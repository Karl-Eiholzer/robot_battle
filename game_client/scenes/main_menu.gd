extends Control

# ==================== Node References ====================

@onready var player_name_input: LineEdit = $CenterContainer/VBox/PlayerNameInput
@onready var team_size_option: OptionButton = $CenterContainer/VBox/TeamSizeOption
@onready var create_game_btn: Button = $CenterContainer/VBox/CreateGameBtn
@onready var game_id_input: LineEdit = $CenterContainer/VBox/GameIDInput
@onready var join_game_btn: Button = $CenterContainer/VBox/JoinGameBtn
@onready var status_label: Label = $CenterContainer/VBox/StatusLabel
@onready var error_label: Label = $CenterContainer/VBox/ErrorLabel
@onready var game_id_display: Label = $CenterContainer/VBox/GameIDDisplay
@onready var poll_timer: Timer = $PollTimer

# ==================== State ====================

var _is_waiting: bool = false

# ==================== Ready ====================

func _ready() -> void:
	# Populate team size dropdown
	team_size_option.clear()
	team_size_option.add_item("2v2 (2 per team)", 2)
	team_size_option.add_item("3v3 (3 per team)", 3)

	# Pre-fill from saved state if available
	if GameState.player_name != "":
		player_name_input.text = GameState.player_name
	if GameState.game_id != "":
		game_id_input.text = GameState.game_id

	# Connect buttons
	create_game_btn.pressed.connect(_on_create_pressed)
	join_game_btn.pressed.connect(_on_join_pressed)
	poll_timer.timeout.connect(_on_poll_timer)

	# Connect API signals
	APIClient.game_created.connect(_on_game_created)
	APIClient.game_joined.connect(_on_game_joined)
	APIClient.game_status_received.connect(_on_status_received)
	APIClient.request_failed.connect(_on_request_failed)

# ==================== Button Handlers ====================

func _on_create_pressed() -> void:
	var pname = player_name_input.text.strip_edges()
	if pname == "":
		_show_error("Please enter your name.")
		return

	GameState.player_name = pname
	var team_size = team_size_option.get_item_id(team_size_option.selected)
	_set_waiting(true, "Creating game...")
	APIClient.create_game(pname, team_size)

func _on_join_pressed() -> void:
	var pname = player_name_input.text.strip_edges()
	var gid = game_id_input.text.strip_edges()
	if pname == "":
		_show_error("Please enter your name.")
		return
	if gid == "":
		_show_error("Please enter a game ID.")
		return

	GameState.player_name = pname
	_set_waiting(true, "Joining game...")
	APIClient.join_game(gid, pname)

# ==================== API Response Handlers ====================

func _on_game_created(data: Dictionary) -> void:
	GameState.initialize_from_create_response(data)
	_show_status("Game created! Share this ID with your friends:")
	game_id_display.text = GameState.game_id
	_set_waiting(true, "Waiting for players to join...")
	poll_timer.start()

func _on_game_joined(data: Dictionary) -> void:
	GameState.initialize_from_join_response(data)
	var state = data.get("state", "")
	_show_status("Joined game " + GameState.game_id)
	game_id_display.text = "Game ID: " + GameState.game_id

	if state == "in_progress":
		_transition_forward()
	else:
		_set_waiting(true, "Waiting for players to join...")
		poll_timer.start()

func _on_status_received(data: Dictionary) -> void:
	var state = data.get("state", "")

	match state:
		"waiting_for_players":
			_show_status("Waiting for players to join...")
		"in_progress", "processing_turn":
			_transition_forward()
		"complete":
			_show_error("Game already complete.")
		_:
			_show_status("Game state: " + state)

func _on_request_failed(endpoint: String, status_code: int, body: String) -> void:
	_set_waiting(false, "")
	poll_timer.stop()
	_show_error("Error (%d): %s" % [status_code, body])

# ==================== Polling ====================

func _on_poll_timer() -> void:
	if GameState.game_id != "":
		APIClient.get_status(GameState.game_id)

# ==================== Scene Transitions ====================

func _transition_forward() -> void:
	poll_timer.stop()
	# Check if we need role assignment or can go straight to game view
	# We go to role_assignment scene; it will redirect if robots already spawned
	get_tree().change_scene_to_file("res://scenes/role_assignment.tscn")

# ==================== UI Helpers ====================

func _set_waiting(waiting: bool, msg: String) -> void:
	_is_waiting = waiting
	create_game_btn.disabled = waiting
	join_game_btn.disabled = waiting
	if msg != "":
		_show_status(msg)

func _show_status(msg: String) -> void:
	status_label.text = msg
	error_label.text = ""

func _show_error(msg: String) -> void:
	error_label.text = msg
	status_label.text = ""
	_set_waiting(false, "")
