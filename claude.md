# Turn-Based Multiplayer Game Project

## Project Overview

This project implements a **turn-based multiplayer game system** with simultaneous move submission. The architecture consists of:

1. **Python REST API** (FastAPI) hosted on Railway
2. **Godot game clients** that communicate with the API
3. **Redis database** for real-time game state management

## Game Mechanics

**Turn Flow:**
- All players submit their moves simultaneously for the current turn
- When the last player submits, the server automatically processes the turn
- Clients poll the API for results (3-10 second intervals)
- Results are returned as delta updates (only changed game state)
- Next turn begins

**Game Type:**
- Hex-based map strategy game
- Multiple players per game
- Session-based multiplayer (games can be created and joined)
- players input moves for their "robots"
- each turn

## Technology Stack

### Backend (Railway-hosted)
- **Framework**: FastAPI (Python)
- **Database**: Redis (game state, sessions, real-time data)
- **Hosting**: Railway (automatic HTTPS, GitHub deployment)
- **Authentication**: Simple API key in request headers

### Frontend (Godot clients)
- **Engine**: Godot 4.x
- **Language**: GDScript
- **Networking**: HTTPRequest with REST API calls
- **Map System**: Hexagonal grid rendering

## Architecture Documents

**For detailed implementation guidance, Claude Code should read:**

1. **`api_architecture.md`** - Complete backend API design
   - Redis data model and key structure
   - All API endpoints with request/response schemas
   - Turn processing logic and auto-trigger mechanism
   - Deployment instructions for Railway
   - Authentication approach
   - Scaling considerations

2. **`godot_architecture.md`** - Game client implementation
   - Godot project structure and autoload singletons
   - API client implementation (HTTPRequest wrapper)
   - Game state management patterns
   - Hex map rendering and coordinate conversion
   - Turn submission and polling flow
   - UI flow and scene organization
   - Performance optimization strategies

## Current Project Status

**Phase**: Initial architecture design complete

**Next Implementation Steps:**

### Backend (Python/FastAPI)
1. Set up FastAPI project structure
2. Implement Redis connection and data access layer
3. Create API endpoints (game creation, join, submit, results)
4. Build turn processing background task
5. Add API key authentication middleware
6. Deploy to Railway
7. Test with curl/Postman

### Frontend (Godot)
1. Create Godot project with singleton structure
2. Implement APIClient autoload script
3. Build GameState management singleton
4. Create basic UI (main menu, lobby, game view)
5. Implement hex map rendering
6. Add turn submission and polling logic
7. Test integration with deployed API

## Deployment Strategy

### Railway Deployment
- GitHub repository connected to Railway project
- Automatic deployment on push to main branch
- Environment variables managed in Railway dashboard
- Redis instance provisioned through Railway

### Claude Code Integration
Claude Code can orchestrate:
- Code generation for API endpoints and Godot scripts
- Railway CLI commands for deployment (`railway up`)
- Testing and iteration
- Environment variable configuration

## Key Design Decisions

### Why FastAPI?
- Clean API structure with automatic documentation
- Native async support for background tasks
- Excellent for MVP development speed

### Why Redis?
- Perfect for real-time game state (fast reads for polling)
- Simple key-value model fits turn-based data
- Built-in TTL for automatic cleanup
- Atomic operations prevent race conditions

### Why Railway?
- Simple deployment from GitHub
- One-click Redis provisioning
- Automatic HTTPS
- Great for MVPs (free tier available)

### Why Polling Instead of WebSockets?
- Simpler implementation for MVP
- Turn-based games have low update frequency
- 3-10 second polling is acceptable latency
- Can upgrade to WebSockets later if needed

## Development Workflow

1. **Local Development**
   - Backend: Run FastAPI with local Redis (`uvicorn main:app --reload`)
   - Frontend: Run Godot editor, connect to local API
   - Test endpoints individually

2. **Deployment**
   - Push backend code to GitHub
   - Railway auto-deploys
   - Test with Godot client against production API

3. **Iteration**
   - Use Claude Code to generate/modify code
   - Test locally
   - Deploy via `railway up` or git push
   - Validate with Godot client

## Security Model

**Current (MVP):**
- HTTPS enforced by Railway
- Simple API key authentication (UUID-based)
- Client stores API key locally
- All requests include `X-API-Key` header

**Future Enhancements:**
- JWT tokens with expiration
- Move validation (prevent cheating)
- Rate limiting per player
- Session replay detection

## Performance Considerations

### Backend
- Background task processing keeps API responsive
- Redis provides sub-millisecond read times for polling
- Single instance handles 10-100 concurrent games initially

### Frontend (Godot)
- Large map loaded once at game start
- Subsequent updates are deltas only
- Hex tiles rendered on-demand (viewport culling)
- Configurable polling interval balances responsiveness vs API load

## Testing Strategy

1. **Unit Tests**: Game logic functions (turn processing)
2. **Integration Tests**: API endpoints with Redis
3. **Client Testing**: Mock API for Godot development
4. **Load Testing**: Simulate multiple games/concurrent players
5. **Multiplayer Testing**: Run multiple Godot instances

## Documentation Structure

```
project/
├── claude.md                  # This file - high-level overview
├── api_architecture.md        # Backend implementation details
├── godot_architecture.md      # Game client implementation details
├── backend/                   # FastAPI project
│   ├── main.py
│   ├── models.py
│   ├── redis_client.py
│   ├── game_logic.py
│   └── requirements.txt
└── game_client/               # Godot project
    ├── project.godot
    ├── scenes/
    └── scripts/
```

## Getting Started with Claude Code

**For Backend Development:**
```bash
# Read the architecture
Read api_architecture.md for complete implementation details

# Create FastAPI project structure
# Implement Redis connection
# Build API endpoints following api_architecture.md specifications
# Test locally with uvicorn
# Deploy to Railway with `railway up`
```

**For Frontend Development:**
```bash
# Read the architecture
Read godot_architecture.md for implementation patterns

# Create Godot project
# Set up autoload singletons (APIClient, GameState)
# Implement HTTPRequest wrapper
# Build UI scenes
# Test with deployed API
```

## Important Notes for Claude Code

- **Read architecture documents first** before implementing features
- **All code checked into Github**
- **Follow the data models** specified in api_architecture.md (Redis keys)
- **Use the API endpoint schemas** exactly as documented
- **Implement error handling** as specified in both documents
- **Railway CLI** can be used for deployment automation
- **Testing strategy** is outlined in both architecture documents

## Questions to Resolve During Implementation

- [ ] Exact game logic for turn processing (hex map rules, combat, etc.)
- [ ] Win condition detection
- [ ] Player matchmaking or manual game joining?
- [ ] Spectator mode support?
- [ ] Replay/game history?
- [ ] Maximum map size that Godot can handle efficiently

## Resources

- Railway Documentation: https://docs.railway.app
- FastAPI Documentation: https://fastapi.tiangolo.com
- Redis Documentation: https://redis.io/docs
- Godot Documentation: https://docs.godotengine.org
- Hex Grid Guide: https://www.redblobgames.com/grids/hexagons/

## Contact / Feedback

Project created by: Karl
Purpose: Minimum viable product for turn-based multiplayer hex map game
