extends Node2D

# Main gameplay scene.
# Round-centric input: the player plans all robots' moves for round N, then
# advances to round N+1. Navigation is free — prev/next buttons or click any
# round indicator. Robots are shown at their projected positions for the
# current round; move arrows show planned destinations.

# ==================== Node References ====================

@onready var hex_map: HexMap = $HexMap
@onready var turn_label: Label = $UI/TopBar/TurnLabel
@onready var initiative_label: Label = $UI/TopBar/InitiativeLabel
@onready var phase_label: Label = $UI/TopBar/PhaseLabel
@onready var timer_label: Label = $UI/TopBar/TimerLabel
@onready var zoom_in_btn: Button = $UI/TopBar/ZoomInBtn
@onready var zoom_out_btn: Button = $UI/TopBar/ZoomOutBtn
@onready var round_nav: HBoxContainer = $UI/RoundNav
@onready var prev_round_btn: Button = $UI/RoundNav/PrevRoundBtn
@onready var next_round_btn: Button = $UI/RoundNav/NextRoundBtn
@onready var round_label: Label = $UI/RightPanel/RightVBox/RoundLabel
@onready var robot_status_list: VBoxContainer = $UI/RightPanel/RightVBox/RobotStatusList
@onready var deploy_btn: Button = $UI/RightPanel/RightVBox/DeployBtn
@onready var submit_btn: Button = $UI/RightPanel/RightVBox/SubmitBtn
@onready var replay_btn: Button = $UI/RightPanel/RightVBox/ReplayBtn
@onready var hint_label: Label = $UI/RightPanel/RightVBox/HintLabel
@onready var status_overlay: PanelContainer = $UI/StatusOverlay
@onready var status_overlay_label: Label = $UI/StatusOverlay/StatusOverlayLabel
@onready var poll_timer: Timer = $PollTimer
@onready var input_timer: Timer = $InputTimer
@onready var camera: Camera2D = $Camera2D

# ==================== State ====================

# Six round indicator buttons (R1..R6), created in _ready() and inserted
# between PrevRoundBtn and NextRoundBtn in the RoundNav bar.
var _round_nav_btns: Array = []
var _last_replay: Dictionary = {}

# Camera pan state
var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_camera: Vector2 = Vector2.ZERO

# ==================== Ready ====================

func _ready() -> void:
	# Build R1..R6 buttons and insert them between Prev and Next in the bar.
	# After adding each button to the end it is moved to the correct index:
	# Prev=0, R1=1, R2=2, ..., R6=6, Next=7.
	for i in range(TurnInput.ROUNDS_PER_TURN):
		var btn = Button.new()
		btn.text = "R%d" % (i + 1)
		btn.custom_minimum_size = Vector2(44, 0)
		btn.toggle_mode = true
		btn.pressed.connect(_on_round_nav_pressed.bind(i))
		round_nav.add_child(btn)
		round_nav.move_child(btn, 1 + i)  # slide in before Next
		_round_nav_btns.append(btn)

	# Signal connections
	hex_map.hex_clicked.connect(_on_hex_clicked)
	prev_round_btn.pressed.connect(_on_prev_round)
	next_round_btn.pressed.connect(_on_next_round)
	submit_btn.pressed.connect(_on_submit_pressed)
	deploy_btn.pressed.connect(_on_deploy_pressed)
	zoom_in_btn.pressed.connect(_on_zoom_in)
	zoom_out_btn.pressed.connect(_on_zoom_out)
	replay_btn.pressed.connect(_replay_last_turn)
	poll_timer.timeout.connect(_on_poll_timer)
	input_timer.timeout.connect(_on_input_timer_expired)

	TurnInput.phase_changed.connect(_on_phase_changed)
	TurnInput.current_round_changed.connect(_on_current_round_changed)
	TurnInput.robot_selected.connect(_on_robot_selected)
	TurnInput.action_plan_changed.connect(_on_action_plan_changed)

	APIClient.moves_submitted.connect(_on_moves_submitted)
	APIClient.results_received.connect(_on_results_received)
	APIClient.request_failed.connect(_on_request_failed)

	GameState.robots_updated.connect(_on_robots_updated)

	# Populate map first, then start input phase (which fires current_round_changed
	# and triggers _update_round_display while action_plan and sprites are ready).
	hex_map.populate_from_game_state()
	camera.position = hex_map.get_player_robots_centroid()
	_update_header()
	TurnInput.start_input_phase()

	var input_time = GameState.game_variables.get("input_time", 90)
	if input_time > 0:
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
						camera.position.y -= pan_step
					else:
						_apply_zoom(1.15)
				MOUSE_BUTTON_WHEEL_DOWN:
					if event.shift_pressed:
						camera.position.y += pan_step
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

