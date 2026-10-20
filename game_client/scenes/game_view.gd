extends Node2D

# Main gameplay scene.
# Path-drawing input: select a robot, then click (or drag across) hexes to lay
# its path — each step fills the next round. The Timeline dock at the bottom
# shows every robot's six rounds for fine-tuning timing; clicking a cell aims
# the next map click at that round. Edits keep later steps; illegal steps are
# flagged red instead of deleted.

# ==================== Node References ====================

@onready var hex_map: HexMap = $HexMap
@onready var turn_label: Label = $UI/TopBar/TurnLabel
@onready var initiative_label: Label = $UI/TopBar/InitiativeLabel
@onready var phase_label: Label = $UI/TopBar/PhaseLabel
@onready var timer_label: Label = $UI/TopBar/TimerLabel
@onready var zoom_in_btn: Button = $UI/TopBar/ZoomInBtn
@onready var zoom_out_btn: Button = $UI/TopBar/ZoomOutBtn
@onready var timeline: PlanTimeline = $UI/Timeline
@onready var robot_card: Label = $UI/RightPanel/RightVBox/RobotCard
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

var _last_replay: Dictionary = {}
var _winner: int = -1

# Step context menu (right-click on a timeline cell or map step marker)
enum MenuItem { WAIT, INSERT_WAIT, DELETE_STEP, DEPLOY, CLEAR_DEPLOY, CLEAR_ROBOT }
var _step_menu: PopupMenu
var _menu_robot_id: String = ""
var _menu_round: int = -1

# Keyboard-chosen deploy target during DEPLOY_TARGETING.
var _deploy_focus: Vector2i = Vector2i.ZERO

# Set when Submit was pressed with flagged steps; a second press confirms.
var _confirm_submit: bool = false

# Camera pan state
var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_camera: Vector2 = Vector2.ZERO

# ==================== Ready ====================

func _ready() -> void:
	_step_menu = PopupMenu.new()
	_step_menu.id_pressed.connect(_on_step_menu_id_pressed)
	$UI.add_child(_step_menu)

	# Keep keyboard shortcuts (Space/Enter) from re-pressing focused buttons.
	for btn in [deploy_btn, submit_btn, replay_btn, zoom_in_btn, zoom_out_btn]:
		btn.focus_mode = Control.FOCUS_NONE

	# Signal connections
	hex_map.hex_clicked.connect(_on_hex_clicked)
	hex_map.hex_drag_entered.connect(_on_hex_drag_entered)
	hex_map.hex_hovered.connect(_on_hex_hovered)
	hex_map.hex_right_clicked.connect(_on_hex_right_clicked)
	timeline.cell_context_requested.connect(_open_step_menu)
	submit_btn.pressed.connect(_on_submit_pressed)
	deploy_btn.pressed.connect(_on_deploy_pressed)
	zoom_in_btn.pressed.connect(_on_zoom_in)
	zoom_out_btn.pressed.connect(_on_zoom_out)
	replay_btn.pressed.connect(_replay_last_turn)
	poll_timer.timeout.connect(_on_poll_timer)
	input_timer.timeout.connect(_on_input_timer_expired)

	TurnInput.phase_changed.connect(_on_phase_changed)
	TurnInput.view_round_changed.connect(_on_view_round_changed)
	TurnInput.robot_selected.connect(_on_robot_selected)
	TurnInput.action_plan_changed.connect(_on_action_plan_changed)

	APIClient.moves_submitted.connect(_on_moves_submitted)
	APIClient.results_received.connect(_on_results_received)
	APIClient.request_failed.connect(_on_request_failed)

	GameState.robots_updated.connect(_on_robots_updated)

	# Populate map first, then start input phase (which resets plans and
	# triggers _refresh_plan_view while sprites are ready).
	hex_map.populate_from_game_state()
	timeline.fit_to_content()
	_center_camera_on(hex_map.get_player_robots_centroid())
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

# Pan motion is tracked in _input so a drag keeps working over UI panels;
# presses and wheel go through _unhandled_input so UI clicks don't pan/zoom.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_is_panning = false
	elif event is InputEventMouseMotion and _is_panning:
		var delta_screen = event.position - _pan_start_mouse
		camera.position = _pan_start_camera - delta_screen / camera.zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	var btn = event.button_index
	if btn == MOUSE_BUTTON_MIDDLE or btn == MOUSE_BUTTON_RIGHT:
		_is_panning = true
		_pan_start_mouse = event.position
		_pan_start_camera = camera.position
		return
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

