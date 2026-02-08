from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional


# ==================== Request Models ====================

class MapConfig(BaseModel):
    """Configuration for game map"""
    width: int = Field(ge=5, le=50, description="Map width in hexes")
    height: int = Field(ge=5, le=50, description="Map height in hexes")
    terrain_data: Optional[Dict[str, Any]] = Field(default=None, description="Terrain configuration")


class CreateGameRequest(BaseModel):
    """Request to create a new game"""
    max_players: int = Field(ge=2, le=8, default=4, description="Maximum number of players")
    map_config: MapConfig


class JoinGameRequest(BaseModel):
    """Request to join an existing game"""
    player_name: str = Field(min_length=1, max_length=50, description="Player display name")


class MoveAction(BaseModel):
    """Individual move action for a unit"""
    unit_id: str = Field(description="Unique identifier for the unit")
    action: str = Field(description="Action type: move, attack, defend, etc.")
    target: Any = Field(description="Target coordinate [q, r] or unit_id")


class SubmitMoveRequest(BaseModel):
    """Request to submit moves for current turn"""
    turn: int = Field(ge=0, description="Turn number for validation")
    moves: List[MoveAction] = Field(description="List of move actions")


# ==================== Response Models ====================

class CreateGameResponse(BaseModel):
    """Response after creating a game"""
    game_id: str
    creator_player_id: str
    api_key: str
    state: str
    max_players: int


class JoinGameResponse(BaseModel):
    """Response after joining a game"""
    game_id: str
    player_id: str
    api_key: str
    map: Dict[str, Any]
    current_players: int
    max_players: int
    state: str


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


class TurnResultsResponse(BaseModel):
    """Response when polling for turn results"""
    ready: bool
    turn: int
    state: Optional[str] = None
    updates: Optional[List[Dict[str, Any]]] = None
    events: Optional[List[Dict[str, Any]]] = None
    next_turn: Optional[int] = None


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