# ==================== Round Navigation ====================

func _on_prev_round() -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	if TurnInput.current_round > 0:
		TurnInput.set_current_round(TurnInput.current_round - 1)

func _on_next_round() -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	if TurnInput.current_round < TurnInput.ROUNDS_PER_TURN - 1:
		TurnInput.set_current_round(TurnInput.current_round + 1)

func _on_round_nav_pressed(round_idx: int) -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	TurnInput.set_current_round(round_idx)

func _on_current_round_changed(_round_num: int) -> void:
	_update_round_display()

func _update_round_display() -> void:
	var r = TurnInput.current_round
	round_label.text = "Round %d of %d" % [r + 1, TurnInput.ROUNDS_PER_TURN]

	for i in range(_round_nav_btns.size()):
		_round_nav_btns[i].button_pressed = (i == r)

	hex_map.update_projected_positions(TurnInput.action_plan, r, GameState.robot_lookup)
	_rebuild_robot_status_list()

	if TurnInput.selected_robot_id != "":
		_show_adjacent_for_selected_robot()
	else:
		hex_map.clear_adjacent_highlights()

	_update_deploy_button()

# ==================== Robot Selection ====================

func _on_robot_selected(robot_id: String) -> void:
	hex_map.set_selected_robot(robot_id)

	if robot_id == "":
		hex_map.clear_adjacent_highlights()
		hint_label.text = ""
		_update_deploy_button()
		_rebuild_robot_status_list()
		return

	# Pan to the robot's projected position for the current round
	var r = TurnInput.current_round
	var proj_pos = TurnInput.get_projected_position(robot_id, r - 1)
	camera.position = HexMath.axial_to_pixel(
		Vector2i(int(proj_pos[0]), int(proj_pos[1])), HexMath.HEX_SIZE)

	_show_adjacent_for_selected_robot()
	_update_deploy_button()
	_rebuild_robot_status_list()

# Show green highlights on adjacent hexes the selected robot can move to.
func _show_adjacent_for_selected_robot() -> void:
	var robot_id = TurnInput.selected_robot_id
	if robot_id == "":
		hex_map.clear_adjacent_highlights()
		return

	var r = TurnInput.current_round
	var proj_pos = TurnInput.get_projected_position(robot_id, r - 1)
	var proj_hex = Vector2i(int(proj_pos[0]), int(proj_pos[1]))

	# If move limit is already reached and this round isn't already a move, no moves possible.
	var rounds = TurnInput.action_plan.get(robot_id, [])
	var this_round_is_move = (r < rounds.size() and rounds[r].get("action_type", "wait") == "move")
	var at_limit = TurnInput.count_moves_planned(robot_id) >= TurnInput.get_max_moves(robot_id)

	if at_limit and not this_round_is_move:
		hex_map.clear_adjacent_highlights()
		hint_label.text = "Move limit reached (%d/%d). Click robot to select, or choose another round." % [
			TurnInput.count_moves_planned(robot_id), TurnInput.get_max_moves(robot_id)]
		return

	var neighbors = HexMath.axial_neighbors(proj_hex)
	var valid: Array = []
	for n in neighbors:
		if hex_map.has_hex(n):
			valid.append(n)
	hex_map.highlight_adjacent_hexes(valid)

	if this_round_is_move:
		hint_label.text = "Click robot to clear move. Click another hex to change destination."
	else:
		hint_label.text = "Click a green hex to move. Click robot to skip (wait)."

# ==================== Robot Status Panel ====================

