from fastapi import FastAPI, BackgroundTasks, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
import uuid
import json
from datetime import datetime
import asyncio

from models import (
    CreateGameRequest, CreateGameResponse,
    JoinGameRequest, JoinGameResponse,
    GameStatusResponse,
    SubmitMoveRequest, SubmitMoveResponse,
    TurnResultsResponse
)
from redis_client import redis_client
from auth import get_current_player, generate_api_key, generate_player_id, store_player_key
from game_logic import calculate_turn_results, check_win_condition, generate_default_map
from config import Config

# Initialize FastAPI application
app = FastAPI(
    title="Turn-Based Game API",
    version="1.0.0",
    description="REST API for turn-based multiplayer hex map strategy game"
)

# Configure CORS for Godot clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: Restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ==================== Health Check ====================

@app.get("/health")
async def health_check():
    """Health check endpoint - no authentication required"""
    redis_healthy = redis_client.health_check()

    return {
        "status": "healthy" if redis_healthy else "unhealthy",
        "redis": redis_healthy,
        "environment": Config.ENVIRONMENT
    }


# ==================== Game Creation ====================

@app.post("/game/create", response_model=CreateGameResponse)
async def create_game(request: CreateGameRequest):
    """
    Create a new game instance

    - Generates unique game_id and creator player_id
    - Initializes game metadata in Redis
    - Returns API key for authentication
    """
    # Generate IDs
    game_id = f"game_{uuid.uuid4().hex[:12]}"
    creator_id = generate_player_id()
    api_key = generate_api_key()

    # Store API key for creator
    store_player_key(creator_id, api_key)

    # Generate game map
    map_data = generate_default_map(
        width=request.map_config.width,
        height=request.map_config.height,
        terrain_data=request.map_config.terrain_data
    )

    # Initialize game metadata
    game_meta = {
        "state": "waiting_for_players",
        "current_turn": 0,
        "player_count": 1,
        "max_players": request.max_players,
        "created_at": datetime.utcnow().isoformat()
    }

    # Store in Redis
    redis_client.set_game_meta(game_id, game_meta, ttl=Config.TTL_ACTIVE_GAME)
    redis_client.store_game_map(game_id, map_data)
    redis_client.add_player_to_game(game_id, creator_id)
    redis_client.set_player_current_game(creator_id, game_id)

    return CreateGameResponse(
        game_id=game_id,
        creator_player_id=creator_id,
        api_key=api_key,
        state="waiting_for_players",
        max_players=request.max_players
    )


# ==================== Join Game ====================

@app.post("/game/{game_id}/join", response_model=JoinGameResponse)
async def join_game(game_id: str, request: JoinGameRequest):
    """
    Join an existing game

    - Verifies game exists and is accepting players
    - Generates player_id and API key
    - Adds player to game
    - Returns full map data
    """
    # Check if game exists
    if not redis_client.game_exists(game_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Game not found"
        )

    # Get game metadata
    game_meta = redis_client.get_game_meta(game_id)

    # Check if game is accepting players
    if game_meta["state"] != "waiting_for_players":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Game is not accepting new players"
        )

    # Check if game is full
    if game_meta["player_count"] >= game_meta["max_players"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Game is full"
        )

    # Generate player credentials
    player_id = generate_player_id()
    api_key = generate_api_key()
    store_player_key(player_id, api_key)

    # Add player to game
    redis_client.add_player_to_game(game_id, player_id)
    redis_client.set_player_current_game(player_id, game_id)

    # Get updated player count
    updated_meta = redis_client.get_game_meta(game_id)

    # If game is now full, start the game
    if updated_meta["player_count"] >= updated_meta["max_players"]:
        redis_client.update_game_state(game_id, "in_progress")
        updated_meta["state"] = "in_progress"

    # Get map data
    map_data = redis_client.get_game_map(game_id)

    return JoinGameResponse(
        game_id=game_id,
        player_id=player_id,
        api_key=api_key,
        map=map_data,
        current_players=updated_meta["player_count"],
        max_players=updated_meta["max_players"],
        state=updated_meta["state"]
    )


# ==================== Game Status ====================

@app.get("/game/{game_id}/status", response_model=GameStatusResponse)
async def get_game_status(
    game_id: str,
    player_id: str = Depends(get_current_player)
):
    """
    Get current game status

    - Requires authentication
    - Returns game state and move submission status
    """
    # Check if game exists
    if not redis_client.game_exists(game_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Game not found"
        )

    # Verify player is in this game
    if not redis_client.is_player_in_game(game_id, player_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Player not in this game"
        )

    # Get game metadata
    game_meta = redis_client.get_game_meta(game_id)

    # Count moves submitted for current turn
    current_turn = game_meta["current_turn"]
    moves_submitted = redis_client.count_turn_moves(game_id, current_turn)
    moves_required = game_meta["player_count"]

    return GameStatusResponse(
        game_id=game_id,
        state=game_meta["state"],
        current_turn=current_turn,
        moves_submitted=moves_submitted,
        moves_required=moves_required,
        all_moves_in=(moves_submitted >= moves_required)
    )


