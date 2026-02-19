# API & Backend Architecture

## Overview

Turn-based multiplayer robot battle API hosted on Railway with Redis state management. Players control teams of robots on a hex map. Each turn, all players simultaneously submit 6-round action plans; the server processes them and returns a full replay.

## Technology Stack

- **Framework**: FastAPI (Python 3.11.7)
- **Database**: Redis (game state, sessions, robot data)
- **Hosting**: Railway (auto-deploy from GitHub main branch)
- **Security**: HTTPS (automatic via Railway) + API key authentication

## Architecture Pattern

1. Players create or join a game → receive `api_key` for all subsequent requests
2. Each team assigns roles (captain/huntsman/engineer) via the API
3. Any player calls `spawn_robots` once both teams have complete role assignments
4. Each player calls `initial_state` to receive their starting view of the game
5. Each turn: all players simultaneously submit a 6-round action plan
6. When the last player submits, the server auto-triggers turn processing (background task)
7. Players poll `results` until `ready == true`, then animate the replay
8. Repeat until a captain is captured (`winner` field is set)

---

## Project Structure

```
backend/
├── main.py          # FastAPI app, all endpoints
├── models.py        # Pydantic request/response models
├── redis_client.py  # Redis connection and data access layer
├── game_logic.py    # Turn processing: collision rules, fog of war, map generation
├── auth.py          # API key generation and verification
├── config.py        # Environment variables and TTL constants
├── requirements.txt
├── Procfile
└── runtime.txt
```

**requirements.txt:**
```
fastapi==0.109.0
uvicorn[standard]==0.27.0
redis==5.0.1
pydantic==2.5.3
python-dotenv==1.0.0
```

**Procfile:**
```
web: uvicorn main:app --host 0.0.0.0 --port $PORT
```

---

## Redis Data Model

### Key Structure

```
game:{game_id}:meta                → Hash: state, current_turn, player_count,
                                            max_players, created_at,
                                            initiative_team, team_size
game:{game_id}:players             → Set:  player_ids
game:{game_id}:player_info:{pid}   → Hash: player_name, team
game:{game_id}:map                 → String: JSON map data
game:{game_id}:variables           → String: JSON GameVariables
game:{game_id}:robots              → String: JSON list of all Robot objects
game:{game_id}:team:{team}:roles   → Hash:  player_id → role_name
game:{game_id}:hex_objects         → String: JSON list of HexObject
game:{game_id}:turn:{n}:moves      → Hash:  player_id → move_data_json
game:{game_id}:turn:{n}:results    → String: JSON turn result data
game:{game_id}:turn:{n}:replay     → String: JSON TurnReplay data

player:{player_id}:current_game    → String: game_id
player:{player_id}:api_key         → String: api_key  (player → key)
api_key:{api_key}                  → String: player_id (key → player, used for auth)
```

### Game States

- `waiting_for_players` — accepting joins
- `in_progress` — active, accepting move submissions
- `processing_turn` — turn processing background task running
- `complete` — game finished (captain captured)

### TTL

- Active games: 24 hours (refreshed on any write)
- Completed games: 1 hour
- Player sessions / API keys: 48 hours (refreshed on every authenticated request)

---

## Data Models

### GameVariables

Sent at game creation; stored in `game:{game_id}:variables`.

```json
{
  "team_size": 2,           // players per team: 2 or 3
  "map_size": "medium",     // "small", "medium", "large"
  "input_time": 90,         // seconds for action input phase
  "review_time": 40,        // seconds to review replay
  "starting_energy": 2      // initial energy per robot (0-3)
}
```

### Robot Types

| type | moves/turn | max_energy | deploy | sight | strength |
|------|-----------|------------|--------|-------|----------|
| captain | 3 | 2 | emp | 5 | 7 |
| scout | 4 | 6 | extra_moves | 7 | 3 |
| defender | 2 | 3 | firewall | 3 | 5 |
| engineer | 6 | 3 | supply_drop | 5 | 0 |

Win condition: a team wins when the opposing team's Captain robot is captured.

### Player Roles

Roles determine which robot types a player controls.

**2-player teams (team_size=2): captain or huntsman**

| role | robots |
|------|--------|
| captain | 1 captain + 2 defenders + 2 engineers |
| huntsman | 4 scouts + 1 engineer |

**3-player teams (team_size=3): captain, huntsman, or engineer**

| role | robots |
|------|--------|
| captain | 1 captain + 3 defenders |
| huntsman | 5 scouts |
| engineer | 5 engineers |

### Robot Object

```json
{
  "robot_id": "robot_abc123",
  "player_id": "player_xyz",
  "team": 0,
  "type": "captain",
  "position": [3, -1],         // [q, r] axial coordinates
  "energy": 2,
  "state": "active",           // "active" or "stunned"
  "spawn_position": [1, -1],
  "extra_moves_this_turn": 0   // reset to 0 at start of each turn
}
```

