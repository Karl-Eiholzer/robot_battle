# Backend API - Turn-Based Multiplayer Game

FastAPI backend with Redis for turn-based hex map strategy game with simultaneous move submission.

## Architecture

- **Framework**: FastAPI (Python)
- **Database**: Redis (game state, sessions)
- **Hosting**: Railway
- **Authentication**: Simple API key (X-API-Key header)

## Project Structure

```
backend/
├── main.py              # FastAPI application with all endpoints
├── models.py            # Pydantic request/response models
├── redis_client.py      # Redis connection and data access layer
├── auth.py              # API key authentication
├── game_logic.py        # Turn processing logic (MVP stub)
├── config.py            # Configuration management
├── requirements.txt     # Python dependencies
├── Procfile             # Railway deployment config
├── .env.example         # Environment variable template
└── README.md            # This file
```

## Local Development Setup

### Prerequisites

- Python 3.10+
- Redis server

### Install Redis

**macOS (Homebrew):**
```bash
brew install redis
brew services start redis
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get install redis-server
sudo systemctl start redis-server
```

**Windows:**
Download from https://redis.io/download

### Setup Steps

1. **Clone the repository**
   ```bash
   cd /path/to/robot_battle/backend
   ```

2. **Create virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Create .env file**
   ```bash
   cp .env.example .env
   ```

5. **Start Redis** (if not already running)
   ```bash
   redis-server
   ```

6. **Run the application**
   ```bash
   uvicorn main:app --reload
   ```

7. **Access the API**
   - API: http://localhost:8000
   - Interactive docs: http://localhost:8000/docs
   - Health check: http://localhost:8000/health

## API Endpoints

### Public Endpoints (No Authentication)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Root endpoint with API info |
| `/health` | GET | Health check (Redis status) |
| `/docs` | GET | Interactive API documentation |

### Game Management

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/game/create` | POST | No | Create new game instance |
| `/game/{game_id}/join` | POST | No | Join existing game |
| `/game/{game_id}/status` | GET | Yes | Get game status |
| `/game/{game_id}/submit` | POST | Yes | Submit moves for turn |
| `/game/{game_id}/results` | GET | Yes | Poll for turn results |

### Authentication

All authenticated endpoints require `X-API-Key` header:

```bash
curl -H "X-API-Key: your-api-key-here" http://localhost:8000/game/{game_id}/status
```

## Example Usage

### 1. Create a Game

```bash
curl -X POST http://localhost:8000/game/create \
  -H "Content-Type: application/json" \
  -d '{
    "max_players": 4,
    "map_config": {
      "width": 10,
      "height": 10
    }
  }'
```

Response:
```json
{
  "game_id": "game_abc123",
  "creator_player_id": "player_xyz789",
  "api_key": "550e8400-e29b-41d4-a716-446655440000",
  "state": "waiting_for_players",
  "max_players": 4
}
```

### 2. Join a Game

```bash
curl -X POST http://localhost:8000/game/game_abc123/join \
  -H "Content-Type: application/json" \
  -d '{
    "player_name": "Player2"
  }'
```

### 3. Submit Moves

```bash
curl -X POST http://localhost:8000/game/game_abc123/submit \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{
    "turn": 0,
    "moves": [
      {
        "unit_id": "unit_1",
        "action": "move",
        "target": [5, 5]
      }
    ]
  }'
```

### 4. Poll for Results

```bash
curl -X GET "http://localhost:8000/game/game_abc123/results?turn=0" \
  -H "X-API-Key: your-api-key"
```

## Railway Deployment

### Prerequisites

- Railway CLI installed: `npm install -g @railway/cli`
- Railway account: https://railway.app

### Deployment Steps

1. **Login to Railway**
   ```bash
   railway login
   ```

2. **Initialize Railway project** (from backend directory)
   ```bash
   railway init
   ```

3. **Provision Redis**
   - Go to Railway dashboard
   - Select your project
   - Click "New Service" → "Database" → "Redis"
   - Railway automatically creates `REDIS_URL` environment variable

4. **Set environment variables**
   ```bash
   railway variables set API_SECRET=$(python -c "import secrets; print(secrets.token_urlsafe(32))")
   railway variables set ENVIRONMENT=production
   ```

5. **Deploy**
   ```bash
   railway up
   ```

6. **Get deployment URL**
   ```bash
   railway open
   ```

7. **Verify deployment**
   ```bash
   curl https://your-app.railway.app/health
   ```

### Environment Variables (Railway)

**Auto-provided by Railway:**
- `PORT` - Application port
- `REDIS_URL` - Redis connection string

**User-configured (via Railway dashboard or CLI):**
- `API_SECRET` - Secret for API key generation
- `ENVIRONMENT` - "production"

## Redis Data Model

### Game Metadata
```
game:{game_id}:meta → Hash
  - state: waiting_for_players | in_progress | processing_turn | complete
  - current_turn: int
  - player_count: int
  - max_players: int
  - created_at: ISO timestamp