# ==================== Submit Move ====================

@app.post("/game/{game_id}/submit", response_model=SubmitMoveResponse)
async def submit_move(
    game_id: str,
    request: SubmitMoveRequest,
    background_tasks: BackgroundTasks,
    player_id: str = Depends(get_current_player)
):
    """
    Submit moves for current turn

    - Requires authentication
    - Validates turn number
    - Prevents duplicate submissions
    - Auto-triggers turn processing when all moves received
    """
    # Check if game exists
    if not redis_client.game_exists(game_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Game not found"
        )

    # Verify player is in this game
    if not redis_client.is_player_in_game(game_id, player_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Player not in this game"
        )

    # Get game metadata
    game_meta = redis_client.get_game_meta(game_id)

    # Verify game is in progress
    if game_meta["state"] not in ["in_progress", "processing_turn"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Game is not in progress (current state: {game_meta['state']})"
        )

    # Verify turn number matches
    if request.turn != game_meta["current_turn"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Turn mismatch. Expected {game_meta['current_turn']}, got {request.turn}"
        )

    # Check if player already submitted for this turn
    if redis_client.has_player_submitted_move(game_id, request.turn, player_id):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Move already submitted for this turn"
        )

    # Store the move
    move_data = {
        "turn": request.turn,
        "moves": [move.model_dump() for move in request.moves],
        "submitted_at": datetime.utcnow().isoformat()
    }
    redis_client.store_move(game_id, request.turn, player_id, move_data)

    # Count total moves submitted
    moves_submitted = redis_client.count_turn_moves(game_id, request.turn)
    moves_required = game_meta["player_count"]

    processing = False

    # If all moves are in, trigger turn processing
    if moves_submitted >= moves_required:
        # Update state to processing
        redis_client.update_game_state(game_id, "processing_turn")
        processing = True

        # Trigger background task
        background_tasks.add_task(process_turn, game_id, request.turn)

    return SubmitMoveResponse(
        success=True,
        turn=request.turn,
        moves_submitted=moves_submitted,
        moves_required=moves_required,
        processing=processing
    )


# ==================== Get Turn Results ====================

@app.get("/game/{game_id}/results", response_model=TurnResultsResponse)
async def get_turn_results(
    game_id: str,
    turn: int,
    player_id: str = Depends(get_current_player)
):
    """
    Poll for turn processing results

    - Requires authentication
    - Returns results if available
    - Returns ready=False if still processing
    """
    # Check if game exists
    if not redis_client.game_exists(game_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Game not found"
        )

    # Verify player is in this game
    if not redis_client.is_player_in_game(game_id, player_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Player not in this game"
        )

    # Check if results exist for this turn
    results = redis_client.get_turn_results(game_id, turn)

    if results:
        # Results are ready
        game_meta = redis_client.get_game_meta(game_id)

        return TurnResultsResponse(
            ready=True,
            turn=turn,
            state=game_meta["state"],
            updates=results.get("updates", []),
            events=results.get("events", []),
            next_turn=game_meta["current_turn"]
        )
    else:
        # Results not ready yet
        game_meta = redis_client.get_game_meta(game_id)

        return TurnResultsResponse(
            ready=False,
            turn=turn,
            state=game_meta["state"]
        )


# ==================== Background Task: Process Turn ====================

async def process_turn(game_id: str, turn: int):
    """
    Background task to process a turn

    - Fetches all moves
    - Calls game logic to calculate results
    - Stores results in Redis
    - Increments turn counter
    - Updates game state
    """
    try:
        # Small delay to ensure all moves are stored
        await asyncio.sleep(0.5)

        # Fetch all moves for this turn
        moves = redis_client.get_turn_moves(game_id, turn)

        # Calculate turn results using game logic
        results = calculate_turn_results(moves, game_id)

        # Store results
        redis_client.store_turn_results(game_id, turn, results)

        # Check win condition
        game_complete = check_win_condition(game_id)

        if game_complete:
            # Game is complete
            redis_client.update_game_state(game_id, "complete")
        else:
            # Increment turn and continue game
            redis_client.increment_turn(game_id)
            redis_client.update_game_state(game_id, "in_progress")

    except Exception as e:
        # Log error and update game state
        print(f"Error processing turn {turn} for game {game_id}: {str(e)}")

        # Set game to error state or retry
        redis_client.update_game_state(game_id, "in_progress")


# ==================== Root Endpoint ====================

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": "Turn-Based Game API",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health"
    }
