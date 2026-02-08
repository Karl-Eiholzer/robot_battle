# Godot Client Architecture

## Overview

Design recommendations for Godot game clients that interact with the turn-based multiplayer REST API hosted on Railway. This document covers networking patterns, state management, and performance optimization for hex map turn-based games.

## Godot Version

Recommended: **Godot 4.x** (GDScript 2.0)
- Better HTTPRequest handling
- Improved JSON parsing
- Native async/await support

Compatible with Godot 3.x with minor adjustments.

## Project Structure

```
godot_project/
├── scenes/
│   ├── main_menu.tscn
│   ├── game_lobby.tscn
│   ├── hex_map.tscn
│   └── ui/
│       ├── turn_indicator.tscn
│       └── move_submission.tscn
├── scripts/
│   ├── api_client.gd         # Singleton for API communication
│   ├── game_state.gd         # Singleton for game state management
│   ├── hex_map_manager.gd    # Hex map rendering and interaction
│   └── turn_manager.gd       # Turn flow orchestration
└── autoload/
    ├── APIClient (api_client.gd)
    └── GameState (game_state.gd)
```

## API Client Singleton

### Setup as Autoload

**Project Settings → Autoload:**
- Name: `APIClient`
- Path: `res://scripts/api_client.gd`
- Enable: ✓

### api_client.gd Implementation

```gdscript
extends Node

# Configuration
const BASE_URL = "https://your-railway-app.railway.app"
const API_KEY_STORAGE_PATH = "user://api_key.dat"

var api_key: String = ""
var player_id: String = ""

# Signals for async responses
signal game_created(game_id: String)
signal game_joined(game_data: Dictionary)
signal move_submitted(response: Dictionary)
signal results_received(results: Dictionary)
signal api_error(error_message: String)

func _ready():
    load_api_key()

# Authentication
func load_api_key():
    if FileAccess.file_exists(API_KEY_STORAGE_PATH):
        var file = FileAccess.open(API_KEY_STORAGE_PATH, FileAccess.READ)
        api_key = file.get_as_text()
        file.close()

func save_api_key(key: String):
    var file = FileAccess.open(API_KEY_STORAGE_PATH, FileAccess.WRITE)
    file.store_string(key)
    file.close()
    api_key = key

# HTTP Request Helper
func _make_request(endpoint: String, method: int, body: Dictionary = {}) -> HTTPRequest:
    var http_request = HTTPRequest.new()
    add_child(http_request)
    
    var headers = [
        "Content-Type: application/json",
        "X-API-Key: " + api_key
    ]
    
    var json_body = JSON.stringify(body) if body else ""
    var url = BASE_URL + endpoint
    
    http_request.request(url, headers, method, json_body)
    return http_request

# API Endpoints

func create_game(max_players: int, map_config: Dictionary):
    var body = {
        "max_players": max_players,
        "map_config": map_config
    }
    var request = _make_request("/game/create", HTTPClient.METHOD_POST, body)
    request.request_completed.connect(_on_game_created)

func _on_game_created(result, response_code, headers, body):
    if response_code == 200:
        var json = JSON.parse_string(body.get_string_from_utf8())
        player_id = json.creator_player_id
        save_api_key(player_id)  # Use player_id as API key for MVP
        game_created.emit(json.game_id)
    else:
        api_error.emit("Failed to create game: " + str(response_code))

func join_game(game_id: String, player_name: String):
    var body = {
        "player_name": player_name
    }
    var request = _make_request("/game/" + game_id + "/join", HTTPClient.METHOD_POST, body)
    request.request_completed.connect(_on_game_joined)

func _on_game_joined(result, response_code, headers, body):
    if response_code == 200:
        var json = JSON.parse_string(body.get_string_from_utf8())
        player_id = json.player_id
        save_api_key(player_id)
        game_joined.emit(json)
    else:
        api_error.emit("Failed to join game: " + str(response_code))

func submit_moves(game_id: String, turn: int, moves: Array):
    var body = {
        "turn": turn,
        "moves": moves
    }
    var request = _make_request("/game/" + game_id + "/submit", HTTPClient.METHOD_POST, body)
    request.request_completed.connect(_on_move_submitted)

func _on_move_submitted(result, response_code, headers, body):
    if response_code == 200:
        var json = JSON.parse_string(body.get_string_from_utf8())
        move_submitted.emit(json)
    else:
        api_error.emit("Failed to submit moves: " + str(response_code))

func poll_results(game_id: String, turn: int):
    var endpoint = "/game/" + game_id + "/results?turn=" + str(turn)
    var request = _make_request(endpoint, HTTPClient.METHOD_GET)
    request.request_completed.connect(_on_results_polled)

func _on_results_polled(result, response_code, headers, body):
    if response_code == 200:
        var json = JSON.parse_string(body.get_string_from_utf8())
        results_received.emit(json)
    else:
        api_error.emit("Failed to poll results: " + str(response_code))

func get_game_status(game_id: String):
    var endpoint = "/game/" + game_id + "/status"
    var request = _make_request(endpoint, HTTPClient.METHOD_GET)
    # Connect to appropriate handler
```

