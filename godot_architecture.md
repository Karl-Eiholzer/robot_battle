# Godot Client Architecture

## Overview

Godot 4.x game client for the Robot Battle turn-based multiplayer game. Connects to the FastAPI backend hosted on Railway. All visuals are prototype-quality colored shapes — no art assets.

## Godot Version

**Godot 4.x** (GDScript 2.0) required.

## Project Structure

```
game_client/
├── project.godot
├── icon.svg
├── scenes/
│   ├── main_menu.tscn + main_menu.gd
│   ├── role_assignment.tscn + role_assignment.gd
│   ├── game_view.tscn + game_view.gd
│   └── game_end.tscn + game_end.gd
└── scripts/
    ├── hex_math.gd        # Autoload: HexMath — axial coordinate math
    ├── api_client.gd      # Autoload: APIClient — all HTTP calls
    ├── game_state.gd      # Autoload: GameState — single source of truth
    ├── turn_input.gd      # Autoload: TurnInput — action planning state machine
    ├── hex_map.gd         # class_name HexMap — map renderer, click input
    └── robot_sprite.gd    # class_name RobotSprite — per-robot visuals
```

## Autoload Singletons

Four autoloads registered in project.godot:

```
HexMath="*res://scripts/hex_math.gd"
APIClient="*res://scripts/api_client.gd"
GameState="*res://scripts/game_state.gd"
TurnInput="*res://scripts/turn_input.gd"
```

All are called globally as `HexMath.func()`, `APIClient.func()`, etc.

---

## APIClient Singleton

Single shared `HTTPRequest` node with a request queue. Only one HTTP request is in-flight at a time; calls are queued and processed in order.

### Signals

```gdscript
signal game_created(data: Dictionary)
signal game_joined(data: Dictionary)
signal game_status_received(data: Dictionary)
signal roles_assigned(data: Dictionary)
signal robots_spawned(data: Dictionary)
signal initial_state_received(data: Dictionary)
signal moves_submitted(data: Dictionary)
signal results_received(data: Dictionary)
signal request_failed(endpoint: String, status_code: int, body: String)
```

`request_failed` is emitted for any HTTP 4xx/5xx response. The `body` string contains the `detail` field from the API error response.

### Authentication

The API key is read from `GameState.api_key` and added as `X-API-Key: <key>` header on every request. The key is returned by the create/join endpoints and stored in GameState (not in APIClient itself).

### Endpoint Methods

```gdscript
func create_game(player_name: String, team_size: int) -> void
# POST /game/create
# Body: {max_players: team_size*2, map_config: {width:15, height:15},
#        game_variables: {team_size: team_size}}

func join_game(game_id: String, player_name: String) -> void
# POST /game/{id}/join
# Body: {player_name: player_name}

func get_status(game_id: String) -> void
# GET /game/{id}/status

func assign_roles(game_id: String, team: int, assignments: Dictionary) -> void
# POST /game/{id}/team/{team}/assign_roles
# Body: {team: team, role_assignments: {player_id: role_name, ...}}

func spawn_robots(game_id: String) -> void
# POST /game/{id}/spawn_robots

func get_initial_state(game_id: String) -> void
# GET /game/{id}/initial_state

func submit_actions(game_id: String, turn: int, actions: Array) -> void
# POST /game/{id}/submit
# Body: {turn: turn, actions: [RoundAction, ...]}

func get_results(game_id: String, turn: int) -> void
# GET /game/{id}/results?turn={turn}
```

### Request Queue Pattern

```gdscript
func _enqueue(endpoint: String, method: int, body: Dictionary, signal_name: String) -> void:
    _request_queue.append({...})
    if not _is_requesting:
        _process_next_request()

func _on_request_completed(result, response_code, _headers, body) -> void:
    # Parse JSON, check for errors, emit the correct signal
    # Then call _process_next_request() to drain the queue
```

---

## GameState Singleton

Single source of truth for all runtime game data. Scenes read from it; API response handlers write to it.

