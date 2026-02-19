extends Control

# Role assignment scene — shown to all players before game starts.
# Each player assigns their own role via a dropdown.
# The backend validates the complete set when spawn_robots is called.

const ROLES_2: Array = ["captain", "huntsman"]
const ROLES_3: Array = ["captain", "huntsman", "engineer"]

const ROLE_DESCRIPTIONS: Dictionary = {
	"captain":  "Captain: 1 Captain + 2 Defenders + 2 Engineers",
	"huntsman": "Huntsman: 4 Scouts + 1 Engineer",
	"engineer": "Engineer: 5 Engineers",
}

# ==================== Node References ====================

@onready var team_label: Label = $CenterContainer/VBox/TeamLabel
@onready var roles_container: VBoxContainer = $CenterContainer/VBox/RolesContainer
@onready var assign_btn: Button = $CenterContainer/VBox/AssignBtn
@onready var spawn_btn: Button = $CenterContainer/VBox/SpawnBtn
@onready var status_label: Label = $CenterContainer/VBox/StatusLabel
@onready var error_label: Label = $CenterContainer/VBox/ErrorLabel
@onready var role_guide: Label = $CenterContainer/VBox/RoleGuide
@onready var poll_timer: Timer = $PollTimer

# ==================== State ====================

var _my_role_dropdown: OptionButton = null
var _team_size: int = 2
var _my_team: int = 0

# ==================== Ready ====================

func _ready() -> void:
	_my_team = GameState.player_team
	_team_size = GameState.game_variables.get("team_size", 2)

	team_label.text = "Team %d — Assign Your Role" % _my_team

	assign_btn.pressed.connect(_on_assign_pressed)
	spawn_btn.pressed.connect(_on_spawn_pressed)
	poll_timer.timeout.connect(_on_poll_timer)

	APIClient.roles_assigned.connect(_on_roles_assigned)
	APIClient.robots_spawned.connect(_on_robots_spawned)
	APIClient.initial_state_received.connect(_on_initial_state)
	APIClient.game_status_received.connect(_on_status_received)
	APIClient.request_failed.connect(_on_request_failed)

	_build_role_ui()
	_update_role_guide()

	# Poll to detect when robots are spawned (both teams assigned)
	poll_timer.start()

# ==================== UI Building ====================

func _build_role_ui() -> void:
	for child in roles_container.get_children():
		child.queue_free()

	var available_roles = ROLES_3 if _team_size == 3 else ROLES_2

	var hbox = HBoxContainer.new()
	hbox.theme_override_constants.separation = 12
	roles_container.add_child(hbox)

	var lbl = Label.new()
	lbl.text = "Your Role:"
	lbl.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(lbl)

	_my_role_dropdown = OptionButton.new()
	_my_role_dropdown.custom_minimum_size = Vector2(200, 36)
	for role in available_roles:
		_my_role_dropdown.add_item(role.capitalize())
	_my_role_dropdown.selected = 0
	hbox.add_child(_my_role_dropdown)

func _update_role_guide() -> void:
	var lines: Array = []
	var roles = ROLES_3 if _team_size == 3 else ROLES_2
	for role in roles:
		lines.append(ROLE_DESCRIPTIONS.get(role, role))
	role_guide.text = "\n".join(lines)

# ==================== Button Handlers ====================

func _on_assign_pressed() -> void:
	if _my_role_dropdown == null:
		_show_error("No role selected.")
		return

	var available_roles = ROLES_3 if _team_size == 3 else ROLES_2
	var chosen_role = available_roles[_my_role_dropdown.selected]
	var assignments = {GameState.player_id: chosen_role}

	assign_btn.disabled = true
	_show_status("Assigning role '%s'..." % chosen_role)
	APIClient.assign_roles(GameState.game_id, _my_team, assignments)

func _on_spawn_pressed() -> void:
	spawn_btn.disabled = true
	_show_status("Spawning robots...")
	APIClient.spawn_robots(GameState.game_id)

# ==================== API Response Handlers ====================

func _on_roles_assigned(data: Dictionary) -> void:
	_show_status("Role assigned! Waiting for all players and both teams to assign roles, then any player can spawn robots.")
	spawn_btn.disabled = false

func _on_robots_spawned(data: Dictionary) -> void:
	_show_status("Robots spawned! Loading game state...")
	APIClient.get_initial_state(GameState.game_id)

func _on_initial_state(data: Dictionary) -> void:
	# Initial state only returned if robots exist
	var player_robots = data.get("player_robots", [])
	if player_robots.is_empty():
		_show_status("Waiting for robots to spawn...")
		return
	GameState.initialize_from_initial_state(data)
	poll_timer.stop()
	get_tree().change_scene_to_file("res://scenes/game_view.tscn")

func _on_status_received(_data: Dictionary) -> void:
	pass  # Just used for future status polling if needed

func _on_request_failed(endpoint: String, _status_code: int, body: String) -> void:
	if endpoint.contains("spawn"):
		spawn_btn.disabled = false
		_show_error("Spawn failed: %s\n(Both teams must assign roles first)" % body)
	elif endpoint.contains("assign"):
		assign_btn.disabled = false
		_show_error("Role assignment failed: %s" % body)
	elif endpoint.contains("initial_state"):
		_show_status("Waiting for robots to be spawned by any player...")
	else:
		_show_error("Error: %s" % body)

# ==================== Polling ====================

func _on_poll_timer() -> void:
	if GameState.game_id != "":
		APIClient.get_initial_state(GameState.game_id)

# ==================== UI Helpers ====================

func _show_status(msg: String) -> void:
	status_label.text = msg
	error_label.text = ""

func _show_error(msg: String) -> void:
	error_label.text = msg
	status_label.text = ""
