extends Node

# Action planning state for the current turn.
# Each robot's plan is a sequence of up to 6 relative steps (move in a hex
# direction, or wait). Steps are relative so editing an early step translates
# the rest of the path instead of breaking it; steps that become illegal are
# flagged by get_step_issues() rather than deleted.

enum Phase {
	WAITING,          # Not our turn yet / waiting for game to start
	INPUT,            # Planning actions
	DEPLOY_TARGETING, # Selecting target hex for a deploy action
	SUBMITTING,       # Waiting for submit response
	REVIEWING,        # Watching replay
	GAME_OVER         # Game ended
}

const ROUNDS_PER_TURN: int = 6
const EMP_RADIUS: int = 3
const LEAP_MIN: int = 2
const LEAP_MAX: int = 3
const LEAPS_PER_TURN: int = 1

# ==================== State ====================

var current_phase: Phase = Phase.WAITING
var selected_robot_id: String = ""

# Round the board is scrubbed to (robots drawn at their projected position
# entering this round). -1 = show robots at turn start with full paths.
var view_round: int = -1

# plans: robot_id -> {"steps": Array, "deploys": Dictionary}
#   steps:   up to ROUNDS_PER_TURN entries, {"type": "move", "dir": 0..5}
#            (index into HexMath.AXIAL_DIRECTIONS), {"type": "wait"}, or a
#            Scout's {"type": "leap", "offset": Vector2i} (2-3 hexes, costs a
#            move and an energy). Rounds at or beyond steps.size() are implicit waits.
#   deploys: round_idx -> {"type": String, "offset": Vector2i}, target hex
#            relative to the robot's position at the start of that round.
var plans: Dictionary = {}

# robot_id -> round index the next map click writes to.
var cursor_round: Dictionary = {}

# Vector2i -> bool, built lazily from GameState.map_data; reset each turn.
var _passable_cache: Dictionary = {}

# Deploy targeting state
var deploy_target_robot_id: String = ""
var deploy_type: String = ""
var deploy_round: int = -1

# ==================== Signals ====================

signal phase_changed(new_phase: Phase)
signal view_round_changed(round_num: int)
signal robot_selected(robot_id: String)
signal action_plan_changed()

# ==================== Constants ====================

# Robot type stats matching backend ROBOT_TYPE_STATS
const ROBOT_STATS: Dictionary = {
	"captain":  {"moves_per_turn": 3, "max_energy": 2, "deploy_type": "emp",         "sight_range": 5, "strength": 7},
	"scout":    {"moves_per_turn": 4, "max_energy": 6, "deploy_type": "leap",        "sight_range": 7, "strength": 3},
	"defender": {"moves_per_turn": 2, "max_energy": 3, "deploy_type": "firewall",    "sight_range": 3, "strength": 5},
	"engineer": {"moves_per_turn": 6, "max_energy": 3, "deploy_type": "supply_drop", "sight_range": 5, "strength": 0},
}

# ==================== Phase Control ====================

func set_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_changed.emit(new_phase)

func start_input_phase() -> void:
	_initialize_plans()
	selected_robot_id = ""
	set_view_round(-1)
	set_phase(Phase.INPUT)

func set_view_round(n: int) -> void:
	view_round = clampi(n, -1, ROUNDS_PER_TURN - 1)
	view_round_changed.emit(view_round)

func start_deploy_targeting(robot_id: String, round_num: int) -> void:
	deploy_target_robot_id = robot_id
	deploy_round = round_num
	deploy_type = get_deploy_type(robot_id)
	set_phase(Phase.DEPLOY_TARGETING)

func cancel_deploy_targeting() -> void:
	deploy_target_robot_id = ""
	deploy_type = ""
	deploy_round = -1
	set_phase(Phase.INPUT)

func confirm_deploy_target(target_hex: Vector2i) -> void:
	if deploy_target_robot_id == "" or deploy_round < 0:
		return
	if deploy_type == "leap":
		set_leap(deploy_target_robot_id, deploy_round, target_hex)
	else:
		set_deploy(deploy_target_robot_id, deploy_round, target_hex)
	cancel_deploy_targeting()