### RoundAction

One round's action for one robot. Players submit 6 of these per robot per turn.

```json
{
  "robot_id": "robot_abc123",
  "round_number": 0,          // 0-5
  "action_type": "move",      // "move" or "wait"
  "before_position": [3, -1],
  "after_position": [4, -1],  // same as before if action_type == "wait"
  "deploy": null              // or DeployAction
}
```

### DeployAction

```json
{
  "type": "emp",                    // emp, firewall, supply_drop, extra_moves
  "target_hexes": [[7, -2]]
}
```

Deploy ranges:
- `emp` (Captain): hexes 4-6 away — stuns robots caught in blast
- `firewall` (Defender): hexes ~4 away — places blocking hex object
- `supply_drop` (Engineer): adjacent hex — restores energy to nearby robots
- `extra_moves` (Scout): self — grants additional moves this turn, no targeting

### HexObject

```json
{
  "type": "emp",         // emp, firewall, supply_drop, obstacle
  "position": [5, -2],
  "created_turn": 3,
  "created_by": "player_xyz"  // null for map obstacles
}
```

### TurnReplay

Returned in `TurnResultsResponse.replay` after turn processing completes.

```json
{
  "turn": 5,
  "rounds": [                   // 6 entries, one per round
    [                           // round 0: list of RobotRoundReplay
      {
        "robot_id": "robot_abc",
        "round": 0,
        "animation_type": "Move",   // Move, Bump, PowerMove, Stunned, Waiting, Puzzled
        "before_position": [3, -1],
        "after_position": [4, -1],
        "status": "success"         // success, fail, error, stunned, win
      }
    ],
    ...                         // rounds 1-5
  ],
  "hex_objects_created": [...],
  "hex_objects_destroyed": [...],
  "winner": null                // null or 0 or 1 (winning team number)
}
```

---

## API Endpoints

### Authentication

- `POST /game/create` and `POST /game/{id}/join` — **no authentication required**
- All other endpoints — require `X-API-Key: <api_key>` header

The `api_key` is returned by create and join. It is separate from the `player_id`.

---

### `GET /health`

Health check, no authentication.

**Response:**
```json
{
  "status": "healthy",
  "redis": true,
  "environment": "production"
}
```

---

### `POST /game/create`

Create a new game. Creator is automatically placed on team 0.

**Request:**
```json
{
  "max_players": 4,
  "map_config": {
    "width": 15,
    "height": 15,
    "terrain_data": null
  },
  "game_variables": {
    "team_size": 2,
    "map_size": "medium",
    "input_time": 90,
    "review_time": 40,
    "starting_energy": 2
  }
}
```

`game_variables` is optional; defaults to `team_size=2` and the values shown above.

**Response:**
```json
{
  "game_id": "game_abc123def456",
  "creator_player_id": "player_abc123def456",
  "api_key": "uuid-api-key",
  "state": "waiting_for_players",
  "max_players": 4
}
```

**Backend logic:**
- Generates `game_id` (`game_` + 12 hex chars), `player_id`, and `api_key` (UUID)
- Stores bidirectional key mapping in Redis
- Generates map from `map_config` + `game_variables`
- Stores `meta`, `map`, and `variables` in Redis
- Creator joins as `player_count=1`, team 0

---

### `POST /game/{game_id}/join`

Join an existing game. Fails if game is not in `waiting_for_players` state or is full.

**Request:**
```json
{"player_name": "PlayerOne"}
```

**Response:**
```json
{
  "game_id": "game_abc123def456",
  "player_id": "player_xyz789",
  "api_key": "uuid-api-key",
  "map": {...},
  "current_players": 2,
  "max_players": 4,
  "state": "waiting_for_players"
}
```

**Team assignment:** Players are split by join order. For `max_players=4`: players 0–1 → team 0, players 2–3 → team 1. Generally: `team = 0 if current_count < max_players // 2 else 1`.

**Auto-transition:** When `player_count == max_players`, state automatically changes to `in_progress` (backward compatibility; the new flow proceeds to role assignment before spawning robots).

---

### `GET /game/{game_id}/status`

Requires authentication.

**Response:**
```json
{
  "game_id": "game_abc123",
  "state": "in_progress",
  "current_turn": 5,
  "moves_submitted": 3,
  "moves_required": 4,
  "all_moves_in": false
}
```

---

### `POST /game/{game_id}/team/{team}/assign_roles`

Requires authentication. Assigns roles to players on a team. Can be called with partial assignments; each call accumulates. The backend validates that no role is assigned twice on the same team.

`team` path parameter: 0 or 1.

**Request:**
```json
{
  "team": 0,
  "role_assignments": {
    "player_abc": "captain"
  }
}
```

