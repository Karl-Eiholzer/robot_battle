# Robot Battle

A turn-based multiplayer hex map strategy game with simultaneous move submission.

## Architecture

- **Backend**: Python FastAPI REST API with Redis database
- **Frontend**: Godot 4.x game client
- **Hosting**: Railway

## Documentation

- `claude.md` - Project overview and development guide
- `api_architecture.md` - Backend implementation details
- `godot_architecture.md` - Game client implementation guide

## Technology Stack

- FastAPI for REST API endpoints
- Redis for real-time game state management
- Godot 4.x with GDScript for game client
- Railway for deployment and hosting

## Game Mechanics

Players submit moves simultaneously each turn. When all players have submitted, the server processes the turn and returns delta updates to clients. Games are session-based with support for multiple concurrent games.