# ==================== Robot Selection ====================

func select_robot(robot_id: String) -> void:
	selected_robot_id = robot_id
	robot_selected.emit(robot_id)

func get_selected_robot() -> Dictionary:
	return GameState.robot_lookup.get(selected_robot_id, {})

# Robot ids this player controls, in display order.
func get_my_robot_ids() -> Array:
	var ids: Array = []
	for robot in GameState.player_robots:
		if robot.get("player_id", "") == GameState.player_id:
			ids.append(robot.get("robot_id", ""))
	return ids

func get_deploy_type(robot_id: String) -> String:
	var robot = GameState.robot_lookup.get(robot_id, {})
	return ROBOT_STATS.get(robot.get("type", ""), {}).get("deploy_type", "")

# ==================== Plan Queries ====================

func _initialize_plans() -> void:
	plans.clear()
	cursor_round.clear()
	_passable_cache.clear()
	for robot_id in get_my_robot_ids():
		plans[robot_id] = {"steps": [], "deploys": {}}
		cursor_round[robot_id] = 0

func get_steps(robot_id: String) -> Array:
	return plans.get(robot_id, {}).get("steps", [])

func get_deploys(robot_id: String) -> Dictionary:
	return plans.get(robot_id, {}).get("deploys", {})

# Returns the step for a round, or an implicit wait past the end of the plan.
func get_step(robot_id: String, round_num: int) -> Dictionary:
	var steps = get_steps(robot_id)
	if round_num < steps.size():
		return steps[round_num]
	return {"type": "wait"}

func get_start_hex(robot_id: String) -> Vector2i:
	var pos = GameState.robot_lookup.get(robot_id, {}).get("position", [0, 0])
	return Vector2i(int(pos[0]), int(pos[1]))

# Moves and leaps both change hex and count toward the move limit.
static func is_move_step(step: Dictionary) -> bool:
	return step.get("type", "wait") in ["move", "leap"]

# How far a step moves the robot (zero for a wait).
static func step_offset(step: Dictionary) -> Vector2i:
	match step.get("type", "wait"):
		"move":
			return HexMath.AXIAL_DIRECTIONS[step["dir"]]
		"leap":
			return step["offset"]
	return Vector2i.ZERO

# Hex the robot occupies after rounds 0..after_round (-1 = turn start).
func get_projected_hex(robot_id: String, after_round: int) -> Vector2i:
	var hex = get_start_hex(robot_id)
	var steps = get_steps(robot_id)
	for i in range(mini(after_round + 1, steps.size())):
		hex += step_offset(steps[i])
	return hex

# Array form of get_projected_hex for callers that work with [q, r].
func get_projected_position(robot_id: String, after_round: int) -> Array:
	var hex = get_projected_hex(robot_id, after_round)
	return [hex.x, hex.y]

# Hex at the end of the planned steps (where the next appended step starts).
func get_path_tip(robot_id: String) -> Vector2i:
	return get_projected_hex(robot_id, get_steps(robot_id).size() - 1)

func get_cursor(robot_id: String) -> int:
	return cursor_round.get(robot_id, get_steps(robot_id).size())

func set_cursor(robot_id: String, round_num: int) -> void:
	cursor_round[robot_id] = clampi(round_num, 0, ROUNDS_PER_TURN)
	action_plan_changed.emit()

func get_max_moves(robot_id: String) -> int:
	var robot = GameState.robot_lookup.get(robot_id, {})
	if robot.get("state", "active") == "stunned":
		return 0
	var robot_type = robot.get("type", "captain")
	return ROBOT_STATS.get(robot_type, {}).get("moves_per_turn", 3)

func count_moves_planned(robot_id: String) -> int:
	var count = 0
	for step in get_steps(robot_id):
		if is_move_step(step):
			count += 1
	return count

func count_leaps_planned(robot_id: String) -> int:
	var count = 0
	for step in get_steps(robot_id):
		if step.get("type", "wait") == "leap":
			count += 1
	return count