func _on_zoom_in() -> void:
	_apply_zoom(1.25)

func _on_zoom_out() -> void:
	_apply_zoom(1.0 / 1.25)

func _apply_zoom(factor: float) -> void:
	camera.zoom = (camera.zoom * factor).clamp(Vector2(0.2, 0.2), Vector2(5.0, 5.0))

# Screen area of the map not covered by the top bar, right panel or plan grid.
func _map_safe_screen_rect() -> Rect2:
	var vp = get_viewport_rect().size
	var top = $UI/TopBar.size.y
	var right = vp.x - $UI/RightPanel.size.x
	var bottom = vp.y
	if timeline.visible:
		bottom = timeline.position.y
	return Rect2(0, top, right, maxf(bottom - top, 1.0))

func _world_to_screen(world: Vector2) -> Vector2:
	return (world - camera.position) * camera.zoom + get_viewport_rect().size * 0.5

# Center a world point within the uncovered map area.
func _center_camera_on(world: Vector2) -> void:
	var offset = _map_safe_screen_rect().get_center() - get_viewport_rect().size * 0.5
	camera.position = world - offset / camera.zoom

# Pan only when the hex is hidden under a panel or off-screen, so selecting
# never yanks the view needlessly.
func _ensure_hex_visible(hex: Vector2i) -> void:
	var world = HexMath.axial_to_pixel(hex, HexMath.HEX_SIZE)
	var safe = _map_safe_screen_rect().grow(-HexMath.HEX_SIZE * camera.zoom.x)
	if not safe.has_point(_world_to_screen(world)):
		_center_camera_on(world)

# ==================== Keyboard ====================

# Q W E / A S D -> hex direction index (HexMath.AXIAL_DIRECTIONS, flat-top):
#  NW N NE / SW S SE
const MOVE_KEYS: Dictionary = {
	KEY_Q: 3, KEY_W: 2, KEY_E: 1,
	KEY_A: 4, KEY_S: 5, KEY_D: 0,
}
const PAN_KEYS: Dictionary = {
	KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT,
	KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN,
}

func _handle_key(event: InputEventKey) -> void:
	var key = event.keycode
	var modified = event.ctrl_pressed or event.meta_pressed or event.alt_pressed
	var handled = true

	# Keys that work in every phase
	if key == KEY_ESCAPE:
		_on_cancel()
	elif key in PAN_KEYS:
		camera.position += PAN_KEYS[key] * 96.0 / camera.zoom.x
	elif key == KEY_EQUAL or key == KEY_PLUS or key == KEY_KP_ADD:
		_on_zoom_in()
	elif key == KEY_MINUS or key == KEY_KP_SUBTRACT:
		_on_zoom_out()
	elif key == KEY_T:
		timeline.toggle_collapsed()
	elif key == KEY_R and not replay_btn.disabled:
		_replay_last_turn()
	elif TurnInput.current_phase == TurnInput.Phase.GAME_OVER and key in [KEY_ENTER, KEY_KP_ENTER]:
		if not submit_btn.disabled:
			_go_to_game_end(_winner)
	elif TurnInput.current_phase == TurnInput.Phase.DEPLOY_TARGETING:
		handled = _handle_deploy_key(event)
	elif TurnInput.current_phase == TurnInput.Phase.INPUT and (not modified or key == KEY_Z):
		handled = _handle_plan_key(event)
	else:
		handled = false

	if handled:
		get_viewport().set_input_as_handled()

