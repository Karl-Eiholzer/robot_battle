from fastapi import FastAPI, BackgroundTasks, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
import uuid
import random
from datetime import datetime
import asyncio

from models import (
    CreateGameRequest, CreateGameResponse,
    JoinGameRequest, JoinGameResponse,
    InviteCodeJoinRequest,
    GameStatusResponse,
    SubmitMoveRequest, SubmitMoveResponse,
    TurnResultsResponse,
    AssignRolesRequest, AssignRolesResponse,
    SpawnRobotsResponse,
    InitialStateResponse,
    GameVariables
)
from redis_client import redis_client
from auth import get_current_player, generate_api_key, generate_player_id, store_player_key
from game_logic import (
    calculate_turn_results, check_win_condition, generate_default_map,
    spawn_robots_for_game, validate_role_assignment, validate_player_actions,
    filter_robots_by_sight
)
from config import Config

# Initialize FastAPI application
app = FastAPI(
    title="Robot Battle Game API",
    version="2.0.0",
    description="REST API for turn-based multiplayer robot hex map strategy game"
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

    # Use game variables from request or defaults
    game_vars = request.game_variables or GameVariables()
    game_vars_dict = game_vars.model_dump()

    # Generate game map based on game variables
    map_data = generate_default_map(
        width=request.map_config.width,
        height=request.map_config.height,
        terrain_data=request.map_config.terrain_data,
        game_variables=game_vars_dict
    )

    # Initialize game metadata
    game_meta = {
        "state": "waiting_for_players",
        "current_turn": 0,
        "player_count": 0,
        "max_players": request.max_players,
        "created_at": datetime.utcnow().isoformat(),
        "initiative_team": random.randint(0, 1),
        "team_size": game_vars.team_size
    }

    # Store in Redis
    redis_client.set_game_meta(game_id, game_meta, ttl=Config.TTL_ACTIVE_GAME)
    redis_client.store_game_map(game_id, map_data)
    redis_client.store_game_variables(game_id, game_vars_dict)

    # Creator joins team 0 by default
    redis_client.add_player_to_game(game_id, creator_id)
    redis_client.store_player_info(game_id, creator_id, "Creator", team=0)
    redis_client.set_player_current_game(creator_id, game_id)

    # Generate invite codes
    from invite_codes import generate_invite_code
    team_0_code = generate_invite_code(redis_client)
    team_1_code = generate_invite_code(redis_client)

    # Store invite code mappings
    redis_client.store_invite_code(team_0_code, game_id, team=0, ttl=Config.TTL_ACTIVE_GAME)
    redis_client.store_invite_code(team_1_code, game_id, team=1, ttl=Config.TTL_ACTIVE_GAME)

    return CreateGameResponse(
        game_id=game_id,
        creator_player_id=creator_id,
        api_key=api_key,
        team_0_invite_code=team_0_code,
        team_1_invite_code=team_1_code,
        state="waiting_for_players",
        max_players=request.max_players,
        team=0  # Creator is always team 0
    )


# ==================== Join Game ====================

@app.post("/game/invite/{invite_code}/join", response_model=JoinGameResponse)
async def join_game_by_invite_code(invite_code: str, request: InviteCodeJoinRequest):
    """
    Join a game using an invite code
    - Looks up game_id and team from invite code
    - Verifies game exists and is accepting players
    - Verifies team has space available
    - Assigns player to the team encoded in the invite code
    """
    # Lookup invite code
    invite_info = redis_client.get_invite_code_info(invite_code)
    if not invite_info:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or expired invite code"
        )

    game_id = invite_info["game_id"]
    assigned_team = invite_info["team"]

    # Verify game exists
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

    # Check if team has space
    team_size = game_meta["max_players"] // 2
    team_count = redis_client.get_team_player_count(game_id, assigned_team)
    if team_count >= team_size:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Team {assigned_team} is full"
        )

    # Generate player credentials
    player_id = generate_player_id()
    api_key = generate_api_key()
    store_player_key(player_id, api_key)

    # Add player to game with assigned team
    redis_client.add_player_to_game(game_id, player_id)
    redis_client.store_player_info(game_id, player_id, request.player_name, team=assigned_team)
    redis_client.set_player_current_game(player_id, game_id)

    # Get updated player count
    updated_meta = redis_client.get_game_meta(game_id)

    # Auto-transition to in_progress when game is full
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
        state=updated_meta["state"],
        team=assigned_team  # Team determined by invite code
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


