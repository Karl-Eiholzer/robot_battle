extends Node

# Action planning state for the current turn.
# Manages the 6-round action plan per robot and deploy targeting mode.

enum Phase {
	WAITING,          # Not our turn yet / waiting for game to start
	INPUT,            # Planning actions
	DEPLOY_TARGETING, # Selecting target hex for a deploy action
	SUBMITTING,       # Waiting for submit response
	REVIEWING,        # Watching replay
	GAME_OVER         # Game ended
}

const ROUNDS_PER_TURN: int = 6

# ==================== State ====================

var current_phase: Phase = Phase.WAITING
var current_round: int = 0       # Which round the player is currently editing (0-5)
var selected_robot_id: String = ""

# action_plan: robot_id -> Array of ROUNDS_PER_TURN dicts (one per round)
# Each dict: {action_type: "move"/"wait", before_position: [q,r], after_position: [q,r], deploy: null/dict}
var action_plan: Dictionary = {}

# Deploy targeting state
var deploy_target_robot_id: String = ""
var deploy_type: String = ""
var deploy_round: int = -1

# ==================== Signals ====================

signal phase_changed(new_phase: Phase)
signal current_round_changed(round_num: int)
signal robot_selected(robot_id: String)
signal action_plan_changed()

# ==================== Constants ====================

# Robot type stats matching backend ROBOT_TYPE_STATS
const ROBOT_STATS: Dictionary = {
	"captain":  {"moves_per_turn": 3, "max_energy": 2, "deploy_type": "emp",         "sight_range": 5, "strength": 7},
	"scout":    {"moves_per_turn": 4, "max_energy": 6, "deploy_type": "extra_moves", "sight_range": 7, "strength": 3},
	"defender": {"moves_per_turn": 2, "max_energy": 3, "deploy_type": "firewall",    "sight_range": 3, "strength": 5},
	"engineer": {"moves_per_turn": 6, "max_energy": 3, "deploy_type": "supply_drop", "sight_range": 5, "strength": 0},
}

# ==================== Phase Control ====================

func set_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_changed.emit(new_phase)

func start_input_phase() -> void:
	_initialize_action_plan()
	selected_robot_id = ""
	set_current_round(0)
	set_phase(Phase.INPUT)

func set_current_round(n: int) -> void:
	current_round = clampi(n, 0, ROUNDS_PER_TURN - 1)
	current_round_changed.emit(current_round)

func start_deploy_targeting(robot_id: String, round_num: int) -> void:
	deploy_target_robot_id = robot_id
	deploy_round = round_num
	var robot = GameState.robot_lookup.get(robot_id, {})
	deploy_type = ROBOT_STATS.get(robot.get("type", ""), {}).get("deploy_type", "")
	set_phase(Phase.DEPLOY_TARGETING)

func cancel_deploy_targeting() -> void:
	deploy_target_robot_id = ""
	deploy_type = ""
	deploy_round = -1
	set_phase(Phase.INPUT)

func confirm_deploy_target(target_hexes: Array) -> void:
	if deploy_target_robot_id == "" or deploy_round < 0:
		return
	var rounds = action_plan.get(deploy_target_robot_id, [])
	if deploy_round < rounds.size():
		rounds[deploy_round]["deploy"] = {
			"type": deploy_type,
			"target_hexes": target_hexes
		}
	action_plan_changed.emit()
	cancel_deploy_targeting()

func clear_deploy_for_round(robot_id: String, round_num: int) -> void:
	var rounds = action_plan.get(robot_id, [])
	if round_num < rounds.size():
		rounds[round_num]["deploy"] = null
	action_plan_changed.emit()

# ==================== Robot Selection ====================

func select_robot(robot_id: String) -> void:
	selected_robot_id = robot_id
	robot_selected.emit(robot_id)

func get_selected_robot() -> Dictionary:
	return GameState.robot_lookup.get(selected_robot_id, {})

# ==================== Action Plan ====================

func _initialize_action_plan() -> void:
	action_plan.clear()
	for robot in GameState.player_robots:
		var robot_id = robot.get("robot_id", "")
		var pos = robot.get("position", [0, 0])
		var rounds: Array = []
		for i in range(ROUNDS_PER_TURN):
			rounds.append({
				"action_type": "wait",
				"before_position": pos.duplicate(),
				"after_position": pos.duplicate(),
				"deploy": null
			})
		action_plan[robot_id] = rounds

# Returns the robot's position after completing rounds 0..after_round.
# Pass after_round = -1 to get the starting position for this turn.
# Wait rounds do not change position; only "move" rounds advance it.
func get_projected_position(robot_id: String, after_round: int) -> Array:
	var robot = GameState.robot_lookup.get(robot_id, {})
	var start_pos = robot.get("position", [0, 0])
	if after_round < 0:
		return start_pos.duplicate()
	var rounds = action_plan.get(robot_id, [])
	var pos = start_pos.duplicate()
	for i in range(mini(after_round + 1, rounds.size())):
		if rounds[i].get("action_type", "wait") == "move":
			pos = rounds[i].get("after_position", pos).duplicate()
	return pos

