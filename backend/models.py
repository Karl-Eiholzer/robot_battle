from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional


# ==================== Robot Type Definitions ====================

class RobotTypeStats(BaseModel):
    """Stats for a robot type"""
    moves_per_turn: int
    max_energy: int
    deploy_type: str  # emp, firewall, supply_drop, extra_moves
    sight_range: int
    team_order: int
    strength: int


ROBOT_TYPE_STATS: Dict[str, RobotTypeStats] = {
    "captain": RobotTypeStats(
        moves_per_turn=3,
        max_energy=2,
        deploy_type="emp",
        sight_range=5,
        team_order=1,
        strength=7
    ),
    "scout": RobotTypeStats(
        moves_per_turn=4,
        max_energy=6,
        deploy_type="extra_moves",
        sight_range=7,
        team_order=3,
        strength=3
    ),
    "defender": RobotTypeStats(
        moves_per_turn=2,
        max_energy=3,
        deploy_type="firewall",
        sight_range=3,
        team_order=3,
        strength=5
    ),
    "engineer": RobotTypeStats(
        moves_per_turn=6,
        max_energy=3,
        deploy_type="supply_drop",
        sight_range=5,
        team_order=0,
        strength=0
    )
}


# ==================== Game Configuration ====================

class GameVariables(BaseModel):
    """Game configuration variables set at game creation"""
    team_size: int = Field(default=2, description="Players per team (2 or 3)")
    map_size: str = Field(default="medium", description="Map size: small, medium, large")
    input_time: int = Field(default=120, description="Seconds for action input")
    review_time: int = Field(default=40, description="Seconds to review replay")
    starting_energy: int = Field(default=2, ge=0, le=3, description="Starting energy 0-3")


# ==================== Player Roles ====================

class PlayerRole(BaseModel):
    """Defines robot counts for a player role"""
    captain_count: int
    scout_count: int
    defender_count: int
    engineer_count: int


# Role definitions: team_size -> role_name -> PlayerRole
PLAYER_ROLES: Dict[int, Dict[str, PlayerRole]] = {
    2: {
        "captain": PlayerRole(captain_count=1, scout_count=0, defender_count=2, engineer_count=2),
        "huntsman": PlayerRole(captain_count=0, scout_count=4, defender_count=0, engineer_count=1),
    },
    3: {
        "captain": PlayerRole(captain_count=1, scout_count=0, defender_count=3, engineer_count=0),
        "huntsman": PlayerRole(captain_count=0, scout_count=5, defender_count=0, engineer_count=0),
        "engineer": PlayerRole(captain_count=0, scout_count=0, defender_count=0, engineer_count=5),
    }
}


# ==================== Runtime Game Objects ====================

class Robot(BaseModel):
    """Runtime state for a robot instance"""
    robot_id: str
    player_id: str
    team: int  # 0 or 1
    type: str  # captain, scout, defender, engineer
    position: List[int]  # [q, r] axial coordinates
    energy: int
    state: str = "active"  # active, stunned
    spawn_position: List[int]  # [q, r] starting position
    # Extra moves granted by Scout deploy this turn
    extra_moves_this_turn: int = 0


class DeployAction(BaseModel):
    """A deploy action attached to a robot's round action"""
    type: str  # emp, firewall, supply_drop, extra_moves
    target_hexes: List[List[int]] = Field(default_factory=list)  # list of [q, r]


class RoundAction(BaseModel):
    """A single round's action for one robot"""
    robot_id: str
    round_number: int  # 0-5
    action_type: str  # move, wait
    before_position: List[int]  # [q, r]
    after_position: List[int]   # [q, r] (same as before if wait)
    deploy: Optional[DeployAction] = None
    # Internal tracking
    status: str = "pending"  # pending, success, fail, error, win


class HexObject(BaseModel):
    """An object placed on the map (emp, firewall, supply_drop, obstacle)"""
    type: str  # emp, firewall, supply_drop, obstacle
    position: List[int]  # [q, r]
    created_turn: int
    created_by: Optional[str] = None  # player_id, None for map obstacles


# ==================== Replay Models ====================

class RobotRoundReplay(BaseModel):
    """Replay data for one robot's action in one round"""
    robot_id: str
    round: int
    animation_type: str  # Stunned, Waiting, Move, Bump, PowerMove, Puzzled
    before_position: List[int]
    after_position: List[int]
    status: str  # success, fail, error, stunned, win


class TurnReplay(BaseModel):
    """Complete replay data for a full turn (6 rounds)"""
    turn: int
    rounds: List[List[RobotRoundReplay]]  # 6 rounds, each with list of robot replays
    hex_objects_created: List[HexObject] = Field(default_factory=list)
    hex_objects_destroyed: List[HexObject] = Field(default_factory=list)
    winner: Optional[int] = None  # winning team (0 or 1), None if no winner


