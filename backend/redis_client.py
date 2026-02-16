import redis
import json
from typing import Optional, Dict, List, Any
from config import Config


class RedisClient:
    """Redis connection and data access layer for game state management"""

    def __init__(self, redis_url: str = None):
        """Initialize Redis connection"""
        self.redis_url = redis_url or Config.REDIS_URL
        self._client = None

    @property
    def client(self) -> redis.Redis:
        """Get Redis client connection (lazy initialization)"""
        if self._client is None:
            self._client = redis.from_url(
                self.redis_url,
                decode_responses=True,
                encoding='utf-8'
            )
        return self._client

    def health_check(self) -> bool:
        """Check if Redis connection is healthy"""
        try:
            return self.client.ping()
        except Exception:
            return False

    # ==================== Game Metadata ====================

    def get_game_meta(self, game_id: str) -> Optional[Dict[str, Any]]:
        """Get game metadata from Redis"""
        key = f"game:{game_id}:meta"
        data = self.client.hgetall(key)
        if not data:
            return None

        # Convert string values to appropriate types
        return {
            "state": data.get("state"),
            "current_turn": int(data.get("current_turn", 0)),
            "player_count": int(data.get("player_count", 0)),
            "max_players": int(data.get("max_players", 4)),
            "created_at": data.get("created_at")
        }

    def set_game_meta(self, game_id: str, data: Dict[str, Any], ttl: int = None):
        """Store game metadata in Redis with TTL"""
        key = f"game:{game_id}:meta"

        # Convert all values to strings for Redis hash
        redis_data = {
            "state": data.get("state", "waiting_for_players"),
            "current_turn": str(data.get("current_turn", 0)),
            "player_count": str(data.get("player_count", 0)),
            "max_players": str(data.get("max_players", 4)),
            "created_at": data.get("created_at", "")
        }

        self.client.hset(key, mapping=redis_data)

        # Set TTL if provided
        if ttl:
            self.client.expire(key, ttl)

    def update_game_state(self, game_id: str, state: str):
        """Update game state"""
        key = f"game:{game_id}:meta"
        self.client.hset(key, "state", state)
        self._refresh_game_ttl(game_id)

    def increment_turn(self, game_id: str) -> int:
        """Increment current turn and return new turn number"""
        key = f"game:{game_id}:meta"
        new_turn = self.client.hincrby(key, "current_turn", 1)
        self._refresh_game_ttl(game_id)
        return new_turn

    def _refresh_game_ttl(self, game_id: str):
        """Refresh TTL for all game-related keys"""
        meta = self.get_game_meta(game_id)
        if not meta:
            return

        # Determine TTL based on game state
        if meta["state"] == "complete":
            ttl = Config.TTL_COMPLETED_GAME
        else:
            ttl = Config.TTL_ACTIVE_GAME

        # Refresh TTL for all game keys
        keys_to_refresh = [
            f"game:{game_id}:meta",
            f"game:{game_id}:players",
            f"game:{game_id}:map"
        ]

        for key in keys_to_refresh:
            if self.client.exists(key):
                self.client.expire(key, ttl)

    # ==================== Game Players ====================

    def add_player_to_game(self, game_id: str, player_id: str):
        """Add player to game's player set"""
        key = f"game:{game_id}:players"
        self.client.sadd(key, player_id)

        # Update player count in metadata
        meta_key = f"game:{game_id}:meta"
        self.client.hincrby(meta_key, "player_count", 1)

        self._refresh_game_ttl(game_id)

    def get_game_players(self, game_id: str) -> List[str]:
        """Get all players in a game"""
        key = f"game:{game_id}:players"
        return list(self.client.smembers(key))

    def is_player_in_game(self, game_id: str, player_id: str) -> bool:
        """Check if player is in the game"""
        key = f"game:{game_id}:players"
        return self.client.sismember(key, player_id)

    # ==================== Game Map ====================

    def store_game_map(self, game_id: str, map_data: Dict[str, Any]):
        """Store game map as JSON"""
        key = f"game:{game_id}:map"
        self.client.set(key, json.dumps(map_data))
        self._refresh_game_ttl(game_id)

    def get_game_map(self, game_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve game map"""
        key = f"game:{game_id}:map"
        data = self.client.get(key)
        return json.loads(data) if data else None

    # ==================== Turn Moves ====================

    def store_move(self, game_id: str, turn: int, player_id: str, move_data: Dict[str, Any]):
        """Store player's move for a specific turn"""
        key = f"game:{game_id}:turn:{turn}:moves"
        self.client.hset(key, player_id, json.dumps(move_data))

        # Set TTL for move data
        self.client.expire(key, Config.TTL_ACTIVE_GAME)
        self._refresh_game_ttl(game_id)

    def has_player_submitted_move(self, game_id: str, turn: int, player_id: str) -> bool:
        """Check if player has already submitted a move for this turn"""
        key = f"game:{game_id}:turn:{turn}:moves"
        return self.client.hexists(key, player_id)

    def get_turn_moves(self, game_id: str, turn: int) -> Dict[str, Any]:
        """Get all moves for a specific turn"""
        key = f"game:{game_id}:turn:{turn}:moves"
        moves_raw = self.client.hgetall(key)

        # Parse JSON for each player's move
        moves = {}
        for player_id, move_json in moves_raw.items():
            moves[player_id] = json.loads(move_json)

        return moves

    def count_turn_moves(self, game_id: str, turn: int) -> int:
        """Count how many moves have been submitted for a turn"""
        key = f"game:{game_id}:turn:{turn}:moves"
        return self.client.hlen(key)

    # ==================== Turn Results ====================

    def store_turn_results(self, game_id: str, turn: int, results: Dict[str, Any]):
        """Store turn processing results"""
        key = f"game:{game_id}:turn:{turn}:results"
        self.client.set(key, json.dumps(results))
        self.client.expire(key, Config.TTL_ACTIVE_GAME)
        self._refresh_game_ttl(game_id)

    def get_turn_results(self, game_id: str, turn: int) -> Optional[Dict[str, Any]]:
        """Get turn processing results if available"""
        key = f"game:{game_id}:turn:{turn}:results"
        data = self.client.get(key)
        return json.loads(data) if data else None

    # ==================== Player Sessions ====================

    def set_player_current_game(self, player_id: str, game_id: str):
        """Set player's current active game"""
        key = f"player:{player_id}:current_game"
        self.client.set(key, game_id, ex=Config.TTL_PLAYER_SESSION)

    def get_player_current_game(self, player_id: str) -> Optional[str]:
        """Get player's current active game"""
        key = f"player:{player_id}:current_game"
        return self.client.get(key)

    # ==================== Utility Functions ====================

    def game_exists(self, game_id: str) -> bool:
        """Check if game exists in Redis"""
        key = f"game:{game_id}:meta"
        return self.client.exists(key) > 0

    def delete_game(self, game_id: str):
        """Delete all game-related keys (cleanup)"""
        # Find all keys related to this game
        pattern = f"game:{game_id}:*"
        keys = self.client.keys(pattern)

        if keys:
            self.client.delete(*keys)


# Global Redis client instance
redis_client = RedisClient()