### Properties

```gdscript
# Identity
var game_id: String
var player_id: String
var api_key: String          # Stored here, read by APIClient for headers
var player_name: String
var player_team: int         # 0 or 1; set from player_robots[0].team in initial_state

# Game config (from game_variables in initial_state response)
var game_variables: Dictionary  # team_size, map_size, input_time, review_time, starting_energy

# Map
var map_data: Dictionary        # {hexes: [{q, r, terrain}], width, height, spawn_points}

# Game progress
var game_state_str: String      # waiting_for_players, in_progress, processing_turn, complete
var current_turn: int
var initiative_team: int

# Robots (fog of war split)
var player_robots: Array        # Full robot data (energy, state, position) for own robots
var visible_enemies: Array      # Partial data (position, type) for visible enemies
var robot_lookup: Dictionary    # robot_id -> dict (combined, rebuilt after any update)

# Hex objects on the map
var hex_objects: Array          # [{type, position:[q,r], created_turn, created_by}]
```

### Signals

```gdscript
signal game_data_updated()
signal robots_updated()
signal hex_objects_updated()
signal game_state_changed(new_state: String)
signal game_over(winner_team: int)
```

### Key Methods

```gdscript
func initialize_from_create_response(data: Dictionary) -> void
# Sets game_id, player_id, api_key, player_team=0; calls save_state()

func initialize_from_join_response(data: Dictionary) -> void
# Sets game_id, player_id, api_key, map_data; team set later from initial_state

func initialize_from_initial_state(data: Dictionary) -> void
# Sets map_data, game_variables, hex_objects, player_robots, visible_enemies
# Derives player_team from player_robots[0].team

func apply_turn_results(data: Dictionary) -> void
# Updates current_turn, rebuilds robot lists from updated_robots
# Emits game_over if winner present

func get_hex_object_at(q: int, r: int) -> Dictionary
```

### Persistence

Session state is saved to `user://last_game.cfg` (Godot ConfigFile format) on create/join so players can rejoin after a crash.

```gdscript
func save_state() -> void      # Saves game_id, player_id, api_key, player_name, player_team
func load_saved_state() -> void # Called in _ready(); pre-fills fields on startup
func clear_saved_state() -> void # Called on return to main menu
```

---

## TurnInput Singleton

Manages the 6-round action plan for the current turn and the deploy targeting flow.

### Phase Enum

```gdscript
enum Phase {
    WAITING,           # Waiting for game to start
    INPUT,             # Player is planning actions
    DEPLOY_TARGETING,  # Player clicked Deploy; map shows valid target hexes
    SUBMITTING,        # Actions sent to API, awaiting response
    REVIEWING,         # Replay is playing back
    GAME_OVER          # Game ended
}
```

### Robot Stats (mirrors backend)

```gdscript
const ROBOT_STATS: Dictionary = {
    "captain":  {moves_per_turn:3, max_energy:2, deploy_type:"emp",         sight_range:5, strength:7},
    "scout":    {moves_per_turn:4, max_energy:6, deploy_type:"extra_moves", sight_range:7, strength:3},
    "defender": {moves_per_turn:2, max_energy:3, deploy_type:"firewall",    sight_range:3, strength:5},
    "engineer": {moves_per_turn:6, max_energy:3, deploy_type:"supply_drop", sight_range:5, strength:0},
}
```

### Action Plan

```gdscript
# action_plan: Dictionary  robot_id -> Array[6 Dictionaries]
# Each round dict:
{
    "action_type": "move" or "wait",
    "before_position": [q, r],
    "after_position": [q, r],   # Same as before if action_type == "wait"
    "deploy": null or {"type": "emp", "target_hexes": [[q, r], ...]}
}
```

### Key Methods