func _rebuild_robot_status_list() -> void:
	for child in robot_status_list.get_children():
		child.queue_free()

	var r = TurnInput.current_round

	for robot in GameState.player_robots:
		if robot.get("player_id", "") != GameState.player_id:
			continue
		var robot_id = robot.get("robot_id", "")
		var robot_type = robot.get("type", "?")
		var energy = robot.get("energy", 0)
		var state_str = robot.get("state", "active")
		var is_selected = (robot_id == TurnInput.selected_robot_id)

		var rounds = TurnInput.action_plan.get(robot_id, [])
		var round_data = rounds[r] if r < rounds.size() else {}
		var action_type = round_data.get("action_type", "wait")
		var has_deploy = round_data.get("deploy", null) != null

		var action_str: String
		if action_type == "move":
			var after = round_data.get("after_position", [0, 0])
			action_str = "→(%d,%d)" % [after[0], after[1]]
		else:
			action_str = "wait"
		if has_deploy:
			action_str += " [D]"
		if state_str == "stunned":
			action_str += " ☠"

		var used_moves = TurnInput.count_moves_planned(robot_id)
		var max_moves = TurnInput.get_max_moves(robot_id)

		var btn = Button.new()
		btn.text = "[%s] %s  E:%d  %d/%d mv" % [
			robot_type.substr(0, 1).to_upper(),
			action_str, energy, used_moves, max_moves
		]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.button_pressed = is_selected
		btn.custom_minimum_size = Vector2(0, 32)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_robot_status_pressed.bind(robot_id))
		robot_status_list.add_child(btn)

func _on_robot_status_pressed(robot_id: String) -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	if TurnInput.selected_robot_id == robot_id:
		TurnInput.select_robot("")
	else:
		TurnInput.select_robot(robot_id)

# ==================== Deploy Button ====================

func _update_deploy_button() -> void:
	var robot_id = TurnInput.selected_robot_id
	if robot_id == "":
		deploy_btn.disabled = true
		deploy_btn.text = "Deploy (select robot)"
		return

	var robot = GameState.robot_lookup.get(robot_id, {})
	var energy = robot.get("energy", 0)
	var deploy_type = TurnInput.ROBOT_STATS.get(robot.get("type", ""), {}).get("deploy_type", "")
	var r = TurnInput.current_round
	var rounds = TurnInput.action_plan.get(robot_id, [])
	var has_deploy = (r < rounds.size() and rounds[r].get("deploy", null) != null)

	if has_deploy:
		deploy_btn.disabled = false
		deploy_btn.text = "Clear Deploy (R%d)" % (r + 1)
	elif energy <= 0:
		deploy_btn.disabled = true
		deploy_btn.text = "Deploy %s (no energy)" % deploy_type
	else:
		deploy_btn.disabled = false
		deploy_btn.text = "Deploy %s on R%d" % [deploy_type, r + 1]

func _on_deploy_pressed() -> void:
	var robot_id = TurnInput.selected_robot_id
	if robot_id == "":
		return

	var r = TurnInput.current_round
	var rounds = TurnInput.action_plan.get(robot_id, [])

	# Toggle: clear existing deploy if present
	if r < rounds.size() and rounds[r].get("deploy", null) != null:
		TurnInput.clear_deploy_for_round(robot_id, r)
		return

	var robot = GameState.robot_lookup.get(robot_id, {})
	if robot.get("energy", 0) <= 0:
		return

	var deploy_type_local = TurnInput.ROBOT_STATS.get(robot.get("type", ""), {}).get("deploy_type", "")

	if deploy_type_local == "extra_moves":
		# No targeting needed — self-applied immediately
		TurnInput.start_deploy_targeting(robot_id, r)
		TurnInput.confirm_deploy_target([robot.get("position", [0, 0])])
		return

	var proj_pos = TurnInput.get_projected_position(robot_id, r - 1)
	var targets = TurnInput.get_valid_deploy_targets(robot_id, proj_pos)
	hex_map.highlight_hexes(targets, Color(0.8, 0.4, 1.0, 0.6))
	TurnInput.start_deploy_targeting(robot_id, r)
	hint_label.text = "Click a highlighted hex to deploy %s" % deploy_type_local

# ==================== Hex Click Handling ====================

func _on_hex_clicked(hex: Vector2i) -> void:
	match TurnInput.current_phase:
		TurnInput.Phase.INPUT:
			_handle_input_click(hex)
		TurnInput.Phase.DEPLOY_TARGETING:
			_handle_deploy_target(hex)