# Assign a move destination for a round.
# Clears all subsequent move rounds and deploys (cascade) since their
# before_positions may no longer be valid after this change.
func set_move_for_round(robot_id: String, round_num: int, dest_pos: Array) -> void:
	var rounds = action_plan.get(robot_id, [])
	if round_num >= rounds.size():
		return
	var before_pos = get_projected_position(robot_id, round_num - 1)
	rounds[round_num]["action_type"] = "move"
	rounds[round_num]["before_position"] = before_pos.duplicate()
	rounds[round_num]["after_position"] = dest_pos.duplicate()
	_cascade_clear_after(robot_id, round_num)
	action_plan_changed.emit()

# Set a round to wait, clearing all subsequent moves (cascade).
func clear_move_for_round(robot_id: String, round_num: int) -> void:
	var rounds = action_plan.get(robot_id, [])
	if round_num >= rounds.size():
		return
	var before_pos = get_projected_position(robot_id, round_num - 1)
	rounds[round_num]["action_type"] = "wait"
	rounds[round_num]["before_position"] = before_pos.duplicate()
	rounds[round_num]["after_position"] = before_pos.duplicate()
	_cascade_clear_after(robot_id, round_num)
	action_plan_changed.emit()

# Clear moves and deploys in all rounds after from_round.
func _cascade_clear_after(robot_id: String, from_round: int) -> void:
	var rounds = action_plan.get(robot_id, [])
	for i in range(from_round + 1, rounds.size()):
		rounds[i]["action_type"] = "wait"
		rounds[i]["deploy"] = null

func get_max_moves(robot_id: String) -> int:
	var robot = GameState.robot_lookup.get(robot_id, {})
	var robot_type = robot.get("type", "captain")
	var base_moves = ROBOT_STATS.get(robot_type, {}).get("moves_per_turn", 3)
	var extra = robot.get("extra_moves_this_turn", 0)
	return base_moves + extra

func count_moves_planned(robot_id: String) -> int:
	var count = 0
	for round_data in action_plan.get(robot_id, []):
		if round_data.get("action_type", "wait") == "move":
			count += 1
	return count

# Build the actions array for API submission.
# Computes before_position from the move chain rather than using stored values,
# so editing earlier rounds never produces stale before_positions.
func build_submit_payload() -> Array:
	var actions: Array = []
	for robot_id in action_plan.keys():
		var robot = GameState.robot_lookup.get(robot_id, {})
		var start_pos = robot.get("position", [0, 0])
		var rounds = action_plan[robot_id]
		var cur_pos = start_pos.duplicate()
		for i in range(rounds.size()):
			var round_data = rounds[i]
			var action_type = round_data.get("action_type", "wait")
			var after_pos: Array = cur_pos.duplicate()
			if action_type == "move":
				after_pos = round_data.get("after_position", cur_pos).duplicate()
			var action_dict: Dictionary = {
				"robot_id": robot_id,
				"round_number": i,
				"action_type": action_type,
				"before_position": cur_pos.duplicate(),
				"after_position": after_pos,
			}
			var deploy = round_data.get("deploy", null)
			if deploy != null:
				action_dict["deploy"] = deploy
			actions.append(action_dict)
			cur_pos = after_pos.duplicate()
	return actions

# Get valid deploy target hexes. from_pos overrides the robot's actual position
# so targeting can use projected positions during planning.
func get_valid_deploy_targets(robot_id: String, from_pos: Array = []) -> Array:
	var pos: Array
	if from_pos.is_empty():
		var robot = GameState.robot_lookup.get(robot_id, {})
		pos = robot.get("position", [0, 0])
	else:
		pos = from_pos
	var center = Vector2i(int(pos[0]), int(pos[1]))
	var deploy = ROBOT_STATS.get(
		GameState.robot_lookup.get(robot_id, {}).get("type", ""), {}
	).get("deploy_type", "")
	var result: Array = []
	match deploy:
		"emp":
			for radius in [4, 5, 6]:
				result.append_array(HexMath.hex_ring(center, radius))
		"firewall":
			result.append_array(HexMath.hex_ring(center, 4))
		"supply_drop":
			result = HexMath.axial_neighbors(center)
		"extra_moves":
			result = [center]
	return result

func validate_plan() -> Array:
	var errors: Array = []
	for robot_id in action_plan.keys():
		var max_moves = get_max_moves(robot_id)
		var planned_moves = count_moves_planned(robot_id)
		if planned_moves > max_moves:
			errors.append("Robot %s has %d moves but max is %d" % [robot_id, planned_moves, max_moves])
	return errors