```gdscript
func start_input_phase() -> void
# Initializes action_plan for all player_robots (all rounds default to wait)
# Sets phase to INPUT

func set_round_action(robot_id, round_num, action_type, before_pos, after_pos) -> void
func count_moves_planned(robot_id: String) -> int
func get_max_moves(robot_id: String) -> int   # base + extra_moves_this_turn

func start_deploy_targeting(robot_id: String, round_num: int) -> void
func confirm_deploy_target(target_hexes: Array) -> void
func cancel_deploy_targeting() -> void

func get_valid_deploy_targets(robot_id: String) -> Array
# Returns Array of Vector2i based on deploy type:
#   emp:         rings at distance 4, 5, 6
#   firewall:    ring at distance 4
#   supply_drop: adjacent hexes (distance 1)
#   extra_moves: self hex only (no targeting UI needed)

func build_submit_payload() -> Array
# Returns Array of RoundAction dicts for all robots, all 6 rounds
# Passed directly to APIClient.submit_actions()

func validate_plan() -> Array
# Returns Array of error strings (empty = valid)
```

### Signals

```gdscript
signal phase_changed(new_phase: Phase)
signal robot_selected(robot_id: String)
signal action_plan_changed()
```

---

## HexMath Autoload

Pure math functions for flat-top axial hex coordinates. Registered as an autoload (`extends Node`) so it can be called as `HexMath.func()` from any script.

### Coordinate System

Flat-top hexagons with axial (q, r) coordinates. `Vector2i(q, r)` used throughout.

### Functions

```gdscript
const HEX_SIZE: float = 48.0   # Radius from center to corner, in pixels

static func axial_distance(a: Vector2i, b: Vector2i) -> int
static func axial_neighbors(hex: Vector2i) -> Array   # Returns Array of 6 Vector2i
static func axial_to_pixel(hex: Vector2i, hex_size: float = HEX_SIZE) -> Vector2
static func pixel_to_axial(pixel: Vector2, hex_size: float = HEX_SIZE) -> Vector2i
static func axial_round(frac: Vector2) -> Vector2i
static func hexes_in_radius(center: Vector2i, radius: int) -> Array
static func hex_ring(center: Vector2i, radius: int) -> Array
static func hex_line(a: Vector2i, b: Vector2i) -> Array
```

The `axial_to_pixel` / `pixel_to_axial` formulas for flat-top layout:
```
pixel.x = hex_size * 1.5 * hex.x
pixel.y = hex_size * (sqrt(3)/2 * hex.x + sqrt(3) * hex.y)
```

---

## HexMap Node (class_name HexMap)

`extends Node2D`, placed as a child of GameView. Handles all map rendering and click input. Uses Godot's `_draw()` method — no textures or Sprite2D nodes needed.

### Map Rendering

Hexes are drawn as filled polygons with colors from a terrain palette:

```gdscript
const TERRAIN_COLORS: Dictionary = {
    "plains":   Color(0.55, 0.76, 0.29),
    "forest":   Color(0.18, 0.49, 0.18),
    "mountain": Color(0.55, 0.47, 0.35),
    "water":    Color(0.20, 0.45, 0.80),
    "obstacle": Color(0.35, 0.30, 0.25),
    "spawn":    Color(0.70, 0.70, 0.50),
}
```

Hexes outside the player's sight range are darkened by 55% and made semi-transparent (fog of war). The visible area is computed at startup from `GameState.player_robots` positions and sight ranges.

### Hex Object Rendering

Hex objects (EMP, Firewall, Supply Drop) are rendered as colored semi-transparent circles overlaid on the hex, with a Label child showing a symbol:

```gdscript
const HEX_OBJECT_COLORS: Dictionary = {
    "emp":         Color(0.6, 0.1, 0.8),  # Purple
    "firewall":    Color(0.9, 0.5, 0.1),  # Orange
    "supply_drop": Color(0.1, 0.8, 0.2),  # Green
    "obstacle":    Color(0.4, 0.35, 0.3), # Brown
}
```

### Key Methods