## Game State Singleton

### game_state.gd

```gdscript
extends Node

# Current game state
var game_id: String = ""
var current_turn: int = 0
var player_id: String = ""
var game_state: String = ""  # "waiting", "planning", "submitted", "processing"

# Game data
var hex_map: Dictionary = {}
var unit_positions: Dictionary = {}
var player_resources: Dictionary = {}

# Pending moves for current turn
var pending_moves: Array = []

signal turn_changed(new_turn: int)
signal state_changed(new_state: String)
signal map_updated(updates: Array)

func initialize_game(game_data: Dictionary):
    game_id = game_data.game_id
    player_id = game_data.player_id
    hex_map = game_data.map
    current_turn = 0
    change_state("planning")

func add_move(unit_id: String, action: String, target):
    pending_moves.append({
        "unit_id": unit_id,
        "action": action,
        "target": target
    })

func clear_pending_moves():
    pending_moves.clear()

func submit_turn():
    if pending_moves.size() > 0:
        APIClient.submit_moves(game_id, current_turn, pending_moves)
        change_state("submitted")
        clear_pending_moves()

func apply_turn_results(results: Dictionary):
    # Apply delta updates to game state
    for update in results.updates:
        if "unit_id" in update:
            if "destroyed" in update and update.destroyed:
                unit_positions.erase(update.unit_id)
            else:
                if "position" in update:
                    unit_positions[update.unit_id] = update.position
                # Apply other attribute changes
    
    current_turn = results.next_turn
    change_state("planning")
    turn_changed.emit(current_turn)
    map_updated.emit(results.updates)

func change_state(new_state: String):
    game_state = new_state
    state_changed.emit(new_state)
```

## Turn Manager

### turn_manager.gd

```gdscript
extends Node

# Polling configuration
const POLL_INTERVAL_MIN = 3.0  # seconds
const POLL_INTERVAL_MAX = 10.0
var current_poll_interval = 5.0

var polling_timer: Timer
var is_polling: bool = false

func _ready():
    polling_timer = Timer.new()
    add_child(polling_timer)
    polling_timer.timeout.connect(_poll_for_results)
    
    # Connect to game state changes
    GameState.state_changed.connect(_on_state_changed)
    APIClient.results_received.connect(_on_results_received)
    APIClient.move_submitted.connect(_on_move_submitted)

func _on_state_changed(new_state: String):
    if new_state == "submitted":
        start_polling()
    elif new_state == "planning":
        stop_polling()

func _on_move_submitted(response: Dictionary):
    if response.processing:
        # Turn processing started immediately
        print("Turn processing started automatically")

func start_polling():
    if not is_polling:
        is_polling = true
        polling_timer.wait_time = current_poll_interval
        polling_timer.start()

func stop_polling():
    is_polling = false
    polling_timer.stop()

func _poll_for_results():
    APIClient.poll_results(GameState.game_id, GameState.current_turn)

func _on_results_received(results: Dictionary):
    if results.ready:
        stop_polling()
        GameState.apply_turn_results(results)
    else:
        # Continue polling, maybe adjust interval
        pass

func set_poll_interval(seconds: float):
    current_poll_interval = clamp(seconds, POLL_INTERVAL_MIN, POLL_INTERVAL_MAX)
```

## Hex Map Manager

### hex_map_manager.gd