func is_hex_passable(hex: Vector2i) -> bool:
	if _passable_cache.is_empty():
		for hex_data in GameState.map_data.get("hexes", []):
			var coord = Vector2i(int(hex_data.get("q", 0)), int(hex_data.get("r", 0)))
			_passable_cache[coord] = hex_data.get("passable", true)
	return _passable_cache.get(hex, false)  # Off the map = obstructed (matches backend is_hex_obstructed)

static func direction_between(from_hex: Vector2i, to_hex: Vector2i) -> int:
	return HexMath.AXIAL_DIRECTIONS.find(to_hex - from_hex)

# Round index -> human-readable problem, for every step that would be
# rejected or misbehave. Empty when the plan is clean.
func get_step_issues(robot_id: String) -> Dictionary:
	var issues: Dictionary = {}
	var robot = GameState.robot_lookup.get(robot_id, {})
	var max_moves = get_max_moves(robot_id)
	var moves_seen = 0
	var hex = get_start_hex(robot_id)
	var steps = get_steps(robot_id)
	var deploys = get_deploys(robot_id)
	var energy_left = int(robot.get("energy", 0))
	var leaps_seen = 0

	for i in range(ROUNDS_PER_TURN):
		if i < steps.size() and steps[i].get("type", "wait") == "leap":
			moves_seen += 1
			leaps_seen += 1
			energy_left -= 1
			var landing = hex + steps[i]["offset"]
			if moves_seen > max_moves:
				issues[i] = "Over move limit (%d max)" % max_moves
			elif leaps_seen > LEAPS_PER_TURN:
				issues[i] = "Only one leap per turn"
			elif energy_left < 0:
				issues[i] = "Not enough energy to leap"
			elif not is_hex_passable(landing):
				issues[i] = "Can't land on water, forest or off the map"
			hex = landing
			continue

		if i in deploys:
			energy_left -= 1
			if energy_left < 0:
				issues[i] = "Not enough energy for this deploy"
			else:
				var target = hex + deploys[i]["offset"]
				if not target in get_valid_deploy_targets(robot_id, hex):
					issues[i] = "Deploy target out of range from here"

		if i < steps.size() and steps[i].get("type", "wait") == "move":
			moves_seen += 1
			var next_hex = hex + HexMath.AXIAL_DIRECTIONS[steps[i]["dir"]]
			if moves_seen > max_moves:
				issues[i] = "Over move limit (%d max)" % max_moves
			elif not is_hex_passable(next_hex):
				issues[i] = "Blocked hex"
			hex = next_hex
	return issues

func count_all_issues() -> int:
	var total = 0
	for robot_id in plans.keys():
		total += get_step_issues(robot_id).size()
	return total

# ==================== Plan Editing ====================

# Writes a move to `dest_hex` at the robot's cursor round (padding with waits
# if the cursor is past the end) and advances the cursor. dest_hex must be
# adjacent to the robot's position entering that round.
func add_move_at_cursor(robot_id: String, dest_hex: Vector2i) -> bool:
	var r = get_cursor(robot_id)
	if r >= ROUNDS_PER_TURN:
		return false
	var dir = direction_between(get_projected_hex(robot_id, r - 1), dest_hex)
	if dir < 0:
		return false
	_write_step(robot_id, r, {"type": "move", "dir": dir})
	cursor_round[robot_id] = r + 1
	action_plan_changed.emit()
	return true

func add_wait_at_cursor(robot_id: String) -> bool:
	var r = get_cursor(robot_id)
	if r >= ROUNDS_PER_TURN:
		return false
	_write_step(robot_id, r, {"type": "wait"})
	cursor_round[robot_id] = r + 1
	action_plan_changed.emit()
	return true

func _write_step(robot_id: String, round_num: int, step: Dictionary) -> void:
	var steps: Array = plans[robot_id]["steps"]
	while steps.size() < round_num:
		steps.append({"type": "wait"})
	if round_num < steps.size():
		steps[round_num] = step
	else:
		steps.append(step)