```gdscript
func populate_from_game_state() -> void
# Full rebuild: hex grid, robots, hex objects, fog of war

func update_robot_position(robot_id: String, hex: Vector2i) -> void
func remove_robot(robot_id: String) -> void
func get_robot_sprite(robot_id: String) -> Node2D   # Returns RobotSprite or null

func add_hex_object(obj: Dictionary) -> void
func remove_hex_object(pos_q: int, pos_r: int, type: String) -> void

func highlight_hexes(hexes: Array, color: Color) -> void  # For deploy targeting
func clear_highlights() -> void

func apply_fog_of_war(visible_hexes: Array) -> void

func animate_replay_round(round_replays: Array,
        hex_objects_created: Array, hex_objects_destroyed: Array) -> void
# Animates all robots for one replay round, then applies hex object changes
# Caller should await a Timer after calling this
```

### Click Input

`_input()` converts the mouse position to axial coordinates and emits `hex_clicked(hex: Vector2i)`. Only fires for hexes that exist in the map.

```gdscript
signal hex_clicked(hex: Vector2i)
```

### Map Centering

On `populate_from_game_state()`, the map offset is computed so the average pixel position of all hexes is centered in the viewport.

---

## RobotSprite Node (class_name RobotSprite)

`extends Node2D`. Drawn via `_draw()`. Instantiated as `RobotSprite.new()`.

### Shapes by Type

| Type | Shape |
|------|-------|
| captain | Large filled circle |
| scout | Small filled circle (70% of full size) |
| defender | Filled square |
| engineer | Filled diamond (rotated square) |

### Colors by Team

| Team | Captain | Scout | Defender | Engineer |
|------|---------|-------|----------|----------|
| 0 (Blue) | Strong blue | Light blue | Dark blue | Cyan-blue |
| 1 (Red) | Strong red | Salmon | Dark red | Orange-red |

Player's own robots get a white outline; enemies get a dim gray outline.

A type letter (C/S/D/E) is drawn centered on the shape using the fallback font.

Stunned robots display a red X drawn over the shape.

### Animation Methods

```gdscript
func setup(rid: String, team: int, rtype: String, pos: Vector2i, is_mine: bool) -> void

func animate_move(from_pixel: Vector2, to_pixel: Vector2, duration: float = 0.4) -> void
# Cubic ease-in-out Tween

func animate_bump(push_direction_pixel: Vector2, duration: float = 0.2) -> void
# Short push then return Tween

func show_stunned_flash() -> void
# Red modulate flash (3 loops), sets is_stunned = true

func set_stunned(stunned: bool) -> void
func clear_stunned() -> void
```

---

## Scene Flow

```
MainMenu
  → (game full) → RoleAssignment
                    → (robots spawned) → GameView
                                          → (winner) → GameEnd
                                                          → MainMenu
```

### MainMenu

- Player enters name and selects team size (2 or 3 per team)
- **Create Game**: calls `APIClient.create_game()`, shows game ID to share, polls `get_status()` every 5s
- **Join Game**: player pastes a game ID, calls `APIClient.join_game()`
- Transitions to RoleAssignment when status is `in_progress`

### RoleAssignment

- Each player selects their own role from a dropdown (Captain/Huntsman for 2-player teams; Captain/Huntsman/Engineer for 3-player teams)
- **Assign Roles** button: calls `assign_roles()` with `{player_id: chosen_role}` — partial assignments are valid; the backend accumulates them
- **Spawn Robots** button: calls `spawn_robots()` — any player can trigger this once both teams have assigned all roles; fails with 409 if roles are incomplete
- Polls `get_initial_state()` every 4s; transitions to GameView when robots exist

### GameView

Two alternating phases per turn:

**Input Phase:**
- Robot list on the right panel; click to select
- 6 action slots per robot; toggle Move/Wait per round slot; click a hex to set destination
- Deploy button: enter DEPLOY_TARGETING phase, map highlights valid targets, click to confirm
- Submit button: validates, calls `submit_actions()`, enters REVIEWING phase