# Planning keys (INPUT phase). Returns true if the key was used.
func _handle_plan_key(event: InputEventKey) -> bool:
	var key = event.keycode
	var robot_id = TurnInput.selected_robot_id

	match key:
		KEY_TAB:
			_cycle_robot(-1 if event.shift_pressed else 1)
			return true
		KEY_ENTER, KEY_KP_ENTER:
			_on_submit_pressed()
			return true
		KEY_0, KEY_QUOTELEFT:
			TurnInput.set_view_round(-1)
			return true
	if robot_id == "":
		if key in MOVE_KEYS or key in [KEY_SPACE, KEY_F, KEY_C, KEY_M]:
			hint_label.text = "Select a robot first (Tab)."
			return true
		return false

	var r = TurnInput.get_cursor(robot_id)
	if key in MOVE_KEYS:
		if r >= TurnInput.ROUNDS_PER_TURN:
			hint_label.text = "All 6 rounds planned. Press 1-6 to edit a round."
		else:
			var from_hex = TurnInput.get_projected_hex(robot_id, r - 1)
			_try_step_to(robot_id, from_hex + HexMath.AXIAL_DIRECTIONS[MOVE_KEYS[key]])
		return true

	match key:
		KEY_SPACE:
			if not TurnInput.add_wait_at_cursor(robot_id):
				hint_label.text = "All 6 rounds planned. Press 1-6 to edit a round."
		KEY_BACKSPACE:
			if event.shift_pressed:
				TurnInput.clear_robot(robot_id)
			else:
				TurnInput.undo_last(robot_id)
		KEY_Z:
			if not (event.ctrl_pressed or event.meta_pressed):
				return false
			TurnInput.undo_last(robot_id)
		KEY_DELETE, KEY_X:
			if r < TurnInput.get_steps(robot_id).size():
				TurnInput.delete_step(robot_id, r)
			else:
				hint_label.text = "No step at round %d to delete (Backspace undoes the last step)." % mini(r + 1, 6)
		KEY_I, KEY_INSERT:
			if not TurnInput.insert_wait(robot_id, mini(r, TurnInput.ROUNDS_PER_TURN - 1)):
				hint_label.text = "Round 6 already has a move or deploy — no room to shift."
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			_shift_step_timing(robot_id, -1 if key == KEY_BRACKETLEFT else 1)
		KEY_F:
			_on_deploy_pressed()
		KEY_C:
			_center_camera_on(HexMath.axial_to_pixel(
				TurnInput.get_projected_hex(robot_id, r - 1), HexMath.HEX_SIZE))
		KEY_M, KEY_MENU:
			var rr = mini(r, TurnInput.ROUNDS_PER_TURN - 1)
			var screen = _world_to_screen(HexMath.axial_to_pixel(
				TurnInput.get_projected_hex(robot_id, rr - 1), HexMath.HEX_SIZE))
			_open_step_menu(robot_id, rr, screen)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			var round_num = key - KEY_1
			TurnInput.set_cursor(robot_id, round_num)
			TurnInput.set_view_round(round_num)
		_:
			return false
	return true

# [ / ] : move the step at the cursor one round earlier/later (swap with its
# neighbour) and keep the cursor on it.
func _shift_step_timing(robot_id: String, direction: int) -> void:
	var r = TurnInput.get_cursor(robot_id)
	if r >= TurnInput.ROUNDS_PER_TURN:
		r = TurnInput.get_steps(robot_id).size() - 1  # at the end: act on the last step
	var target = r + direction
	if r < 0 or target < 0 or target >= TurnInput.ROUNDS_PER_TURN:
		return
	TurnInput.swap_steps(robot_id, r, target)
	TurnInput.set_cursor(robot_id, target)
	TurnInput.set_view_round(target)

# Deploy targeting keys: Q/W/E/A/S/D move the target, Tab cycles through valid
# targets, Enter / Space / F confirms.
func _handle_deploy_key(event: InputEventKey) -> bool:
	var key = event.keycode
	var robot_id = TurnInput.deploy_target_robot_id
	var from_hex = TurnInput.get_projected_hex(robot_id, TurnInput.deploy_round - 1)
	var targets = TurnInput.get_valid_deploy_targets(robot_id, from_hex)
	if key in MOVE_KEYS:
		_set_deploy_focus(_deploy_focus + HexMath.AXIAL_DIRECTIONS[MOVE_KEYS[key]])
	elif key == KEY_TAB:
		var idx = targets.find(_deploy_focus)
		idx = posmod(idx + (-1 if event.shift_pressed else 1), targets.size())
		_set_deploy_focus(targets[idx])
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_F]:
		_handle_deploy_target(_deploy_focus)
	else:
		return false
	return true

func _set_deploy_focus(hex: Vector2i) -> void:
	_deploy_focus = hex
	hex_map.set_focus_hex(hex)
	_ensure_hex_visible(hex)

