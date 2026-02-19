extends Node

# Single source of truth for all runtime game data.
# All scenes read from here; APIClient writes here after successful responses.

# ==================== Identity ====================

var game_id: String = ""
var player_id: String = ""
var api_key: String = ""
var player_name: String = ""
var player_team: int = -1  # 0 or 1

# ==================== Game Config ====================

var game_variables: Dictionary = {
	"team_size": 2,
	"map_size": "medium",
	"input_time": 90,
	"review_time": 40,
	"starting_energy": 2
}

# ==================== Map ====================

# Full map dict from API: {hexes: [{q, r, terrain, ...}], width, height, spawn_points}
var map_data: Dictionary = {}

# ==================== Game Progress ====================

var game_state_str: String = "waiting_for_players"
# States: waiting_for_players, in_progress, processing_turn, complete

var current_turn: int = 0
var initiative_team: int = 0

# ==================== Robots ====================

# All known robots as dicts from API.
# For player's own robots: full data including energy.
# For enemies: position + type only (fog of war).
var player_robots: Array = []   # List[dict] for this player's robots
var visible_enemies: Array = []  # List[dict] for visible enemy robots

# Combined lookup: robot_id -> dict
var robot_lookup: Dictionary = {}

# ==================== Hex Objects ====================

# List[dict] of hex objects: {type, position: [q, r], created_turn, created_by}
var hex_objects: Array = []

# ==================== Role Assignment ====================

# Track which players on our team have been assigned roles
# player_id -> role_name
var team_role_assignments: Dictionary = {}

# Whether this player is the captain (first to join their team)
var is_team_captain: bool = false

# ==================== Signals ====================

signal game_data_updated()
signal robots_updated()
signal hex_objects_updated()
signal game_state_changed(new_state: String)
signal game_over(winner_team: int)

# ==================== Init ====================

func _ready() -> void:
	load_saved_state()

# ==================== State Management ====================

func update_game_state(new_state: String) -> void:
	game_state_str = new_state
	game_state_changed.emit(new_state)

func initialize_from_create_response(data: Dictionary) -> void:
	game_id = data.get("game_id", "")
	player_id = data.get("creator_player_id", "")
	api_key = data.get("api_key", "")
	player_team = 0  # Creator is always team 0
	game_state_str = data.get("state", "waiting_for_players")
	save_state()

func initialize_from_join_response(data: Dictionary) -> void:
	game_id = data.get("game_id", "")
	player_id = data.get("player_id", "")
	api_key = data.get("api_key", "")
	game_state_str = data.get("state", "waiting_for_players")
	map_data = data.get("map", {})
	# Team is determined by join order; we'll get it from initial_state
	save_state()

func initialize_from_initial_state(data: Dictionary) -> void:
	current_turn = data.get("current_turn", 0)
	initiative_team = data.get("team_with_initiative", 0)
	map_data = data.get("map", map_data)
	game_variables = data.get("game_variables", game_variables)
	hex_objects = data.get("hex_objects", [])

	player_robots = data.get("player_robots", [])
	visible_enemies = data.get("other_robots", [])

	_rebuild_robot_lookup()

	# Determine player team from own robots
	if player_robots.size() > 0:
		player_team = player_robots[0].get("team", player_team)

	# Captain: we assume the first player on the team is captain;
	# for prototype, captain is determined by having team_order role assignment
	# We detect this in role_assignment.gd based on API response

	game_data_updated.emit()
	robots_updated.emit()
	hex_objects_updated.emit()

func apply_turn_results(data: Dictionary) -> void:
	var updated_robots: Array = data.get("updated_robots", [])
	var updated_hex_objects: Array = data.get("updated_hex_objects", [])
	var next_turn: int = data.get("next_turn", current_turn + 1)
	var winner = data.get("winner", null)

	current_turn = next_turn

	# Rebuild robot lists from updated data
	player_robots.clear()
	visible_enemies.clear()
	for robot in updated_robots:
		if robot.get("player_id", "") == player_id:
			player_robots.append(robot)
		else:
			visible_enemies.append(robot)

	_rebuild_robot_lookup()

	hex_objects = updated_hex_objects

	robots_updated.emit()
	hex_objects_updated.emit()

	if winner != null:
		game_over.emit(winner)

func _rebuild_robot_lookup() -> void:
	robot_lookup.clear()
	for r in player_robots:
		robot_lookup[r.get("robot_id", "")] = r
	for r in visible_enemies:
		robot_lookup[r.get("robot_id", "")] = r

# ==================== Hex Object Helpers ====================

func get_hex_object_at(q: int, r: int) -> Dictionary:
	for obj in hex_objects:
		var pos = obj.get("position", [])
		if pos.size() >= 2 and pos[0] == q and pos[1] == r:
			return obj
	return {}

# ==================== Persistence ====================

const SAVE_PATH = "user://last_game.cfg"

func save_state() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("session", "game_id", game_id)
	cfg.set_value("session", "player_id", player_id)
	cfg.set_value("session", "api_key", api_key)
	cfg.set_value("session", "player_name", player_name)
	cfg.set_value("session", "player_team", player_team)
	cfg.save(SAVE_PATH)

func load_saved_state() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		game_id = cfg.get_value("session", "game_id", "")
		player_id = cfg.get_value("session", "player_id", "")
		api_key = cfg.get_value("session", "api_key", "")
		player_name = cfg.get_value("session", "player_name", "")
		player_team = cfg.get_value("session", "player_team", -1)

func clear_saved_state() -> void:
	var cfg = ConfigFile.new()
	cfg.save(SAVE_PATH)  # Overwrite with empty
	game_id = ""
	player_id = ""
	api_key = ""
	player_name = ""
	player_team = -1
	player_robots.clear()
	visible_enemies.clear()
	robot_lookup.clear()
	hex_objects.clear()
	map_data = {}
	current_turn = 0