# ==================== Assign Roles ====================

@app.post("/game/{game_id}/team/{team}/assign_roles", response_model=AssignRolesResponse)
async def assign_roles(
    game_id: str,
    team: int,
    request: AssignRolesRequest,
    player_id: str = Depends(get_current_player)
):
    """
    Assign roles to players on a team

    - Validates role assignments against team size
    - Stores role assignments in Redis
    """
    if not redis_client.game_exists(game_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Game not found"
        )

    if not redis_client.is_player_in_game(game_id, player_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Player not in this game"
        )

    if team not in [0, 1]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Team must be 0 or 1"
        )

    game_meta = redis_client.get_game_meta(game_id)
    team_size = game_meta.get("team_size", 2)

    # Get existing roles for this team
    existing_roles = redis_client.get_team_roles(game_id, team)

    # Validate role assignments
    errors = validate_role_assignment(team_size, request.role_assignments, existing_roles)
    if errors:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid role assignments: {'; '.join(errors)}"
        )

    # Store role assignments
    for pid, role_name in request.role_assignments.items():
        redis_client.assign_role(game_id, team, pid, role_name)

    return AssignRolesResponse(
        success=True,
        team=team,
        roles_assigned=request.role_assignments
    )


# ==================== Spawn Robots ====================

@app.post("/game/{game_id}/spawn_robots", response_model=SpawnRobotsResponse)
async def spawn_robots(
    game_id: str,
    player_id: str = Depends(get_current_player)
):
    """
    Spawn robots for all players based on role assignments

    - Requires both teams to have roles assigned
    - Creates Robot instances at spawn positions
    - Transitions game to in_progress state
    """
    if not redis_client.game_exists(game_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Game not found"
        )

    if not redis_client.is_player_in_game(game_id, player_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Player not in this game"
        )

    # Check roles are assigned for both teams
    team0_roles = redis_client.get_team_roles(game_id, 0)
    team1_roles = redis_client.get_team_roles(game_id, 1)

    if not team0_roles:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Team 0 has not assigned roles yet"
        )
    if not team1_roles:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Team 1 has not assigned roles yet"
        )

    # Idempotent: if robots are already spawned return them without re-spawning.
    # This handles the race where multiple players click Spawn simultaneously.
    game_meta = redis_client.get_game_meta(game_id)
    if game_meta and game_meta.get("state") == "in_progress":
        existing_robots = redis_client.get_robots(game_id)
        return SpawnRobotsResponse(
            success=True,
            robots_created=len(existing_robots),
            robots=existing_robots
        )

    game_vars = redis_client.get_game_variables(game_id)
    if not game_vars:
        game_vars = GameVariables().model_dump()

    map_data = redis_client.get_game_map(game_id)
    if not map_data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Map data not found"
        )

    # Mark in_progress BEFORE spawning so concurrent idempotency check catches
    # simultaneous requests before they each try to spawn robots.
    redis_client.update_game_state(game_id, "in_progress")

    robots = spawn_robots_for_game(game_id, game_vars, map_data)

    if not robots:
        redis_client.update_game_state(game_id, "lobby")  # rollback
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to spawn robots - check role assignments"
        )

    # Store robots
    redis_client.store_robots(game_id, robots)

    # Initialize hex objects (empty at start)
    redis_client.store_hex_objects(game_id, [])

    return SpawnRobotsResponse(
        success=True,
        robots_created=len(robots),
        robots=robots
    )