func _cycle_robot(direction: int) -> void:
	var ids = TurnInput.get_my_robot_ids()
	if ids.is_empty():
		return
	var idx = ids.find(TurnInput.selected_robot_id)
	if idx < 0:
		idx = 0 if direction > 0 else ids.size() - 1
	else:
		idx = posmod(idx + direction, ids.size())
	TurnInput.select_robot(ids[idx])

func _on_cancel() -> void:
	_step_menu.hide()
	if TurnInput.current_phase == TurnInput.Phase.DEPLOY_TARGETING:
		TurnInput.cancel_deploy_targeting()
		hint_label.text = "Deploy cancelled."
	elif TurnInput.current_phase == TurnInput.Phase.INPUT:
		TurnInput.select_robot("")

# ==================== Header ====================

func _update_header() -> void:
	turn_label.text = "Turn %d" % (GameState.current_turn + 1)
	if TurnInput.current_phase == TurnInput.Phase.GAME_OVER:
		# Turn results already advanced current_turn past the final turn
		turn_label.text = "Turn %d (final)" % GameState.current_turn
	initiative_label.text = "Initiative: Team %d" % GameState.initiative_team
	var phase_name = TurnInput.Phase.keys()[TurnInput.current_phase]
	phase_label.text = "Phase: " + phase_name

# ==================== Plan View ====================

func _on_view_round_changed(_round_num: int) -> void:
	_refresh_plan_view()

func _on_action_plan_changed() -> void:
	_confirm_submit = false
	_refresh_plan_view()

func _on_robots_updated() -> void:
	_refresh_plan_view()

# Redraw paths/sprites, next-step highlights, the robot card and deploy button.
func _refresh_plan_view() -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT \
			and TurnInput.current_phase != TurnInput.Phase.DEPLOY_TARGETING:
		return
	hex_map.update_plan_display(TurnInput.selected_robot_id, TurnInput.view_round)
	hex_map.clear_hover_route()
	_show_next_step_highlights()
	_update_robot_card()
	_update_deploy_button()

# Green highlights on passable hexes the selected robot can step to from its
# position entering the cursor round.
func _show_next_step_highlights() -> void:
	var robot_id = TurnInput.selected_robot_id
	if robot_id == "" or TurnInput.current_phase != TurnInput.Phase.INPUT:
		hex_map.clear_adjacent_highlights()
		return
	var r = TurnInput.get_cursor(robot_id)
	if r >= TurnInput.ROUNDS_PER_TURN or _moves_left_at_cursor(robot_id) <= 0:
		hex_map.clear_adjacent_highlights()
		return
	var from_hex = TurnInput.get_projected_hex(robot_id, r - 1)
	var valid: Array = []
	for n in HexMath.axial_neighbors(from_hex):
		if TurnInput.is_hex_passable(n):
			valid.append(n)
	hex_map.highlight_adjacent_hexes(valid)

# Moves still available when writing at the cursor (a move already at the
# cursor can be replaced, so it doesn't count against the budget).
func _moves_left_at_cursor(robot_id: String) -> int:
	var r = TurnInput.get_cursor(robot_id)
	var replacing = TurnInput.is_move_step(TurnInput.get_step(robot_id, r))
	return TurnInput.get_max_moves(robot_id) - TurnInput.count_moves_planned(robot_id) \
		+ (1 if replacing else 0)

func _update_robot_card() -> void:
	var robot_id = TurnInput.selected_robot_id
	if robot_id == "":
		robot_card.text = "No robot selected\nClick one of your robots, its timeline row, or press Tab."
		return
	var robot = GameState.robot_lookup.get(robot_id, {})
	var rtype = robot.get("type", "robot")
	var max_energy = TurnInput.ROBOT_STATS.get(rtype, {}).get("max_energy", 0)
	var r = TurnInput.get_cursor(robot_id)
	var lines: Array = [
		"%s%s" % [rtype.capitalize(), "  (STUNNED)" if robot.get("state", "") == "stunned" else ""],
		"Moves: %d of %d used" % [TurnInput.count_moves_planned(robot_id), TurnInput.get_max_moves(robot_id)],
		"Energy: %d/%d" % [int(robot.get("energy", 0)), max_energy],
	]
	if r >= TurnInput.ROUNDS_PER_TURN:
		lines.append("All 6 rounds planned.")
	else:
		lines.append("Next click / move key sets round %d." % (r + 1))
	var issues = TurnInput.get_step_issues(robot_id)
	for round_num in issues.keys():
		lines.append("! R%d: %s" % [round_num + 1, issues[round_num]])
	var warnings = TurnInput.get_firewall_warnings(robot_id)
	for round_num in warnings.keys():
		lines.append("! R%d: %s" % [round_num + 1, warnings[round_num]])
	robot_card.text = "\n".join(lines)