# ==================== Request Models ====================

class MapConfig(BaseModel):
    """Configuration for game map (kept for backward compatibility)"""
    width: int = Field(ge=5, le=50, description="Map width in hexes")
    height: int = Field(ge=5, le=50, description="Map height in hexes")
    terrain_data: Optional[Dict[str, Any]] = Field(default=None, description="Terrain configuration")


class CreateGameRequest(BaseModel):
    """Request to create a new game"""
    max_players: int = Field(ge=2, le=8, default=4, description="Maximum number of players")
    map_config: MapConfig
    game_variables: Optional[GameVariables] = None  # New: game configuration


class JoinGameRequest(BaseModel):
    """Request to join an existing game"""
    player_name: str = Field(min_length=1, max_length=50, description="Player display name")


class MoveAction(BaseModel):
    """Individual move action for a unit (backward compatibility)"""
    unit_id: str = Field(description="Unique identifier for the unit")
    action: str = Field(description="Action type: move, attack, defend, etc.")
    target: Any = Field(description="Target coordinate [q, r] or unit_id")


class SubmitMoveRequest(BaseModel):
    """Request to submit moves for current turn"""
    turn: int = Field(ge=0, description="Turn number for validation")
    # Support both old format (moves) and new format (actions)
    moves: Optional[List[MoveAction]] = None  # Old format for backward compatibility
    actions: Optional[List[RoundAction]] = None  # New format with round actions


class AssignRolesRequest(BaseModel):
    """Request to assign roles to players on a team"""
    team: int  # 0 or 1
    role_assignments: Dict[str, str]  # player_id -> role_name (captain/huntsman/engineer)


# ==================== Response Models ====================

class CreateGameResponse(BaseModel):
    """Response after creating a game"""
    game_id: str
    creator_player_id: str
    api_key: str
    team_0_invite_code: str  # Share with your team
    team_1_invite_code: str  # Share with opponents
    state: str
    max_players: int
    team: int  # 0 or 1 (creator is always team 0)


class InviteCodeJoinRequest(BaseModel):
    """Request body for joining via invite code"""
    player_name: str


class JoinGameResponse(BaseModel):
    """Response after joining a game"""
    game_id: str
    player_id: str
    api_key: str
    map: Dict[str, Any]
    current_players: int
    max_players: int
    state: str
    team: int  # 0 or 1 (assigned by invite code)


class GameStatusResponse(BaseModel):
    """Response for game status check"""
    game_id: str
    state: str
    current_turn: int
    moves_submitted: int
    moves_required: int
    all_moves_in: bool


class SubmitMoveResponse(BaseModel):
    """Response after submitting a move"""
    success: bool
    turn: int
    moves_submitted: int
    moves_required: int
    processing: bool
    validation_errors: List[str] = Field(default_factory=list)


class TurnResultsResponse(BaseModel):
    """Response when polling for turn results"""
    ready: bool
    turn: int
    state: Optional[str] = None
    updates: Optional[List[Dict[str, Any]]] = None
    events: Optional[List[Dict[str, Any]]] = None
    next_turn: Optional[int] = None
    replay: Optional[Dict[str, Any]] = None  # TurnReplay as dict
    updated_robots: Optional[List[Dict[str, Any]]] = None
    updated_hex_objects: Optional[List[Dict[str, Any]]] = None
    winner: Optional[int] = None  # winning team


class AssignRolesResponse(BaseModel):
    """Response after assigning roles"""
    success: bool
    team: int
    roles_assigned: Dict[str, str]  # player_id -> role_name


class SpawnRobotsResponse(BaseModel):
    """Response after spawning robots"""
    success: bool
    robots_created: int
    robots: List[Dict[str, Any]]


class InitialStateResponse(BaseModel):
    """Response with full initial game state"""
    game_id: str
    current_turn: int
    team_with_initiative: int
    map: Dict[str, Any]
    game_variables: Dict[str, Any]
    player_robots: List[Dict[str, Any]]  # Full robot data for player's own robots
    other_robots: List[Dict[str, Any]]   # Limited data for enemy/other robots
    hex_objects: List[Dict[str, Any]]


# ==================== Internal Models ====================

class GameMeta(BaseModel):
    """Internal model for game metadata"""
    state: str  # waiting_for_players, in_progress, processing_turn, complete
    current_turn: int
    player_count: int
    max_players: int
    created_at: str


# ==================== Error Response Models ====================

class ErrorResponse(BaseModel):
    """Standard error response"""
    detail: str
    error_code: Optional[str] = None
