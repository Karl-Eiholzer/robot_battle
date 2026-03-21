extends Node2D

# Main gameplay scene.
# Handles input phase (action planning) and review phase (replay playback).
# Manages the poll timer and coordinates between TurnInput, HexMap, and API.

# ==================== Node References ====================

@onready var hex_map: HexMap = $HexMap
@onready var turn_label: Label = $UI/TopBar/TurnLabel
@onready var initiative_label: Label = $UI/TopBar/InitiativeLabel
@onready var phase_label: Label = $UI/TopBar/PhaseLabel
@onready var timer_label: Label = $UI/TopBar/TimerLabel
@onready var robot_list: VBoxContainer = $UI/RightPanel/RightVBox/RobotList
@onready var robot_stats: Label = $UI/RightPanel/RightVBox/RobotStats
@onready var action_slots: VBoxContainer = $UI/RightPanel/RightVBox/ActionSlots
@onready var deploy_btn: Button = $UI/RightPanel/RightVBox/DeployBtn
@onready var submit_btn: Button = $UI/RightPanel/RightVBox/SubmitBtn
@onready var validation_errors: Label = $UI/RightPanel/RightVBox/ValidationErrors
@onready var status_overlay: PanelContainer = $UI/StatusOverlay
@onready var status_overlay_label: Label = $UI/StatusOverlay/StatusOverlayLabel
@onready var poll_timer: Timer = $PollTimer
@onready var input_timer: Timer = $InputTimer
@onready var camera: Camera2D = $Camera2D
@onready var zoom_in_btn: Button = $UI/TopBar/ZoomInBtn
@onready var zoom_out_btn: Button = $UI/TopBar/ZoomOutBtn

# ==================== State ====================

var _selected_round: int = -1
var _round_buttons: Array = []  # Array of Button nodes for the 6 round slots
var _robot_buttons: Dictionary = {}  # robot_id -> Button
var _input_time_remaining: float = 0.0

# Camera pan state
var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_camera: Vector2 = Vector2.ZERO

# ==================== Ready ====================

func _ready() -> void:
	# Connect signals
	hex_map.hex_clicked.connect(_on_hex_clicked)
	submit_btn.pressed.connect(_on_submit_pressed)
	deploy_btn.pressed.connect(_on_deploy_pressed)
	zoom_in_btn.pressed.connect(_on_zoom_in)
	zoom_out_btn.pressed.connect(_on_zoom_out)
	poll_timer.timeout.connect(_on_poll_timer)
	input_timer.timeout.connect(_on_input_timer_expired)

	TurnInput.phase_changed.connect(_on_phase_changed)
	TurnInput.robot_selected.connect(_on_robot_selected)
	TurnInput.action_plan_changed.connect(_on_action_plan_changed)

	APIClient.moves_submitted.connect(_on_moves_submitted)
	APIClient.results_received.connect(_on_results_received)
	APIClient.request_failed.connect(_on_request_failed)

	GameState.robots_updated.connect(_on_robots_updated)

	# Initialize map and UI
	hex_map.populate_from_game_state()
	camera.position = hex_map.get_player_robots_centroid()
	_rebuild_robot_list()
	_update_header()

	# Start input phase
	TurnInput.start_input_phase()

	# Start input timer if configured
	var input_time = GameState.game_variables.get("input_time", 90)
	if input_time > 0:
		_input_time_remaining = float(input_time)
		input_timer.wait_time = float(input_time)
		input_timer.start()

func _process(_delta: float) -> void:
	if input_timer.time_left > 0:
		timer_label.text = "Time: %ds" % int(input_timer.time_left)
	else:
		timer_label.text = ""

# ==================== Camera Pan / Zoom ====================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var btn = event.button_index
		if btn == MOUSE_BUTTON_MIDDLE or btn == MOUSE_BUTTON_RIGHT:
			_is_panning = event.pressed
			if event.pressed:
				_pan_start_mouse = event.position
				_pan_start_camera = camera.position
		elif event.pressed:
			var pan_step: float = 96.0 / camera.zoom.x
			match btn:
				MOUSE_BUTTON_WHEEL_UP:
					if event.shift_pressed:
						camera.position.y -= pan_step  # Shift+scroll up = pan up
					else:
						_apply_zoom(1.15)
				MOUSE_BUTTON_WHEEL_DOWN:
					if event.shift_pressed:
						camera.position.y += pan_step  # Shift+scroll down = pan down
					else:
						_apply_zoom(1.0 / 1.15)
				MOUSE_BUTTON_WHEEL_LEFT:
					camera.position.x -= pan_step
				MOUSE_BUTTON_WHEEL_RIGHT:
					camera.position.x += pan_step
	elif event is InputEventMouseMotion and _is_panning:
		var delta_screen = event.position - _pan_start_mouse
		camera.position = _pan_start_camera - delta_screen / camera.zoom.x