# ==================== Robot Selection ====================

func _on_robot_selected(robot_id: String) -> void:
	hex_map.set_selected_robot(robot_id)
	hint_label.text = ""
	if robot_id != "":
		_ensure_hex_visible(TurnInput.get_projected_hex(robot_id, TurnInput.get_cursor(robot_id) - 1))
	_refresh_plan_view()

# Own robot whose sprite or path-end ghost sits on hex, preferring the
# currently selected robot's ghost so clicking it continues the path.
func _find_my_robot_at_hex(hex: Vector2i) -> String:
	for robot_id in TurnInput.get_my_robot_ids():
		if TurnInput.get_projected_hex(robot_id, TurnInput.view_round - 1) == hex:
			return robot_id
	for robot_id in TurnInput.get_my_robot_ids():
		if TurnInput.get_start_hex(robot_id) == hex or TurnInput.get_path_tip(robot_id) == hex:
			return robot_id
	return ""

# ==================== Deploy ====================

func _update_deploy_button() -> void:
	var robot_id = TurnInput.selected_robot_id
	if robot_id == "":
		deploy_btn.disabled = true
		deploy_btn.text = "Deploy (select robot)"
		return

	var robot = GameState.robot_lookup.get(robot_id, {})
	var deploy_type = TurnInput.get_deploy_type(robot_id)
	var r = mini(TurnInput.get_cursor(robot_id), TurnInput.ROUNDS_PER_TURN - 1)

	if TurnInput.has_deploy(robot_id, r):
		deploy_btn.disabled = false
		deploy_btn.text = "Clear Deploy (R%d)  [F]" % (r + 1)
	elif deploy_type == "leap" and TurnInput.count_leaps_planned(robot_id) >= TurnInput.LEAPS_PER_TURN:
		deploy_btn.disabled = true
		deploy_btn.text = "Leap used this turn"
	elif int(robot.get("energy", 0)) <= 0:
		deploy_btn.disabled = true
		deploy_btn.text = "Deploy %s (no energy)" % deploy_type
	else:
		deploy_btn.disabled = false
		deploy_btn.text = "Deploy %s on R%d  [F]" % [deploy_type, r + 1]

func _on_deploy_pressed() -> void:
	var robot_id = TurnInput.selected_robot_id
	if robot_id == "" or TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	_start_deploy(robot_id, mini(TurnInput.get_cursor(robot_id), TurnInput.ROUNDS_PER_TURN - 1))

# Toggle a deploy on round_num: clear an existing one, or enter targeting.
func _start_deploy(robot_id: String, round_num: int) -> void:
	if TurnInput.has_deploy(robot_id, round_num):
		TurnInput.clear_deploy(robot_id, round_num)
		return

	var robot = GameState.robot_lookup.get(robot_id, {})
	if int(robot.get("energy", 0)) <= 0:
		hint_label.text = "No energy left for a deploy."
		return

	var from_hex = TurnInput.get_projected_hex(robot_id, round_num - 1)
	var deploy_type_local = TurnInput.get_deploy_type(robot_id)
	if deploy_type_local == "leap":
		if TurnInput.count_leaps_planned(robot_id) >= TurnInput.LEAPS_PER_TURN:
			hint_label.text = "A Scout can leap once per turn. Clear the other leap first."
			return
		if _moves_left_at_cursor(robot_id) <= 0 and round_num == TurnInput.get_cursor(robot_id):
			hint_label.text = "No moves left this turn; a leap uses one."
			return

	var targets = TurnInput.get_valid_deploy_targets(robot_id, from_hex)
	if targets.is_empty():
		hint_label.text = "Nowhere to %s from here." % deploy_type_local
		return
	TurnInput.set_view_round(round_num)
	hex_map.highlight_hexes(targets, Color(0.8, 0.4, 1.0, 0.6))
	TurnInput.start_deploy_targeting(robot_id, round_num)
	_set_deploy_focus(targets[0])
	hint_label.text = "R%d: click a purple hex to deploy %s, or move the white outline with QWEASD / Tab and press Enter. Esc cancels." % [
		round_num + 1, deploy_type_local]