# Shortest passable route from the hex entering the cursor round to dest_hex,
# limited to the robot's remaining moves and free rounds. Returns the list of
# hexes to step through (excluding the start), or [] if unreachable.
func find_route(robot_id: String, dest_hex: Vector2i) -> Array:
	var r = get_cursor(robot_id)
	var start = get_projected_hex(robot_id, r - 1)
	var moves_after_cursor = 0
	var steps = get_steps(robot_id)
	for i in range(r, steps.size()):
		if is_move_step(steps[i]):
			moves_after_cursor += 1
	var budget = mini(
		get_max_moves(robot_id) - (count_moves_planned(robot_id) - moves_after_cursor),
		ROUNDS_PER_TURN - r)
	if budget <= 0 or start == dest_hex:
		return []

	var came_from: Dictionary = {start: start}
	var frontier: Array = [start]
	for _depth in range(budget):
		var next_frontier: Array = []
		for hex in frontier:
			for d in HexMath.AXIAL_DIRECTIONS:
				var n = hex + d
				if n in came_from or not is_hex_passable(n):
					continue
				came_from[n] = hex
				if n == dest_hex:
					var route: Array = [n]
					var cur = hex
					while cur != start:
						route.push_front(cur)
						cur = came_from[cur]
					return route
				next_frontier.append(n)
		frontier = next_frontier
	return []

# Writes a whole route starting at the cursor. Later steps are kept and
# shifted by however many rounds the route used beyond one.
func add_route_at_cursor(robot_id: String, route: Array) -> bool:
	if route.is_empty():
		return false
	var r = get_cursor(robot_id)
	if r + route.size() > ROUNDS_PER_TURN:
		return false
	var prev = get_projected_hex(robot_id, r - 1)
	var new_steps: Array = []
	for hex in route:
		new_steps.append({"type": "move", "dir": direction_between(prev, hex)})
		prev = hex
	var steps: Array = plans[robot_id]["steps"].duplicate()
	while steps.size() < r:
		steps.append({"type": "wait"})
	# Replace the step at the cursor (if any), insert the rest.
	if r < steps.size():
		steps.remove_at(r)
	for i in range(new_steps.size()):
		steps.insert(r + i, new_steps[i])
	# Never silently push planned moves off the end of the turn.
	for i in range(ROUNDS_PER_TURN, steps.size()):
		if is_move_step(steps[i]):
			return false
	plans[robot_id]["steps"] = steps
	_shift_deploys(robot_id, r + 1, new_steps.size() - 1)
	_trim_to_turn(robot_id)
	cursor_round[robot_id] = r + new_steps.size()
	action_plan_changed.emit()
	return true

# Make round_num a wait (keeps later steps in their rounds).
func set_wait(robot_id: String, round_num: int) -> void:
	_write_step(robot_id, round_num, {"type": "wait"})
	_trim_trailing_waits(robot_id)
	action_plan_changed.emit()

# Insert a wait before round_num, pushing later steps one round later.
# Refused if that would push a move or deploy past the last round.
func insert_wait(robot_id: String, round_num: int) -> bool:
	var steps: Array = plans[robot_id]["steps"]
	var deploys: Dictionary = plans[robot_id]["deploys"]
	var last = ROUNDS_PER_TURN - 1
	if (steps.size() > last and is_move_step(steps[last])) or last in deploys:
		return false
	while steps.size() < round_num:
		steps.append({"type": "wait"})
	steps.insert(round_num, {"type": "wait"})
	_shift_deploys(robot_id, round_num, 1)
	_trim_to_turn(robot_id)
	_trim_trailing_waits(robot_id)
	action_plan_changed.emit()
	return true

# Remove the step at round_num, pulling later steps one round earlier.
func delete_step(robot_id: String, round_num: int) -> void:
	var steps: Array = plans[robot_id]["steps"]
	if round_num < steps.size():
		steps.remove_at(round_num)
	var deploys: Dictionary = plans[robot_id]["deploys"]
	deploys.erase(round_num)
	_shift_deploys(robot_id, round_num + 1, -1)
	_trim_trailing_waits(robot_id)
	if get_cursor(robot_id) > round_num:
		cursor_round[robot_id] = get_cursor(robot_id) - 1
	action_plan_changed.emit()