**Review Phase:**
- Polls `get_results()` every 3s
- When `ready == true`, plays replay: iterates `replay.rounds` (6 rounds), calls `hex_map.animate_replay_round()` per round, awaits 0.6s between rounds
- After replay, calls `GameState.apply_turn_results()`, starts next Input phase
- If `winner != null`, transitions to GameEnd

### GameEnd

- Displays winning team, turn count
- Return to Main Menu button calls `GameState.clear_saved_state()` then changes scene

---

## Game Flow Sequence

1. `POST /game/create` → get `game_id`, `creator_player_id`, `api_key`
2. Other players: `POST /game/{id}/join` → get `player_id`, `api_key`
3. Each player: `POST /game/{id}/team/{team}/assign_roles` with `{player_id: role}`
4. Any player: `POST /game/{id}/spawn_robots` (fails until both teams fully assigned)
5. Each player: `GET /game/{id}/initial_state` → populate GameState
6. Each player: `POST /game/{id}/submit` with `{turn, actions: [RoundAction×6×N]}`
7. Poll: `GET /game/{id}/results?turn={turn}` until `ready == true`
8. Repeat from step 6 until `winner != null`

---

## Action Submission Format

```gdscript
# TurnInput.build_submit_payload() produces this structure
actions = [
    # One entry per robot per round (6 rounds × N robots)
    {
        "robot_id": "robot_abc123",
        "round_number": 0,            # 0-5
        "action_type": "move",        # or "wait"
        "before_position": [3, -1],   # [q, r]
        "after_position": [4, -1],    # [q, r]
        # Optional deploy (only one deploy per turn per robot):
        "deploy": {
            "type": "emp",
            "target_hexes": [[7, -2]]
        }
    },
    ...
]
```

---

## Replay Playback

The `replay` field in `TurnResultsResponse` contains:

```
replay = {
    "turn": int,
    "rounds": [[RobotRoundReplay, ...], ...],   # 6 rounds, each a list of robot entries
    "hex_objects_created": [HexObject, ...],
    "hex_objects_destroyed": [HexObject, ...],
    "winner": null or int
}
```

Each `RobotRoundReplay`:
```
{
    "robot_id": str,
    "round": int,
    "animation_type": "Move" | "Bump" | "PowerMove" | "Stunned" | "Waiting" | "Puzzled",
    "before_position": [q, r],
    "after_position": [q, r],
    "status": "success" | "fail" | "error" | "stunned" | "win"
}
```

Animation mapping in `HexMap.animate_replay_round()`:

| animation_type | Visual |
|----------------|--------|
| Move, PowerMove | `animate_move(from, to, 0.4s)` tween |
| Bump | `animate_bump(direction, 0.2s)` push-back tween |
| Stunned | `show_stunned_flash()` red flash |
| Waiting, Puzzled | No movement |

Hex object changes are applied at the last round of the replay.

---

## Fog of War

The visible hex set is computed in `HexMap._rebuild_visible_hexes()` by taking the union of `hexes_in_radius(robot.position, sight_range)` for all player robots. Hexes outside this set are darkened; enemies outside this set are not rendered.

---

## Persistence

`GameState` saves `game_id`, `player_id`, `api_key`, `player_name`, `player_team` to `user://last_game.cfg` (ConfigFile format) on every create/join. On startup, `load_saved_state()` pre-fills these fields so the player can rejoin a running game by entering their game ID again.

---

## Security

- **HTTPS**: enforced by Railway (no config needed client-side)
- **API Key**: returned by create/join, stored in `GameState.api_key`, sent as `X-API-Key` header on every authenticated request
- **Server authoritative**: client validates moves locally for UX only; server re-validates on submit

---

## Resources

- [Godot HTTPRequest Docs](https://docs.godotengine.org/en/stable/classes/class_httprequest.html)
- [Hex Grid Guide](https://www.redblobgames.com/grids/hexagons/) — flat-top axial coordinate reference
- [Godot Networking Best Practices](https://docs.godotengine.org/en/stable/tutorials/networking/index.html)