# ==================== Hex Input ====================

func _on_hex_clicked(hex: Vector2i) -> void:
	match TurnInput.current_phase:
		TurnInput.Phase.INPUT:
			_handle_input_click(hex)
		TurnInput.Phase.DEPLOY_TARGETING:
			_handle_deploy_target(hex)

func _handle_input_click(hex: Vector2i) -> void:
	var robot_id = TurnInput.selected_robot_id

	var clicked_robot = _find_my_robot_at_hex(hex)
	if clicked_robot != "" and clicked_robot != robot_id:
		TurnInput.select_robot(clicked_robot)
		return

	if robot_id == "":
		hint_label.text = "Select one of your robots first (click it, or press Tab)."
		return

	_try_step_to(robot_id, hex)

# Painting: dragging with the left button held adds one step per hex entered.
func _on_hex_drag_entered(hex: Vector2i) -> void:
	var robot_id = TurnInput.selected_robot_id
	if TurnInput.current_phase != TurnInput.Phase.INPUT or robot_id == "":
		return
	var r = TurnInput.get_cursor(robot_id)
	if HexMath.axial_distance(TurnInput.get_projected_hex(robot_id, r - 1), hex) == 1:
		_try_step_to(robot_id, hex)

# Add a step (adjacent hex) or an auto-routed path (farther hex) at the cursor.
func _try_step_to(robot_id: String, hex: Vector2i) -> void:
	var r = TurnInput.get_cursor(robot_id)
	if r >= TurnInput.ROUNDS_PER_TURN:
		hint_label.text = "All 6 rounds planned. Click a timeline cell (or 1-6) to edit a round."
		return
	var from_hex = TurnInput.get_projected_hex(robot_id, r - 1)
	if hex == from_hex:
		# Clicking the robot / path tip itself: nothing to do.
		return
	if _moves_left_at_cursor(robot_id) <= 0:
		hint_label.text = "No moves left (%d max). Space adds a wait." % TurnInput.get_max_moves(robot_id)
		return
	if HexMath.axial_distance(from_hex, hex) == 1:
		if not TurnInput.is_hex_passable(hex):
			hint_label.text = "That hex is blocked."
			return
		TurnInput.add_move_at_cursor(robot_id, hex)
		hint_label.text = ""
		return
	var route = TurnInput.find_route(robot_id, hex)
	if route.is_empty() or not TurnInput.add_route_at_cursor(robot_id, route):
		hint_label.text = "Can't reach that hex with the moves and rounds left."
	else:
		hint_label.text = ""

func _on_hex_hovered(hex: Vector2i) -> void:
	var robot_id = TurnInput.selected_robot_id
	if TurnInput.current_phase != TurnInput.Phase.INPUT or robot_id == "":
		hex_map.clear_hover_route()
		return
	var r = TurnInput.get_cursor(robot_id)
	if r >= TurnInput.ROUNDS_PER_TURN:
		hex_map.clear_hover_route()
		return
	var from_hex = TurnInput.get_projected_hex(robot_id, r - 1)
	if hex == from_hex:
		hex_map.clear_hover_route()
		return
	var route = TurnInput.find_route(robot_id, hex)
	if route.is_empty():
		hex_map.set_hover_route([from_hex, hex], false)
	else:
		hex_map.set_hover_route([from_hex] + route, true)

func _on_hex_right_clicked(hex: Vector2i, screen_pos: Vector2) -> void:
	if TurnInput.current_phase == TurnInput.Phase.DEPLOY_TARGETING:
		_on_cancel()
		return
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	# Open the step menu for the selected robot's step that ends on this hex
	# (latest one if several), else for whichever own robot's step does.
	var candidates = TurnInput.get_my_robot_ids()
	var sel = TurnInput.selected_robot_id
	if sel != "":
		candidates.erase(sel)
		candidates.push_front(sel)
	for robot_id in candidates:
		for r in range(TurnInput.get_steps(robot_id).size() - 1, -1, -1):
			if TurnInput.get_projected_hex(robot_id, r) == hex:
				_open_step_menu(robot_id, r, screen_pos)
				return