func _on_zoom_in() -> void:
	_apply_zoom(1.25)

func _on_zoom_out() -> void:
	_apply_zoom(1.0 / 1.25)

func _apply_zoom(factor: float) -> void:
	camera.zoom = (camera.zoom * factor).clamp(Vector2(0.2, 0.2), Vector2(5.0, 5.0))

# ==================== Header ====================

func _update_header() -> void:
	turn_label.text = "Turn %d" % (GameState.current_turn + 1)
	initiative_label.text = "Initiative: Team %d" % GameState.initiative_team
	var phase_name = TurnInput.Phase.keys()[TurnInput.current_phase]
	phase_label.text = "Phase: " + phase_name

# ==================== Robot List ====================

func _rebuild_robot_list() -> void:
	for child in robot_list.get_children():
		child.queue_free()
	_robot_buttons.clear()

	for robot in GameState.player_robots:
		if robot.get("player_id", "") != GameState.player_id:
			continue  # Skip robots belonging to teammates
		var robot_id = robot.get("robot_id", "")
		var robot_type = robot.get("type", "?")
		var _team = robot.get("team", 0)
		var energy = robot.get("energy", 0)
		var state_str = robot.get("state", "active")

		var btn = Button.new()
		btn.text = "[%s] %s E:%d%s" % [
			robot_type.substr(0, 1).to_upper(),
			robot_type,
			energy,
			" (STUNNED)" if state_str == "stunned" else ""
		]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 32)
		btn.pressed.connect(_on_robot_button_pressed.bind(robot_id))
		robot_list.add_child(btn)
		_robot_buttons[robot_id] = btn

# ==================== Robot Selection ====================

func _on_robot_button_pressed(robot_id: String) -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	TurnInput.select_robot(robot_id)

func _on_robot_selected(robot_id: String) -> void:
	# Highlight selected button in right panel
	for rid in _robot_buttons.keys():
		_robot_buttons[rid].button_pressed = (rid == robot_id)

	# Highlight robot sprite on map
	hex_map.set_selected_robot(robot_id)

	# Pan camera to center on the selected robot
	var robot = GameState.robot_lookup.get(robot_id, {})
	if not robot.is_empty():
		var pos = robot.get("position", [0, 0])
		camera.position = HexMath.axial_to_pixel(Vector2i(int(pos[0]), int(pos[1])), HexMath.HEX_SIZE)

	_update_robot_stats(robot_id)
	_rebuild_action_slots(robot_id)
	_update_deploy_button(robot_id)
	_selected_round = -1

func _update_robot_stats(robot_id: String) -> void:
	var robot = GameState.robot_lookup.get(robot_id, {})
	if robot.is_empty():
		robot_stats.text = "(none selected)"
		return

	var stats = TurnInput.ROBOT_STATS.get(robot.get("type", ""), {})
	robot_stats.text = """Type: %s
Energy: %d / %d
Moves/turn: %d (planned: %d)
Strength: %d
Sight: %d
Deploy: %s
State: %s""" % [
		robot.get("type", "?"),
		robot.get("energy", 0),
		stats.get("max_energy", 0),
		TurnInput.get_max_moves(robot_id),
		TurnInput.count_moves_planned(robot_id),
		stats.get("strength", 0),
		stats.get("sight_range", 0),
		stats.get("deploy_type", "?"),
		robot.get("state", "active"),
	]

# ==================== Action Slots ====================