```gdscript
extends Node2D

# Hex grid configuration
const HEX_SIZE = 64  # pixels
const HEX_LAYOUT = "pointy_top"  # or "flat_top"

var hex_tiles: Dictionary = {}  # {coordinate: TileSprite}
var units: Dictionary = {}      # {unit_id: UnitSprite}

signal hex_clicked(coordinate: Vector2)
signal unit_selected(unit_id: String)

func initialize_map(map_data: Dictionary):
    clear_map()
    
    # Create hex tiles from map data
    for hex_data in map_data.hexes:
        var coord = Vector2(hex_data.q, hex_data.r)  # Axial coordinates
        var tile = create_hex_tile(coord, hex_data.terrain)
        hex_tiles[coord] = tile
        add_child(tile)
    
    # Position camera to center of map
    center_camera()

func create_hex_tile(coord: Vector2, terrain: String) -> Sprite2D:
    var tile = Sprite2D.new()
    tile.texture = load("res://assets/terrain/" + terrain + ".png")
    tile.position = axial_to_pixel(coord)
    # Add input detection, etc.
    return tile

func axial_to_pixel(coord: Vector2) -> Vector2:
    # Convert axial coordinates (q, r) to pixel position
    var x = HEX_SIZE * (3.0/2.0 * coord.x)
    var y = HEX_SIZE * (sqrt(3.0)/2.0 * coord.x + sqrt(3.0) * coord.y)
    return Vector2(x, y)

func pixel_to_axial(pixel: Vector2) -> Vector2:
    # Convert pixel position to axial coordinates
    var q = (2.0/3.0 * pixel.x) / HEX_SIZE
    var r = (-1.0/3.0 * pixel.x + sqrt(3.0)/3.0 * pixel.y) / HEX_SIZE
    return Vector2(round(q), round(r))

func update_map(updates: Array):
    # Apply delta updates from turn results
    for update in updates:
        if "unit_id" in update:
            if "destroyed" in update and update.destroyed:
                remove_unit(update.unit_id)
            elif "position" in update:
                move_unit(update.unit_id, update.position)
            
            # Update unit properties
            if update.unit_id in units:
                var unit = units[update.unit_id]
                if "hp" in update:
                    unit.update_hp(update.hp)

func move_unit(unit_id: String, new_coord: Array):
    if unit_id in units:
        var unit = units[unit_id]
        var target_pos = axial_to_pixel(Vector2(new_coord[0], new_coord[1]))
        
        # Animate movement
        var tween = create_tween()
        tween.tween_property(unit, "position", target_pos, 0.5)

func remove_unit(unit_id: String):
    if unit_id in units:
        units[unit_id].queue_free()
        units.erase(unit_id)

func clear_map():
    for tile in hex_tiles.values():
        tile.queue_free()
    hex_tiles.clear()
    
    for unit in units.values():
        unit.queue_free()
    units.clear()
```

## UI Flow

### Main Menu Scene
```gdscript
# main_menu.gd
extends Control

func _on_create_game_pressed():
    var map_config = generate_default_map()
    APIClient.create_game(4, map_config)
    
    APIClient.game_created.connect(_on_game_created)

func _on_game_created(game_id: String):
    # Save game_id, transition to lobby
    get_tree().change_scene_to_file("res://scenes/game_lobby.tscn")

func _on_join_game_pressed():
    var game_id = $GameIDInput.text
    var player_name = $PlayerNameInput.text
    APIClient.join_game(game_id, player_name)
    
    APIClient.game_joined.connect(_on_game_joined)

func _on_game_joined(game_data: Dictionary):
    GameState.initialize_game(game_data)
    get_tree().change_scene_to_file("res://scenes/hex_map.tscn")
```

### Game Scene (Hex Map)
```gdscript
# hex_map.gd
extends Node2D

@onready var hex_map_manager = $HexMapManager
@onready var ui = $UI

func _ready():
    # Initialize map with data from GameState
    hex_map_manager.initialize_map(GameState.hex_map)
    
    # Connect signals
    GameState.map_updated.connect(_on_map_updated)
    GameState.turn_changed.connect(_on_turn_changed)
    
    ui.update_turn_display(GameState.current_turn)

func _on_map_updated(updates: Array):
    hex_map_manager.update_map(updates)

func _on_turn_changed(new_turn: int):
    ui.update_turn_display(new_turn)
    ui.show_notification("Turn " + str(new_turn) + " begins!")

func _on_submit_turn_pressed():
    GameState.submit_turn()
    ui.show_notification("Waiting for other players...")
```