# Swap the steps (and deploys) of two rounds — the quick way to retime a move.
func swap_steps(robot_id: String, a: int, b: int) -> void:
	if a == b:
		return
	var step_a = get_step(robot_id, a)
	var step_b = get_step(robot_id, b)
	_write_step(robot_id, a, step_b)
	_write_step(robot_id, b, step_a)
	var deploys: Dictionary = plans[robot_id]["deploys"]
	var dep_a = deploys.get(a, null)
	var dep_b = deploys.get(b, null)
	deploys.erase(a)
	deploys.erase(b)
	if dep_b != null:
		deploys[a] = dep_b
	if dep_a != null:
		deploys[b] = dep_a
	_trim_trailing_waits(robot_id)
	action_plan_changed.emit()

# Remove the last step before the cursor and move the cursor back onto it.
func undo_last(robot_id: String) -> void:
	var r = get_cursor(robot_id) - 1
	if r < 0:
		return
	var steps: Array = plans[robot_id]["steps"]
	if r < steps.size():
		steps.remove_at(r)
		_shift_deploys(robot_id, r + 1, -1)
	_trim_trailing_waits(robot_id)
	cursor_round[robot_id] = r
	action_plan_changed.emit()

func clear_robot(robot_id: String) -> void:
	plans[robot_id] = {"steps": [], "deploys": {}}
	cursor_round[robot_id] = 0
	action_plan_changed.emit()

func set_deploy(robot_id: String, round_num: int, target_hex: Vector2i) -> void:
	var from_hex = get_projected_hex(robot_id, round_num - 1)
	plans[robot_id]["deploys"][round_num] = {
		"type": get_deploy_type(robot_id),
		"offset": target_hex - from_hex,
	}
	action_plan_changed.emit()

# A Scout's leap is its deploy: it replaces the step at round_num.
func set_leap(robot_id: String, round_num: int, target_hex: Vector2i) -> void:
	var from_hex = get_projected_hex(robot_id, round_num - 1)
	_write_step(robot_id, round_num, {"type": "leap", "offset": target_hex - from_hex})
	cursor_round[robot_id] = round_num + 1
	action_plan_changed.emit()

func clear_deploy(robot_id: String, round_num: int) -> void:
	if get_step(robot_id, round_num).get("type", "wait") == "leap":
		set_wait(robot_id, round_num)
		return
	plans[robot_id]["deploys"].erase(round_num)
	action_plan_changed.emit()

func has_deploy(robot_id: String, round_num: int) -> bool:
	return round_num in get_deploys(robot_id) \
		or get_step(robot_id, round_num).get("type", "wait") == "leap"

func get_deploy_target(robot_id: String, round_num: int) -> Vector2i:
	var deploy = get_deploys(robot_id).get(round_num, {})
	return get_projected_hex(robot_id, round_num - 1) + deploy.get("offset", Vector2i.ZERO)

# Move deploys at rounds >= from_round by delta rounds, dropping any that
# fall outside the turn.
func _shift_deploys(robot_id: String, from_round: int, delta: int) -> void:
	if delta == 0:
		return
	var old: Dictionary = plans[robot_id]["deploys"]
	var shifted: Dictionary = {}
	for round_num in old.keys():
		var new_round = round_num + delta if round_num >= from_round else round_num
		if new_round >= 0 and new_round < ROUNDS_PER_TURN:
			shifted[new_round] = old[round_num]
	plans[robot_id]["deploys"] = shifted

func _trim_to_turn(robot_id: String) -> void:
	var steps: Array = plans[robot_id]["steps"]
	while steps.size() > ROUNDS_PER_TURN:
		steps.pop_back()

func _trim_trailing_waits(robot_id: String) -> void:
	var steps: Array = plans[robot_id]["steps"]
	while not steps.is_empty() and steps.back().get("type", "wait") == "wait":
		steps.pop_back()