func _handle_deploy_target(hex: Vector2i) -> void:
	var robot_id = TurnInput.deploy_target_robot_id
	var from_hex = TurnInput.get_projected_hex(robot_id, TurnInput.deploy_round - 1)
	if not hex in TurnInput.get_valid_deploy_targets(robot_id, from_hex):
		hint_label.text = "Pick one of the purple hexes (Esc cancels)."
		return
	TurnInput.confirm_deploy_target(hex)
	hex_map.clear_highlights()
	hint_label.text = ""

# ==================== Step Menu ====================

func _open_step_menu(robot_id: String, round_num: int, screen_pos: Vector2) -> void:
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	if TurnInput.selected_robot_id != robot_id:
		TurnInput.select_robot(robot_id)
	_menu_robot_id = robot_id
	_menu_round = round_num

	var step = TurnInput.get_step(robot_id, round_num)
	var has_step = round_num < TurnInput.get_steps(robot_id).size()
	var robot = GameState.robot_lookup.get(robot_id, {})

	_step_menu.clear()
	_step_menu.add_separator("Round %d" % (round_num + 1))
	if TurnInput.is_move_step(step) or not has_step:
		_step_menu.add_item("Wait this round", MenuItem.WAIT)
	_step_menu.add_item("Insert wait before (shift later steps)", MenuItem.INSERT_WAIT)
	if has_step:
		_step_menu.add_item("Delete step (pull later steps earlier)", MenuItem.DELETE_STEP)
	if TurnInput.has_deploy(robot_id, round_num):
		_step_menu.add_item("Clear deploy", MenuItem.CLEAR_DEPLOY)
	elif int(robot.get("energy", 0)) > 0:
		_step_menu.add_item("Deploy %s here" % TurnInput.get_deploy_type(robot_id), MenuItem.DEPLOY)
	_step_menu.add_separator()
	_step_menu.add_item("Clear this robot's plan", MenuItem.CLEAR_ROBOT)
	_step_menu.position = Vector2i(screen_pos)
	_step_menu.reset_size()
	_step_menu.popup()

func _on_step_menu_id_pressed(id: int) -> void:
	var robot_id = _menu_robot_id
	var r = _menu_round
	if robot_id == "" or TurnInput.current_phase != TurnInput.Phase.INPUT:
		return
	match id:
		MenuItem.WAIT:
			TurnInput.set_wait(robot_id, r)
		MenuItem.INSERT_WAIT:
			if not TurnInput.insert_wait(robot_id, r):
				hint_label.text = "Round 6 already has a move or deploy — no room to shift."
		MenuItem.DELETE_STEP:
			TurnInput.delete_step(robot_id, r)
		MenuItem.DEPLOY:
			_start_deploy(robot_id, r)
		MenuItem.CLEAR_DEPLOY:
			TurnInput.clear_deploy(robot_id, r)
		MenuItem.CLEAR_ROBOT:
			TurnInput.clear_robot(robot_id)

# ==================== Submit ====================

func _on_submit_pressed() -> void:
	if TurnInput.current_phase == TurnInput.Phase.GAME_OVER:
		_go_to_game_end(_winner)
		return
	if TurnInput.current_phase != TurnInput.Phase.INPUT:
		return

	var errors = TurnInput.validate_plan()
	if errors.size() > 0 and not _confirm_submit:
		_confirm_submit = true
		hint_label.text = "%d step(s) can't be carried out and will be sent as waits (e.g. %s). Press Submit again to send anyway." % [
			errors.size(), errors[0]]
		return
	_confirm_submit = false

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
	TurnInput.set_phase(TurnInput.Phase.REVIEWING)
	var winner = replay.get("winner", null)
	if winner != null:
		# The overlay would sit right on top of the capture, so narrate in the hint instead
		hint_label.text = "Final turn: watch the Captain..."
		_focus_on_capture(replay)
	else:
		_show_overlay("Playing turn replay...")

	await _animate_replay(replay)
	await get_tree().create_timer(0.5).timeout

	_last_replay = replay
	GameState.apply_turn_results(full_results)
	_hide_overlay()

	if winner != null:
		_show_game_over(winner)
	else:
		replay_btn.disabled = false
		_start_next_turn()