func _rebuild_action_slots(robot_id: String) -> void:
	for child in action_slots.get_children():
		child.queue_free()
	_round_buttons.clear()
	_selected_round = -1

	var rounds = TurnInput.action_plan.get(robot_id, [])
	for i in range(rounds.size()):
		var round_data = rounds[i]
		var hbox = HBoxContainer.new()
		action_slots.add_child(hbox)

		var round_lbl = Label.new()
		round_lbl.text = "R%d:" % (i + 1)
		round_lbl.custom_minimum_size = Vector2(28, 0)
		hbox.add_child(round_lbl)

		var move_btn = Button.new()
		move_btn.text = "Move"
		move_btn.toggle_mode = true
		move_btn.button_pressed = (round_data.get("action_type", "wait") == "move")
		move_btn.custom_minimum_size = Vector2(54, 28)
		move_btn.pressed.connect(_on_round_move_toggle.bind(robot_id, i, move_btn))
		hbox.add_child(move_btn)

		var pos_lbl = Label.new()
		var after = round_data.get("after_position", [0, 0])
		pos_lbl.text = "(%d,%d)" % [after[0], after[1]]
		pos_lbl.custom_minimum_size = Vector2(64, 0)
		pos_lbl.add_theme_font_size_override("font_size", 11)
		hbox.add_child(pos_lbl)

		var deploy_indicator = Label.new()
		var deploy = round_data.get("deploy", null)
		deploy_indicator.text = "[D]" if deploy != null else ""
		deploy_indicator.add_theme_color_override("font_color", Color(0.8, 0.4, 1.0))
		deploy_indicator.add_theme_font_size_override("font_size", 11)
		hbox.add_child(deploy_indicator)

		# Select round button (for deploy targeting)
		var sel_btn = Button.new()
		sel_btn.text = "Sel"
		sel_btn.custom_minimum_size = Vector2(36, 28)
		sel_btn.pressed.connect(_on_select_round.bind(i))
		hbox.add_child(sel_btn)

		_round_buttons.append(hbox)

func _on_round_move_toggle(robot_id: String, round_num: int, btn: Button) -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		btn.button_pressed = not btn.button_pressed
		return

	var action_type = "move" if btn.button_pressed else "wait"

	# Check move limit
	if action_type == "move":
		if TurnInput.count_moves_planned(robot_id) >= TurnInput.get_max_moves(robot_id):
			btn.button_pressed = false
			validation_errors.text = "Move limit reached for this robot."
			return

	var robot = GameState.robot_lookup.get(robot_id, {})
	var pos = robot.get("position", [0, 0])

	# Get the before position from previous round's after position
	var rounds = TurnInput.action_plan.get(robot_id, [])
	var before_pos = pos.duplicate() if pos is Array else [0, 0]
	if round_num > 0 and rounds.size() > round_num - 1:
		before_pos = rounds[round_num - 1].get("after_position", before_pos)

	TurnInput.set_round_action(robot_id, round_num, action_type, before_pos, before_pos)
	_rebuild_action_slots(robot_id)
	_update_robot_stats(robot_id)
	validation_errors.text = ""

func _on_select_round(round_num: int) -> void:
	_selected_round = round_num
	validation_errors.text = "Round %d selected. Click a hex to set destination." % (round_num + 1)
	_update_deploy_button(TurnInput.selected_robot_id)

func _on_action_plan_changed() -> void:
	hex_map.update_move_path_highlights(TurnInput.action_plan, GameState.robot_lookup)
	if TurnInput.selected_robot_id != "":
		_rebuild_action_slots(TurnInput.selected_robot_id)
		_update_robot_stats(TurnInput.selected_robot_id)

# ==================== Deploy Button ====================

func _update_deploy_button(robot_id: String) -> void:
	if robot_id == "":
		deploy_btn.disabled = true
		deploy_btn.text = "Deploy (select robot first)"
		return

	var robot = GameState.robot_lookup.get(robot_id, {})
	var energy = robot.get("energy", 0)
	var deploy_type = TurnInput.ROBOT_STATS.get(robot.get("type", ""), {}).get("deploy_type", "")

	if energy <= 0:
		deploy_btn.disabled = true
		deploy_btn.text = "Deploy (no energy)"
	elif _selected_round < 0:
		deploy_btn.disabled = true
		deploy_btn.text = "Deploy %s (select round first)" % deploy_type
	else:
		deploy_btn.disabled = false
		deploy_btn.text = "Deploy %s on Round %d" % [deploy_type, _selected_round + 1]