func _handle_input_click(hex: Vector2i) -> void:
	var robot_id = TurnInput.selected_robot_id
	var r = TurnInput.current_round

	# Check if the click lands on one of my robots at their projected position.
	var clicked_robot = _find_my_robot_at_projected_hex(hex, r)
	if clicked_robot != "":
		if clicked_robot == robot_id:
			# Re-clicking the selected robot clears its move for this round.
			TurnInput.clear_move_for_round(robot_id, r)
			_show_adjacent_for_selected_robot()
		else:
			TurnInput.select_robot(clicked_robot)
		return

	# Not a robot hex.
	if robot_id == "":
		return

	# Robot selected — check if hex is an adjacent valid move.
	var proj_pos = TurnInput.get_projected_position(robot_id, r - 1)
	var proj_hex = Vector2i(int(proj_pos[0]), int(proj_pos[1]))

	if HexMath.axial_distance(proj_hex, hex) == 1:
		_assign_move(robot_id, r, hex)
	else:
		# Click elsewhere deselects.
		TurnInput.select_robot("")

func _find_my_robot_at_projected_hex(hex: Vector2i, round_num: int) -> String:
	for robot in GameState.player_robots:
		if robot.get("player_id", "") != GameState.player_id:
			continue
		var robot_id = robot.get("robot_id", "")
		var proj = TurnInput.get_projected_position(robot_id, round_num - 1)
		if int(proj[0]) == hex.x and int(proj[1]) == hex.y:
			return robot_id
	return ""

func _assign_move(robot_id: String, round_num: int, dest_hex: Vector2i) -> void:
	var rounds = TurnInput.action_plan.get(robot_id, [])
	var current_action = rounds[round_num].get("action_type", "wait") if round_num < rounds.size() else "wait"

	# Check move limit when adding a new move (not when replacing existing).
	if current_action == "wait":
		if TurnInput.count_moves_planned(robot_id) >= TurnInput.get_max_moves(robot_id):
			hint_label.text = "Move limit reached — can't add more moves for this robot."
			return

	TurnInput.set_move_for_round(robot_id, round_num, [dest_hex.x, dest_hex.y])
	hint_label.text = ""

func _handle_deploy_target(hex: Vector2i) -> void:
	TurnInput.confirm_deploy_target([[hex.x, hex.y]])
	hex_map.clear_highlights()
	hint_label.text = ""

# ==================== Action Plan Changed ====================

func _on_action_plan_changed() -> void:
	var r = TurnInput.current_round
	hex_map.update_projected_positions(TurnInput.action_plan, r, GameState.robot_lookup)
	_rebuild_robot_status_list()
	_update_deploy_button()
	if TurnInput.selected_robot_id != "":
		_show_adjacent_for_selected_robot()

# ==================== Submit ====================

func _on_submit_pressed() -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return

	var errors = TurnInput.validate_plan()
	if errors.size() > 0:
		hint_label.text = errors[0]
		return

	var payload = TurnInput.build_submit_payload()
	TurnInput.set_phase(TurnInput.Phase.SUBMITTING)
	submit_btn.disabled = true
	input_timer.stop()
	timer_label.text = ""
	APIClient.submit_actions(GameState.game_id, GameState.current_turn, payload)

func _on_input_timer_expired() -> void:
	if TurnInput.current_phase == TurnInput.Phase.INPUT:
		_on_submit_pressed()

# ==================== Poll for Results ====================

func _on_moves_submitted(data: Dictionary) -> void:
	var errors = data.get("validation_errors", [])
	if errors.size() > 0:
		hint_label.text = "Server: " + errors[0]
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
		return

	poll_timer.stop()

	var winner = data.get("winner", null)
	var replay = data.get("replay", null)

	if replay != null:
		_play_replay(replay, data)
	else:
		GameState.apply_turn_results(data)
		if winner != null:
			_go_to_game_end(winner)
		else:
			_start_next_turn()

func _on_request_failed(endpoint: String, _status_code: int, body: String) -> void:
	if endpoint.contains("submit"):
		TurnInput.set_phase(TurnInput.Phase.INPUT)
		submit_btn.disabled = false
		hint_label.text = "Submit failed: %s" % body
	elif endpoint.contains("results"):
		pass  # Keep polling
	else:
		hint_label.text = "Error: %s" % body