# ==================== Submission ====================

# Build the actions array for API submission: six chained rounds per robot.
# Each step is re-checked from the robot's actual chained position; illegal
# moves are sent as waits and illegal deploys dropped, so an auto-submit on
# timeout never fails server validation.
func build_submit_payload() -> Array:
	var actions: Array = []
	for robot_id in plans.keys():
		var robot = GameState.robot_lookup.get(robot_id, {})
		var deploys = get_deploys(robot_id)
		var moves_left = get_max_moves(robot_id)
		var energy_left = int(robot.get("energy", 0))
		var leaps_left = LEAPS_PER_TURN
		var cur_hex = get_start_hex(robot_id)
		for i in range(ROUNDS_PER_TURN):
			var step = get_step(robot_id, i)
			var after_hex = cur_hex
			var leaped = false
			if step.get("type", "wait") == "move" and moves_left > 0:
				var next_hex = cur_hex + HexMath.AXIAL_DIRECTIONS[step["dir"]]
				if is_hex_passable(next_hex):
					after_hex = next_hex
					moves_left -= 1
			elif step.get("type", "wait") == "leap" and moves_left > 0 and energy_left > 0 and leaps_left > 0:
				var landing = cur_hex + step["offset"]
				if is_hex_passable(landing):
					after_hex = landing
					moves_left -= 1
					energy_left -= 1
					leaps_left -= 1
					leaped = true
			var action_dict: Dictionary = {
				"robot_id": robot_id,
				"round_number": i,
				"action_type": "move" if after_hex != cur_hex else "wait",
				"before_position": [cur_hex.x, cur_hex.y],
				"after_position": [after_hex.x, after_hex.y],
			}
			if leaped:
				action_dict["deploy"] = {"type": "leap", "target_hexes": [[after_hex.x, after_hex.y]]}
			if i in deploys and energy_left > 0:
				var target = cur_hex + deploys[i]["offset"]
				if target in get_valid_deploy_targets(robot_id, cur_hex):
					energy_left -= 1
					var area: Array = []
					for h in get_deploy_area(deploys[i]["type"], cur_hex, target):
						area.append([h.x, h.y])
					action_dict["deploy"] = {
						"type": deploys[i]["type"],
						"target_hexes": area,
					}
			actions.append(action_dict)
			cur_hex = after_hex
	return actions

# Get valid deploy target hexes around from_hex (the robot's position at the
# start of the deploy round).
func get_valid_deploy_targets(robot_id: String, from_hex: Vector2i) -> Array:
	var result: Array = []
	match get_deploy_type(robot_id):
		"emp":
			for radius in [4, 5, 6]:
				result.append_array(HexMath.hex_ring(from_hex, radius))
		"firewall":
			result.append_array(HexMath.hex_ring(from_hex, 4))
		"supply_drop":
			result = HexMath.axial_neighbors(from_hex)
		"leap":
			# Straight-line distance 2-3, over anything; only the landing hex must be open
			for radius in range(LEAP_MIN, LEAP_MAX + 1):
				for h in HexMath.hex_ring(from_hex, radius):
					if is_hex_passable(h):
						result.append(h)
	return result

# Every hex a deploy affects: EMP covers the target and all hexes within 3 of it;
# Firewall is the line from the robot out to the target, not counting the robot's hex.
func get_deploy_area(deploy_type: String, from_hex: Vector2i, target: Vector2i) -> Array:
	match deploy_type:
		"emp":
			return HexMath.hexes_in_radius(target, EMP_RADIUS)
		"firewall":
			var line = HexMath.hex_line(from_hex, target)
			line.erase(from_hex)
			return line
	return [target]

func validate_plan() -> Array:
	var errors: Array = []
	for robot_id in plans.keys():
		var robot = GameState.robot_lookup.get(robot_id, {})
		var issues = get_step_issues(robot_id)
		for round_num in issues.keys():
			errors.append("%s R%d: %s" % [
				robot.get("type", "robot").capitalize(), round_num + 1, issues[round_num]])
	return errors