func _on_deploy_pressed() -> void:
	if TurnInput.selected_robot_id == "" or _selected_round < 0:
		return

	var deploy_type_local = TurnInput.ROBOT_STATS.get(
		GameState.robot_lookup.get(TurnInput.selected_robot_id, {}).get("type", ""),
		{}).get("deploy_type", "")

	if deploy_type_local == "extra_moves":
		# No targeting needed — apply immediately
		TurnInput.confirm_deploy_target([GameState.robot_lookup[TurnInput.selected_robot_id].get("position", [0,0])])
		return

	# Show valid targets
	var targets = TurnInput.get_valid_deploy_targets(TurnInput.selected_robot_id)
	hex_map.highlight_hexes(targets, Color(0.8, 0.4, 1.0, 0.6))
	TurnInput.start_deploy_targeting(TurnInput.selected_robot_id, _selected_round)
	validation_errors.text = "Click a highlighted hex to deploy %s" % deploy_type_local

# ==================== Hex Click ====================

func _on_hex_clicked(hex: Vector2i) -> void:
	match TurnInput.current_phase:
		TurnInput.Phase.INPUT:
			# Clicking on one of this player's robots selects it (higher priority than move targeting)
			var robot_at = _find_my_robot_at_hex(hex)
			if robot_at != "":
				TurnInput.select_robot(robot_at)
				return
			# Otherwise, if a round is selected, treat the click as a move destination
			if TurnInput.selected_robot_id != "" and _selected_round >= 0:
				_handle_move_target(hex)
		TurnInput.Phase.DEPLOY_TARGETING:
			_handle_deploy_target(hex)

func _find_my_robot_at_hex(hex: Vector2i) -> String:
	for robot in GameState.player_robots:
		if robot.get("player_id", "") != GameState.player_id:
			continue
		var pos = robot.get("position", [0, 0])
		if int(pos[0]) == hex.x and int(pos[1]) == hex.y:
			return robot.get("robot_id", "")
	return ""

func _handle_move_target(hex: Vector2i) -> void:
	var robot_id = TurnInput.selected_robot_id
	var robot = GameState.robot_lookup.get(robot_id, {})
	var rounds = TurnInput.action_plan.get(robot_id, [])

	# Get before position for this round
	var before_pos: Array = robot.get("position", [0, 0])
	if _selected_round > 0 and rounds.size() > _selected_round - 1:
		before_pos = rounds[_selected_round - 1].get("after_position", before_pos)

	var after_pos = [hex.x, hex.y]

	# Validate adjacency (moves must be to adjacent hexes)
	var before_hex = Vector2i(int(before_pos[0]), int(before_pos[1]))
	if HexMath.axial_distance(before_hex, hex) != 1:
		validation_errors.text = "Must move to an adjacent hex."
		return

	# Check move count
	var current_action = rounds[_selected_round].get("action_type", "wait")
	if current_action == "wait":
		# Setting to move — check limit
		if TurnInput.count_moves_planned(robot_id) >= TurnInput.get_max_moves(robot_id):
			validation_errors.text = "Move limit reached."
			return

	TurnInput.set_round_action(robot_id, _selected_round, "move", before_pos, after_pos)
	validation_errors.text = ""
	hex_map.clear_highlights()
	_rebuild_action_slots(robot_id)
	_update_robot_stats(robot_id)

func _handle_deploy_target(hex: Vector2i) -> void:
	TurnInput.confirm_deploy_target([[hex.x, hex.y]])
	hex_map.clear_highlights()
	_rebuild_action_slots(TurnInput.selected_robot_id)
	validation_errors.text = ""

# ==================== Submit ====================

func _on_submit_pressed() -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return

	var errors = TurnInput.validate_plan()
	if errors.size() > 0:
		validation_errors.text = "\n".join(errors)
		return

	var payload = TurnInput.build_submit_payload()
	TurnInput.set_phase(TurnInput.Phase.SUBMITTING)
	submit_btn.disabled = true
	input_timer.stop()
	timer_label.text = ""
	APIClient.submit_actions(GameState.game_id, GameState.current_turn, payload)

func _on_input_timer_expired() -> void:
	# Auto-submit with current plan when time runs out
	if TurnInput.current_phase == TurnInput.Phase.INPUT:
		_on_submit_pressed()

# ==================== Poll for Results ====================