## Performance Optimization

### Map Data Handling

**Initial Load (Large Payload):**
- Load hex map once on game join
- Cache in GameState singleton
- Render progressively (load visible tiles first)

**Turn Updates (Small Payloads):**
- Only receive changed units/tiles
- Apply deltas to existing state
- Minimal network traffic

### Memory Management

```gdscript
# Only keep visible hex tiles in memory
func optimize_tile_rendering():
    var camera_viewport = get_viewport_rect()
    
    for coord in hex_tiles.keys():
        var tile = hex_tiles[coord]
        if not is_tile_visible(tile, camera_viewport):
            tile.hide()  # Or remove from scene tree
        else:
            tile.show()
```

### Polling Optimization

**Adaptive Polling Interval:**
```gdscript
func adjust_poll_interval(response: Dictionary):
    if response.moves_submitted < response.moves_required:
        # Most players haven't submitted, poll less frequently
        current_poll_interval = POLL_INTERVAL_MAX
    else:
        # Almost ready, poll more frequently
        current_poll_interval = POLL_INTERVAL_MIN
```

## Error Handling

### Connection Failures
```gdscript
func _on_api_error(error_message: String):
    show_error_dialog(error_message)
    
    # Retry logic
    if error_message.contains("timeout"):
        retry_last_request()

func retry_last_request():
    # Store last request details and retry
    pass
```

### Invalid Game State
```gdscript
func validate_game_state() -> bool:
    if GameState.game_id.is_empty():
        push_error("No active game")
        return false
    
    if GameState.current_turn < 0:
        push_error("Invalid turn number")
        return false
    
    return true
```

## Testing Strategy

### Local Testing Without API
```gdscript
# mock_api_client.gd
extends Node

# Override APIClient for testing
func create_game(max_players: int, map_config: Dictionary):
    await get_tree().create_timer(0.5).timeout
    game_created.emit("test_game_123")

func join_game(game_id: String, player_name: String):
    await get_tree().create_timer(0.5).timeout
    var mock_data = {
        "game_id": game_id,
        "player_id": "test_player",
        "map": generate_test_map()
    }
    game_joined.emit(mock_data)
```

### Integration Testing
1. Test API endpoints with real Railway backend
2. Simulate slow network (adjust poll intervals)
3. Test with multiple Godot instances (multiplayer simulation)

## Configuration Management

### Config File (config.json)
```json
{
    "api": {
        "base_url": "https://your-app.railway.app",
        "poll_interval": 5
    },
    "game": {
        "hex_size": 64,
        "camera_speed": 500
    }
}
```

### Load Configuration
```gdscript
func load_config():
    var file = FileAccess.open("res://config.json", FileAccess.READ)
    var json = JSON.parse_string(file.get_as_text())
    
    APIClient.BASE_URL = json.api.base_url
    TurnManager.current_poll_interval = json.api.poll_interval
```

## Security Considerations

### API Key Storage
- Store in `user://` directory (platform-specific, sandboxed)
- Never commit to version control
- Consider encryption for production

### Move Validation
- Client-side validation (UX)
- Server authoritative (security)
- Don't trust client state

### Network Security
- HTTPS enforced by Railway
- No sensitive data in URLs (use POST body)

## Next Steps for Godot Implementation

1. Create basic project structure with autoload singletons
2. Implement APIClient with HTTPRequest
3. Build simple UI for game creation/joining
4. Test API connectivity with Railway backend
5. Implement hex map rendering (start with basic tiles)
6. Add unit selection and move planning
7. Integrate turn submission and polling
8. Polish with animations and UI feedback
9. Performance testing with large maps
10. Multiplayer testing with multiple instances

## Resources

- [Godot HTTPRequest Docs](https://docs.godotengine.org/en/stable/classes/class_httprequest.html)
- [Hex Grid Guide](https://www.redblobgames.com/grids/hexagons/) - Essential reading for hex math
- [Godot Networking Best Practices](https://docs.godotengine.org/en/stable/tutorials/networking/index.html)
