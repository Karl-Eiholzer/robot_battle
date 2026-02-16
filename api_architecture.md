# API & Backend Architecture

## Overview

Turn-based multiplayer game API hosted on Railway with Redis state management. Supports simultaneous move submission with auto-triggered turn processing and client polling for results.

## Technology Stack

- **Framework**: FastAPI (Python)
- **Database**: Redis (for game state, sessions, and real-time data)
- **Hosting**: Railway
- **Deployment**: Direct from GitHub via Railway CLI
- **Security**: HTTPS (automatic via Railway) + API Key authentication

## Architecture Pattern

**Client-Server Turn-Based Flow:**
1. All players submit moves simultaneously for current turn
2. When last move received → auto-trigger turn processing
3. Clients poll for results (3-10 second intervals)
4. Results delivered as delta updates (not full game state)

## Redis Data Model

### Key Structure

```
game:{game_id}:meta          → Hash: {state, current_turn, player_count, created_at, max_players}
game:{game_id}:players       → Set: player_ids
game:{game_id}:turn:{n}:moves → Hash: {player_id: move_data_json}
game:{game_id}:turn:{n}:results → String: JSON result data
game:{game_id}:map           → String: Initial hex map JSON (large, sent once)
player:{player_id}:current_game → String: game_id
player:{player_id}:api_key   → String: authentication key
```

### Game States

- `waiting_for_players` - Game created, accepting joins
- `in_progress` - Game active, accepting moves
- `processing_turn` - Computing turn results
- `complete` - Game finished

### TTL (Time-to-Live)

- Active games: 24 hours from last activity
- Completed games: 1 hour after completion
- Player sessions: 48 hours

## API Endpoints

### Authentication
All endpoints require `X-API-Key` header with valid player API key.

### Game Management

#### `POST /game/create`
Create new game instance.

**Request:**
```json
{
  "max_players": 4,
  "map_config": {
    "width": 20,
    "height": 20,
    "terrain_data": {...}
  }
}
```

**Response:**
```json
{
  "game_id": "abc123",
  "creator_player_id": "player_uuid",
  "state": "waiting_for_players"
}
```

**Backend Logic:**
- Generate unique game_id
- Store map data in `game:{game_id}:map`
- Initialize meta with state="waiting_for_players", current_turn=0
- Return game_id to creator

---

#### `POST /game/{game_id}/join`
Player joins existing game.

**Request:**
```json
{
  "player_name": "PlayerOne"
}
```

**Response:**
```json
{
  "game_id": "abc123",
  "player_id": "player_uuid",
  "map": {...},  // Full hex map JSON
  "current_players": 2,
  "max_players": 4
}
```

**Backend Logic:**
- Verify game exists and state="waiting_for_players"
- Add player_id to `game:{game_id}:players` set
- Return full map data from `game:{game_id}:map`
- If player_count == max_players, update state to "in_progress"

---

#### `GET /game/{game_id}/status`
Check game status and turn state.

**Response:**
```json
{
  "game_id": "abc123",
  "state": "in_progress",
  "current_turn": 5,
  "moves_submitted": 3,
  "moves_required": 4,
  "all_moves_in": false
}
```

---

### Turn Management

#### `POST /game/{game_id}/submit`
Submit move for current turn.

**Request:**
```json
{
  "turn": 5,
  "moves": [
    {"unit_id": "u1", "action": "move", "target": [5, 3]},
    {"unit_id": "u2", "action": "attack", "target": "enemy_u1"}
  ]
}
```

**Response:**
```json
{
  "success": true,
  "turn": 5,
  "moves_submitted": 4,
  "moves_required": 4,
  "processing": true  // Auto-triggered if last submission
}
```

**Backend Logic:**
- Verify game state is "in_progress"
- Verify turn number matches current_turn
- Store move data in `game:{game_id}:turn:{n}:moves` hash with player_id as key
- Check if HLEN(moves) == player_count
- **If all moves submitted:**
  - Update game state to "processing_turn"
  - **Trigger background task for turn processing**

---

#### `GET /game/{game_id}/results`
Poll for turn results.

**Query Parameters:**
- `turn` (int): Turn number to check

**Response (not ready):**
```json
{
  "ready": false,
  "turn": 5,
  "state": "processing_turn"
}
```

**Response (ready):**
```json
{
  "ready": true,
  "turn": 5,
  "updates": [
    {"unit_id": "u1", "position": [5, 3], "hp": 80},
    {"unit_id": "u2", "destroyed": true},
    {"resource": "gold", "player_id": "p1", "amount": 150}
  ],
  "events": [
    {"type": "combat", "attacker": "u1", "defender": "u3", "damage": 20}
  ],
  "next_turn": 6
}
```

**Backend Logic:**
- Check if `game:{game_id}:turn:{n}:results` exists
- If exists, parse and return JSON
- If not exists, return ready=false

---

## Turn Processing Logic

### Auto-Trigger Mechanism

When last move is submitted in `/game/{game_id}/submit`:

```python
from fastapi import BackgroundTasks

@app.post("/game/{game_id}/submit")
async def submit_move(game_id: str, move_data: MoveData, 
                      background_tasks: BackgroundTasks):
    # ... store move ...
    
    if all_moves_submitted:
        background_tasks.add_task(process_turn, game_id, current_turn)
    
    return response
```