# ==================== Replay Playback ====================

func _play_replay(replay: Dictionary, full_results: Dictionary) -> void:
	_show_overlay("Playing turn replay...")
	TurnInput.set_phase(TurnInput.Phase.REVIEWING)

	var rounds = replay.get("rounds", [])
	var hex_objects_created = replay.get("hex_objects_created", [])
	var hex_objects_destroyed = replay.get("hex_objects_destroyed", [])
	var winner = replay.get("winner", null)

	for round_idx in range(rounds.size()):
		var created_this_round: Array = []
		var destroyed_this_round: Array = []
		if round_idx == rounds.size() - 1:
			created_this_round = hex_objects_created
			destroyed_this_round = hex_objects_destroyed

		hex_map.animate_replay_round(rounds[round_idx], created_this_round, destroyed_this_round)
		await get_tree().create_timer(0.6).timeout

	await get_tree().create_timer(0.5).timeout

	_last_replay = replay
	GameState.apply_turn_results(full_results)
	_hide_overlay()

	if winner != null:
		_go_to_game_end(winner)
	else:
		replay_btn.disabled = false
		_start_next_turn()

func _replay_last_turn() -> void:
	if _last_replay.is_empty():
		return

	replay_btn.disabled = true
	submit_btn.disabled = true
	var saved_robot_id = TurnInput.selected_robot_id

	_show_overlay("Replaying turn...")
	hex_map.reset_for_replay(_last_replay)

	var rounds = _last_replay.get("rounds", [])
	var hex_objects_created = _last_replay.get("hex_objects_created", [])
	var hex_objects_destroyed = _last_replay.get("hex_objects_destroyed", [])
	for round_idx in range(rounds.size()):
		var created_this_round: Array = []
		var destroyed_this_round: Array = []
		if round_idx == rounds.size() - 1:
			created_this_round = hex_objects_created
			destroyed_this_round = hex_objects_destroyed
		hex_map.animate_replay_round(rounds[round_idx], created_this_round, destroyed_this_round)
		await get_tree().create_timer(0.6).timeout

	await get_tree().create_timer(0.5).timeout

	# Restore planning view for the current round
	hex_map.populate_from_game_state()
	_update_round_display()
	if saved_robot_id != "":
		hex_map.set_selected_robot(saved_robot_id)
		TurnInput.select_robot(saved_robot_id)

	_hide_overlay()
	replay_btn.disabled = false
	if TurnInput.current_phase == TurnInput.Phase.INPUT:
		submit_btn.disabled = false

# ==================== Next Turn / Game End ====================

func _start_next_turn() -> void:
	hex_map.populate_from_game_state()
	hex_map.set_selected_robot("")
	camera.position = hex_map.get_player_robots_centroid()
	_update_header()
	hint_label.text = ""
	TurnInput.start_input_phase()  # emits current_round_changed(0) → _update_round_display()

	var input_time = GameState.game_variables.get("input_time", 90)
	if input_time > 0:
		input_timer.wait_time = float(input_time)
		input_timer.start()

func _go_to_game_end(winner: int) -> void:
	GameState.game_state_str = "complete"
	GameState.initiative_team = winner
	get_tree().change_scene_to_file("res://scenes/game_end.tscn")

# ==================== Phase Changes ====================

func _on_phase_changed(new_phase: TurnInput.Phase) -> void:
	_update_header()
	match new_phase:
		TurnInput.Phase.INPUT:
			submit_btn.disabled = false
			_hide_overlay()
			hex_map.clear_highlights()
		TurnInput.Phase.DEPLOY_TARGETING:
			submit_btn.disabled = true
		TurnInput.Phase.SUBMITTING:
			submit_btn.disabled = true
		TurnInput.Phase.REVIEWING:
			submit_btn.disabled = true
			hex_map.clear_adjacent_highlights()
			hex_map.clear_highlights()
			hex_map.clear_path_highlights()
			hint_label.text = ""

func _on_robots_updated() -> void:
	_rebuild_robot_status_list()

# ==================== Overlay ====================

func _show_overlay(msg: String) -> void:
	status_overlay_label.text = msg
	status_overlay.visible = true

func _hide_overlay() -> void:
	status_overlay.visible = false