# Animate a turn's rounds, stopping at the capture round if the game ended.
func _animate_replay(replay: Dictionary) -> void:
	var rounds = replay.get("rounds", [])
	var hex_objects_created = replay.get("hex_objects_created", [])
	var hex_objects_destroyed = replay.get("hex_objects_destroyed", [])
	var capture = replay.get("capture", null)
	var last_round = rounds.size() - 1
	if capture is Dictionary:
		last_round = mini(int(capture.get("round", last_round)), last_round)

	for round_idx in range(last_round + 1):
		var created_this_round: Array = []
		var destroyed_this_round: Array = []
		if round_idx == last_round:
			created_this_round = hex_objects_created
			destroyed_this_round = hex_objects_destroyed
		hex_map.animate_replay_round(rounds[round_idx], created_this_round, destroyed_this_round)
		await get_tree().create_timer(0.6).timeout

	if capture is Dictionary:
		var pos = capture.get("position", [0, 0])
		hex_map.show_capture(Vector2i(int(pos[0]), int(pos[1])))
		await get_tree().create_timer(1.0).timeout

# Center the camera on the captured Captain so the final replay plays out in view.
func _focus_on_capture(replay: Dictionary) -> void:
	var capture = replay.get("capture", null)
	if not capture is Dictionary:
		return
	var pos = capture.get("position", [0, 0])
	if camera.zoom.x < 1.0:
		camera.zoom = Vector2.ONE
	_center_camera_on(HexMath.axial_to_pixel(Vector2i(int(pos[0]), int(pos[1])), HexMath.HEX_SIZE))

func _replay_last_turn() -> void:
	if _last_replay.is_empty():
		return

	replay_btn.disabled = true
	submit_btn.disabled = true
	var saved_robot_id = TurnInput.selected_robot_id

	var game_over = TurnInput.current_phase == TurnInput.Phase.GAME_OVER
	if game_over:
		_focus_on_capture(_last_replay)
	else:
		_show_overlay("Replaying turn...")
	hex_map.reset_for_replay(_last_replay)

	await _animate_replay(_last_replay)
	await get_tree().create_timer(0.5).timeout

	if game_over:
		# Leave the final position on screen, with the capture marked
		_hide_overlay()
		replay_btn.disabled = false
		submit_btn.disabled = false
		return

	# Restore planning view
	hex_map.populate_from_game_state()
	if saved_robot_id != "":
		TurnInput.select_robot(saved_robot_id)
	else:
		_refresh_plan_view()

	_hide_overlay()
	replay_btn.disabled = false
	if TurnInput.current_phase == TurnInput.Phase.INPUT:
		submit_btn.disabled = false

# ==================== Next Turn / Game End ====================

func _start_next_turn() -> void:
	hex_map.populate_from_game_state()
	hex_map.set_selected_robot("")
	_center_camera_on(hex_map.get_player_robots_centroid())
	_update_header()
	hint_label.text = ""
	TurnInput.start_input_phase()  # resets plans, emits view_round_changed → _refresh_plan_view()

	var input_time = GameState.game_variables.get("input_time", 90)
	if input_time > 0:
		input_timer.wait_time = float(input_time)
		input_timer.start()

# Stay on the map after the final replay so players can see (and re-watch) the
# capture; Submit becomes End Game.
func _show_game_over(winner: int) -> void:
	_winner = winner
	TurnInput.set_phase(TurnInput.Phase.GAME_OVER)
	input_timer.stop()
	timer_label.text = ""
	var outcome = "You win!" if winner == GameState.player_team else "You lose."
	hint_label.text = "Team %d captured the Captain. %s Press Replay Last Turn [R] to watch again, or End Game [Enter] for the results." % [
		winner, outcome]

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
			_refresh_plan_view()
		TurnInput.Phase.DEPLOY_TARGETING:
			submit_btn.disabled = true
			hex_map.clear_adjacent_highlights()
		TurnInput.Phase.SUBMITTING:
			submit_btn.disabled = true
		TurnInput.Phase.GAME_OVER:
			submit_btn.text = "End Game  [Enter]"
			submit_btn.disabled = false
			deploy_btn.disabled = true
			replay_btn.disabled = false
		TurnInput.Phase.REVIEWING:
			submit_btn.disabled = true
			hex_map.clear_adjacent_highlights()
			hex_map.clear_highlights()
			hex_map.clear_path_highlights()
			hint_label.text = ""

# ==================== Overlay ====================

func _show_overlay(msg: String) -> void:
	status_overlay_label.text = msg
	status_overlay.visible = true

func _hide_overlay() -> void:
	status_overlay.visible = false