`role_assignments` is a dict of `player_id → role_name`. For `team_size=2` the valid roles are `captain` and `huntsman`. For `team_size=3` the valid roles are `captain`, `huntsman`, and `engineer`.

**Response:**
```json
{
  "success": true,
  "team": 0,
  "roles_assigned": {"player_abc": "captain"}
}
```

---

### `POST /game/{game_id}/spawn_robots`

Requires authentication. Creates all robot instances from role assignments and transitions game to active play. Fails with 409 if either team has not fully assigned roles.

Any player can call this once both teams are ready.

**Response:**
```json
{
  "success": true,
  "robots_created": 10,
  "robots": [...]
}
```

**Backend logic:**
- Validates role assignments for both teams
- Calls `spawn_robots_for_game()` which places robots at spawn positions on the map
- Calls `store_robots()` and `store_hex_objects([], ...)` (starts empty)
- Sets game state to `in_progress`
- Robots recover `state="active"` and `extra_moves_this_turn=0` at the start of each turn

---

### `GET /game/{game_id}/initial_state`

Requires authentication. Returns the full starting view for the requesting player, with fog of war applied to enemies.

**Response:**
```json
{
  "game_id": "game_abc123",
  "current_turn": 0,
  "team_with_initiative": 1,
  "map": {
    "hexes": [{"q": 0, "r": 0, "terrain": "plains"}, ...],
    "width": 15,
    "height": 15,
    "spawn_points": {...}
  },
  "game_variables": {"team_size": 2, "input_time": 90, ...},
  "player_robots": [
    {
      "robot_id": "robot_abc",
      "player_id": "player_xyz",
      "team": 0,
      "type": "captain",
      "position": [2, -1],
      "energy": 2,
      "state": "active",
      "spawn_position": [2, -1],
      "extra_moves_this_turn": 0
    }
  ],
  "other_robots": [
    {
      "robot_id": "robot_enemy",
      "team": 1,
      "type": "scout",
      "position": [10, -3]
    }
  ],
  "hex_objects": []
}
```

`player_robots` — full data for the requesting player's own robots.
`other_robots` — partial data (no energy) for enemy robots visible within sight range of any friendly robot. Enemies out of sight range are omitted entirely.

---

### `POST /game/{game_id}/submit`

Requires authentication. Submit action plan for the current turn. Each player submits once. Duplicate submissions return 409.

**Request:**
```json
{
  "turn": 5,
  "actions": [
    {
      "robot_id": "robot_abc",
      "round_number": 0,
      "action_type": "move",
      "before_position": [3, -1],
      "after_position": [4, -1],
      "deploy": null
    },
    {
      "robot_id": "robot_abc",
      "round_number": 1,
      "action_type": "wait",
      "before_position": [4, -1],
      "after_position": [4, -1],
      "deploy": {
        "type": "emp",
        "target_hexes": [[7, -2]]
      }
    }
  ]
}
```

Submit one `RoundAction` per robot per round (6 rounds × N robots = 6N entries total).

The legacy `moves` field (list of `MoveAction`) is still accepted for backward compatibility but carries no game logic in Phase 2+.

**Response:**
```json
{
  "success": true,
  "turn": 5,
  "moves_submitted": 4,
  "moves_required": 4,
  "processing": true,
  "validation_errors": []
}
```

`processing: true` means this submission triggered turn processing (last player to submit).
`validation_errors` contains server-side validation warnings (submission still accepted).

**Backend logic:**
- Validates turn number matches `current_turn`
- Validates actions against robot ownership and move limits
- Stores in `game:{game_id}:turn:{n}:moves`
- If all players have submitted: sets state to `processing_turn`, enqueues background task

---

### `GET /game/{game_id}/results`

Requires authentication. Poll after submitting; call every 3 seconds until `ready == true`.

**Query parameter:** `turn` (int)

**Response when not ready:**
```json
{
  "ready": false,
  "turn": 5,
  "state": "processing_turn"
}
```

**Response when ready:**
```json
{
  "ready": true,
  "turn": 5,
  "state": "in_progress",
  "updates": [...],
  "events": [...],
  "next_turn": 6,
  "replay": {
    "turn": 5,
    "rounds": [[...], [...], [...], [...], [...], [...]],
    "hex_objects_created": [...],
    "hex_objects_destroyed": [...],
    "winner": null
  },
  "updated_robots": [...],
  "updated_hex_objects": [...],
  "winner": null
}
```

`updated_robots` — same fog-of-war split as `initial_state`: full data for own robots, partial for visible enemies.
`winner` — `null` or the winning team number (0 or 1).

---

## Turn Processing

### Auto-Trigger

When the last player submits their actions:

```python
if moves_submitted >= moves_required:
    redis_client.update_game_state(game_id, "processing_turn")
    background_tasks.add_task(process_turn, game_id, request.turn)
```

### Background Task

```python
async def process_turn(game_id: str, turn: int):
    await asyncio.sleep(0.5)   # ensure all moves are written

    moves = redis_client.get_turn_moves(game_id, turn)
    results = calculate_turn_results(moves, game_id)
    redis_client.store_turn_results(game_id, turn, results)

    winner = check_win_condition(game_id)

    if winner is not None:
        redis_client.update_game_state(game_id, "complete")
    else:
        redis_client.increment_turn(game_id)
        redis_client.flip_initiative(game_id)
        redis_client.update_game_state(game_id, "in_progress")
        # Reset per-turn robot fields
        for robot in redis_client.get_robots(game_id):
            robot["extra_moves_this_turn"] = 0
            robot["state"] = "active"     # stunned robots recover
        redis_client.store_robots(game_id, robots)
```

`calculate_turn_results(moves, game_id)` processes all 6 rounds sequentially using the 12-case collision ruleset (see `game_logic.py`). It produces replay data stored separately via `store_turn_replay()`.

### Win Condition

`check_win_condition(game_id)` checks whether any Captain robot has been captured (removed from the robots list). Returns the winning team number (0 or 1), or `None` if no winner yet.

### Initiative

`initiative_team` is stored in the game meta hash. It is set randomly at game creation and flipped after every turn (`flip_initiative()`). The initiative team moves first within each round when collision resolution order matters.

---

## Authentication

### Key Generation

Both create and join generate an independent `api_key` (UUID) and `player_id` (`player_` + 12 hex chars).

```python
def generate_api_key() -> str:
    return str(uuid.uuid4())

def generate_player_id() -> str:
    return f"player_{uuid.uuid4().hex[:12]}"
```

### Redis Storage (bidirectional)

```python
def store_player_key(player_id: str, api_key: str):
    redis.set(f"player:{player_id}:api_key", api_key, ex=TTL_PLAYER_SESSION)
    redis.set(f"api_key:{api_key}", player_id, ex=TTL_PLAYER_SESSION)
```

### FastAPI Dependency

Used on all authenticated endpoints:

```python
async def get_current_player(x_api_key: str = Header(...)) -> str:
    player_id = redis.get(f"api_key:{x_api_key}")
    if not player_id:
        raise HTTPException(status_code=401, detail="Invalid or expired API key")
    refresh_api_key_ttl(x_api_key)   # keeps session alive
    return player_id
```

---

## Configuration

### Environment Variables

| Variable | Source | Default | Required |
|----------|--------|---------|----------|
| `REDIS_URL` | Railway (auto-injected) | `redis://localhost:6379` | Yes |
| `API_SECRET` | Railway dashboard | `dev_secret_key` | Yes |
| `ENVIRONMENT` | Railway dashboard | `development` | No |

### TTL Constants (config.py)

```python
TTL_ACTIVE_GAME    = 24 * 60 * 60   # 24 hours
TTL_COMPLETED_GAME =  1 * 60 * 60   # 1 hour
TTL_PLAYER_SESSION = 48 * 60 * 60   # 48 hours
```

---

## Deployment

Railway auto-deploys from the GitHub `main` branch. The backend root directory is `/backend`.

```bash
# Manual deploy (if needed)
railway login
railway link
railway up
```

Test against the deployed API:
```bash
python test_api.py https://robotbattle-production.up.railway.app      # Phase 1 tests (14 tests)
python test_full_game.py https://robotbattle-production.up.railway.app # Phase 2 tests (30 tests)
```

---

## Error Responses

All errors use the standard FastAPI format:

```json
{"detail": "Human-readable error message"}
```

Common status codes:

| Code | Meaning |
|------|---------|
| 401 | Invalid or expired API key |
| 403 | Player not in this game |
| 404 | Game not found |
| 409 | Game full / wrong state / already submitted / roles incomplete |
| 500 | Turn processing error (game state reset to in_progress so players can retry) |

---

## Security

- **HTTPS**: enforced by Railway, no client configuration needed
- **API key per player**: generated at create/join, stored in Redis with TTL; separate from player_id
- **Player isolation**: all authenticated endpoints verify the requesting player is in the game before returning data
- **Fog of war**: `initial_state` and `results` filter enemy robot data by sight range; out-of-sight enemies are omitted entirely
- **Server authoritative**: client-submitted `before_position`/`after_position` are validated against actual robot positions

---

## Scaling Notes

### Current (MVP)
- Single FastAPI instance, background tasks for turn processing
- Redis for all state; no database
- Suitable for 10–100 concurrent games

### Future
- Separate worker service for turn processing (Railway background worker)
- WebSocket connections to eliminate polling
- Horizontal API scaling with Redis pub/sub for result notification