func _on_moves_submitted(data: Dictionary) -> void:
	var errors = data.get("validation_errors", [])
	if errors.size() > 0:
		validation_errors.text = "Server validation: " + "\n".join(errors)
		TurnInput.set_phase(TurnInput.Phase.INPUT)
		submit_btn.disabled = false
		return

	_show_overlay("Waiting for other players... (%d/%d submitted)" % [
		data.get("moves_submitted", 1),
		data.get("moves_required", 1)
	])
	TurnInput.set_phase(TurnInput.Phase.REVIEWING)
	poll_timer.start()

func _on_poll_timer() -> void:
	APIClient.get_results(GameState.game_id, GameState.current_turn)

func _on_results_received(data: Dictionary) -> void:
	if not data.get("ready", false):
		# Not ready yet, keep polling
		return

	poll_timer.stop()

	var winner = data.get("winner", null)
	var replay = data.get("replay", null)

	if replay != null:
		_play_replay(replay, data)
	else:
		# No replay data, just update state
		GameState.apply_turn_results(data)
		if winner != null:
			_go_to_game_end(winner)
		else:
			_start_next_turn()

func _on_request_failed(endpoint: String, _status_code: int, body: String) -> void:
	if endpoint.contains("submit"):
		TurnInput.set_phase(TurnInput.Phase.INPUT)
		submit_btn.disabled = false
		validation_errors.text = "Submit failed: %s" % body
	elif endpoint.contains("results"):
		pass  # Keep polling
	else:
		validation_errors.text = "Error: %s" % body

# ==================== Replay Playback ====================

func _play_replay(replay: Dictionary, full_results: Dictionary) -> void:
	_show_overlay("Playing turn replay...")
	TurnInput.set_phase(TurnInput.Phase.REVIEWING)

	var rounds = replay.get("rounds", [])
	var hex_objects_created = replay.get("hex_objects_created", [])
	var hex_objects_destroyed = replay.get("hex_objects_destroyed", [])
	var winner = replay.get("winner", null)

	# Play each round sequentially
	for round_idx in range(rounds.size()):
		var round_replays = rounds[round_idx]
		# Spread hex object events across rounds proportionally
		var created_this_round: Array = []
		var destroyed_this_round: Array = []
		if round_idx == rounds.size() - 1:
			# Apply all hex object changes at the last round
			created_this_round = hex_objects_created
			destroyed_this_round = hex_objects_destroyed

		hex_map.animate_replay_round(round_replays, created_this_round, destroyed_this_round)

		# Wait for animations to complete
		await get_tree().create_timer(0.6).timeout

	# Brief pause after replay
	await get_tree().create_timer(0.5).timeout

	# Update game state
	GameState.apply_turn_results(full_results)
	_hide_overlay()

	if winner != null:
		_go_to_game_end(winner)
	else:
		_start_next_turn()

# ==================== Next Turn / Game End ====================

func _start_next_turn() -> void:
	hex_map.populate_from_game_state()
	hex_map.set_selected_robot("")
	camera.position = hex_map.get_player_robots_centroid()
	_rebuild_robot_list()
	_update_header()
	TurnInput.start_input_phase()
	validation_errors.text = ""

	var input_time = GameState.game_variables.get("input_time", 90)
	if input_time > 0:
		_input_time_remaining = float(input_time)
		input_timer.wait_time = float(input_time)
		input_timer.start()

func _go_to_game_end(winner: int) -> void:
	GameState.game_state_str = "complete"
	# Store winner for game_end scene
	GameState.initiative_team = winner  # Reuse field temporarily
	get_tree().change_scene_to_file("res://scenes/game_end.tscn")

# ==================== Phase Changes ====================

func _on_phase_changed(new_phase: TurnInput.Phase) -> void:
	_update_header()
	match new_phase:
		TurnInput.Phase.INPUT:
			submit_btn.disabled = false
			_hide_overlay()
		TurnInput.Phase.DEPLOY_TARGETING:
			submit_btn.disabled = true
		TurnInput.Phase.SUBMITTING:
			submit_btn.disabled = true
		TurnInput.Phase.REVIEWING:
			submit_btn.disabled = true
			hex_map.clear_move_path_highlights()

func _on_robots_updated() -> void:
	_rebuild_robot_list()
	if TurnInput.selected_robot_id != "":
		_update_robot_stats(TurnInput.selected_robot_id)

# ==================== Overlay ====================

func _show_overlay(msg: String) -> void:
	status_overlay_label.text = msg
	status_overlay.visible = true

func _hide_overlay() -> void:
	status_overlay.visible = false