### Processing Function

```python
async def process_turn(game_id: str, turn: int):
    # 1. Fetch all moves
    moves = redis.hgetall(f"game:{game_id}:turn:{turn}:moves")
    
    # 2. Run game logic (your custom implementation)
    results = calculate_turn_results(moves)
    
    # 3. Store results
    redis.set(f"game:{game_id}:turn:{turn}:results", 
              json.dumps(results))
    
    # 4. Update game state
    redis.hincrby(f"game:{game_id}:meta", "current_turn", 1)
    redis.hset(f"game:{game_id}:meta", "state", "in_progress")
    
    # 5. Check win conditions
    if game_complete:
        redis.hset(f"game:{game_id}:meta", "state", "complete")
```

### Game Logic Module

Create separate `game_logic.py` module:

```python
def calculate_turn_results(moves: dict) -> dict:
    """
    Process all player moves and return delta updates.
    
    Args:
        moves: {player_id: move_data_json}
    
    Returns:
        {
            "updates": [...],  # Unit/state changes
            "events": [...]    # Combat, resource changes, etc.
        }
    """
    # Your hex map game logic here
    # - Resolve movement
    # - Calculate combat
    # - Update resources
    # - Generate events
    
    return results
```

## Authentication

### Simple API Key Approach

**Player Registration/Key Generation:**
- During game join or initial connection, generate UUID-based API key
- Store in `player:{player_id}:api_key`
- Return to client (client stores securely)

**Middleware:**
```python
from fastapi import Header, HTTPException

async def verify_api_key(x_api_key: str = Header(...)):
    # Verify key exists in Redis
    player_id = redis.get(f"api_key:{x_api_key}")
    if not player_id:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return player_id
```

**Godot sends:**
```
X-API-Key: player_uuid_generated_key
```

## Deployment on Railway

### Environment Variables

Railway automatically injects:
- `REDIS_URL` - Connection string to Redis instance

Your app needs:
- `API_SECRET` - Secret for generating API keys (set in Railway dashboard)
- `ENVIRONMENT` - "production" or "development"

### Project Structure

```
project/
├── main.py              # FastAPI app entry point
├── models.py            # Pydantic models for requests/responses
├── redis_client.py      # Redis connection and helpers
├── game_logic.py        # Turn processing logic
├── auth.py              # API key authentication
├── requirements.txt     # Python dependencies
├── Procfile             # Railway deployment config
└── README.md
```

### requirements.txt

```
fastapi==0.109.0
uvicorn[standard]==0.27.0
redis==5.0.1
pydantic==2.5.3
python-dotenv==1.0.0
```

### Procfile

```
web: uvicorn main:app --host 0.0.0.0 --port $PORT
```

### Railway CLI Deployment

```bash
# Login to Railway
railway login

# Link to project
railway link

# Deploy
railway up
```

## Scaling Considerations

### MVP Phase (Current)
- Single FastAPI instance
- Background tasks for turn processing
- Redis for all state
- Works for 10-100 concurrent games

### Future Scaling
- Separate worker service for turn processing (Railway background worker)
- Redis caching layer + PostgreSQL for persistent storage
- WebSocket connections instead of polling (reduce API calls)
- Horizontal scaling with multiple API instances

## Error Handling

### Common Error Responses

**401 Unauthorized:**
```json
{"detail": "Invalid API key"}
```

**404 Not Found:**
```json
{"detail": "Game not found"}
```

**409 Conflict:**
```json
{"detail": "Move already submitted for this turn"}
```

**500 Internal Server Error:**
```json
{"detail": "Turn processing failed", "error": "..."}
```

## Monitoring & Logging

### Key Metrics to Track
- API request latency
- Turn processing duration
- Active games count
- Redis memory usage
- Failed turn processing attempts

### Railway Built-in Monitoring
- CPU/Memory usage
- Request volume
- Error rates
- Logs accessible via Railway dashboard

## Security Notes

### Current Approach (MVP)
- HTTPS enforced by Railway
- Simple API key in headers
- Redis password authentication
- No rate limiting (rely on Railway defaults)

### Future Enhancements
- JWT tokens with expiration
- Rate limiting per player
- Move validation (prevent cheating)
- Encrypted move data
- Session replay detection

## Development Workflow

1. **Local Development:**
   - Use local Redis instance (`redis-server`)
   - FastAPI dev server: `uvicorn main:app --reload`
   - Test endpoints with Postman/curl

2. **Testing:**
   - Unit tests for game logic
   - Integration tests for API endpoints
   - Load testing for turn processing

3. **Deployment:**
   - Push to GitHub
   - Railway auto-deploys from main branch
   - Or manual: `railway up`

4. **Claude Code Integration:**
   - Claude Code can run Railway CLI commands
   - Automated deployment after code changes
   - Environment variable management via Railway CLI

## Next Steps

1. Implement basic FastAPI structure with health check endpoint
2. Set up Redis connection and test CRUD operations
3. Build game creation and join endpoints
4. Implement move submission with move counter
5. Create turn processing background task
6. Add results polling endpoint
7. Deploy to Railway and test with Godot client
8. Iterate on game logic implementation