```

### Players
```
game:{game_id}:players → Set of player_ids
```

### Turn Moves
```
game:{game_id}:turn:{n}:moves → Hash
  - {player_id}: JSON move data
```

### Turn Results
```
game:{game_id}:turn:{n}:results → JSON string
  - updates: array of delta updates
  - events: array of game events
```

### Game Map
```
game:{game_id}:map → JSON string (hex map data)
```

### Player Sessions
```
player:{player_id}:api_key → API key
api_key:{api_key} → player_id (reverse lookup)
player:{player_id}:current_game → game_id
```

## Game Flow

1. **Create Game**
   - Creator calls `/game/create`
   - Receives `game_id` and `api_key`
   - Game state: `waiting_for_players`

2. **Players Join**
   - Other players call `/game/{game_id}/join`
   - Each receives unique `api_key`
   - When `player_count == max_players`, state → `in_progress`

3. **Turn Submission**
   - Players submit moves via `/game/{game_id}/submit`
   - When all players submit, state → `processing_turn`
   - Background task processes turn automatically

4. **Turn Processing**
   - Fetch all moves from Redis
   - Calculate results (game_logic.py)
   - Store results in Redis
   - Increment turn counter
   - State → `in_progress`

5. **Results Polling**
   - Clients poll `/game/{game_id}/results?turn={n}`
   - Returns delta updates (not full state)
   - Recommended polling interval: 3-10 seconds

## Development Tips

### Testing Redis Connection

```bash
redis-cli ping
# Should return: PONG
```

### View Redis Keys

```bash
redis-cli
> KEYS game:*
> HGETALL game:{game_id}:meta
```

### Clear Redis Data

```bash
redis-cli FLUSHDB
```

### Run Tests

```bash
# From project root
python test_api.py http://localhost:8000
```

## TTL (Time To Live) Settings

- **Active games**: 24 hours from last activity
- **Completed games**: 1 hour after completion
- **Player sessions**: 48 hours

TTLs are automatically refreshed on game activity.

## Error Handling

| Status Code | Description |
|-------------|-------------|
| 200 | Success |
| 401 | Unauthorized (invalid API key) |
| 403 | Forbidden (player not in game) |
| 404 | Not Found (game doesn't exist) |
| 409 | Conflict (duplicate move, wrong turn, game full) |
| 422 | Validation Error (invalid request data) |
| 500 | Internal Server Error |

## Game Logic (MVP Stub)

Current implementation in `game_logic.py` is a **stub for MVP**:

- Accepts all moves without validation
- Returns simple delta updates (units moved to positions)
- No combat resolution
- No win condition checking
- Games never end

**Future Implementation:**
- Movement validation (pathfinding, obstacles)
- Combat resolution (damage, health)
- Resource management
- Win condition detection
- Unit abilities and special actions

## Monitoring

### Railway Dashboard

- CPU/Memory usage
- Request logs
- Error tracking
- Redis metrics

### Health Check Endpoint

```bash
curl https://your-app.railway.app/health
```

Response:
```json
{
  "status": "healthy",
  "redis": true,
  "environment": "production"
}
```

## Troubleshooting

**Redis connection fails:**
- Check Redis is running: `redis-cli ping`
- Verify `REDIS_URL` in .env or Railway

**API returns 401 Unauthorized:**
- Check `X-API-Key` header is included
- Verify API key is valid (48h TTL)

**Turn processing stuck:**
- Check background task logs
- Verify all players submitted moves
- Check Redis for turn data: `redis-cli HGETALL game:{id}:turn:{n}:moves`

**Game state incorrect:**
- Check game metadata: `redis-cli HGETALL game:{id}:meta`
- Verify player count matches submissions

## Contributing

When implementing real game logic:

1. Update `game_logic.py` with actual rules
2. Implement movement validation
3. Add combat resolution
4. Implement win conditions
5. Add unit tests for game logic
6. Update API documentation

## License

See project root LICENSE file.