# ==================== Initial State ====================

@app.get("/game/{game_id}/initial_state", response_model=InitialStateResponse)
async def get_initial_state(
    game_id: str,
    player_id: str = Depends(get_current_player)
):
    """
    Get initial game state customized for the requesting player

    - Full robot data for player's own robots
    - Limited data for enemy robots (no energy)
    - Map data, hex objects, game variables
    """
    if not redis_client.game_exists(game_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Game not found"
        )

    if not redis_client.is_player_in_game(game_id, player_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Player not in this game"
        )

    game_meta = redis_client.get_game_meta(game_id)
    all_robots = redis_client.get_robots(game_id)
    map_data = redis_client.get_game_map(game_id)
    game_vars = redis_client.get_game_variables(game_id) or GameVariables().model_dump()
    hex_objects = redis_client.get_hex_objects(game_id)

    # Filter robots by sight range
    player_robots, visible_others = filter_robots_by_sight(player_id, all_robots)

    return InitialStateResponse(
        game_id=game_id,
        current_turn=game_meta["current_turn"],
        team_with_initiative=game_meta.get("initiative_team", 0),
        map=map_data or {},
        game_variables=game_vars,
        player_robots=player_robots,
        other_robots=visible_others,
        hex_objects=hex_objects
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
    - Validates turn number and action format
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

    validation_errors = []

    # Validate new-format actions if provided
    if request.actions:
        all_robots = redis_client.get_robots(game_id)
        if all_robots:
            actions_dicts = [a.model_dump() for a in request.actions]
            validation_errors = validate_player_actions(
                player_id, actions_dicts, all_robots, game_id
            )

    # Build move data to store
    if request.actions:
        move_data = {
            "turn": request.turn,
            "actions": [a.model_dump() for a in request.actions],
            "submitted_at": datetime.utcnow().isoformat()
        }
    else:
        # Old format
        move_data = {
            "turn": request.turn,
            "moves": [m.model_dump() for m in (request.moves or [])],
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
        processing=processing,
        validation_errors=validation_errors
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
    - Returns results if available with replay data
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

        # Get replay data
        replay = redis_client.get_turn_replay(game_id, turn)

        # Get updated robots filtered by sight
        all_robots = redis_client.get_robots(game_id)
        hex_objects = redis_client.get_hex_objects(game_id)

        player_robots, visible_others = filter_robots_by_sight(player_id, all_robots)
        updated_robots = player_robots + visible_others

        winner = results.get("winner")

        return TurnResultsResponse(
            ready=True,
            turn=turn,
            state=game_meta["state"],
            updates=results.get("updates", []),
            events=results.get("events", []),
            next_turn=game_meta["current_turn"],
            replay=replay,
            updated_robots=updated_robots,
            updated_hex_objects=hex_objects,
            winner=winner
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
        winner = check_win_condition(game_id)

        if winner is not None:
            # Game is complete
            redis_client.update_game_state(game_id, "complete")
        else:
            # Increment turn, flip initiative, and continue game
            redis_client.increment_turn(game_id)
            redis_client.flip_initiative(game_id)
            redis_client.update_game_state(game_id, "in_progress")

            # Reset extra_moves_this_turn for all robots at start of new turn
            robots = redis_client.get_robots(game_id)
            if robots:
                for robot in robots:
                    robot["extra_moves_this_turn"] = 0
                    robot["state"] = "active"  # Stunned robots recover each turn
                redis_client.store_robots(game_id, robots)

    except Exception as e:
        # Log error and update game state
        print(f"Error processing turn {turn} for game {game_id}: {str(e)}")
        import traceback
        traceback.print_exc()

        # Set game back to in_progress so players can retry
        redis_client.update_game_state(game_id, "in_progress")


# ==================== Root Endpoint ====================

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": "Robot Battle Game API",
        "version": "2.0.0",
        "docs": "/docs",
        "health": "/health"
    }
