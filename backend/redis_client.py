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
            "created_at": data.get("created_at"),
            "initiative_team": int(data.get("initiative_team", 0)),
            "team_size": int(data.get("team_size", 2))
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
            "created_at": data.get("created_at", ""),
            "initiative_team": str(data.get("initiative_team", 0)),
            "team_size": str(data.get("team_size", 2))
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

    def flip_initiative(self, game_id: str) -> int:
        """Flip initiative team and return new initiative team"""
        meta = self.get_game_meta(game_id)
        new_initiative = 1 - meta.get("initiative_team", 0)
        key = f"game:{game_id}:meta"
        self.client.hset(key, "initiative_team", str(new_initiative))
        return new_initiative

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

        # Refresh TTL for all game keys (scan for all game-related keys)
        pattern = f"game:{game_id}:*"
        keys = self.client.keys(pattern)
        for key in keys:
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

    # ==================== Player Info ====================

    def store_player_info(self, game_id: str, player_id: str, player_name: str, team: int):
        """Store player display info (name, team assignment)"""
        key = f"game:{game_id}:player_info:{player_id}"
        self.client.hset(key, mapping={
            "player_name": player_name,
            "team": str(team)
        })
        self._refresh_game_ttl(game_id)

    def get_player_info(self, game_id: str, player_id: str) -> Optional[Dict[str, Any]]:
        """Get player info"""
        key = f"game:{game_id}:player_info:{player_id}"
        data = self.client.hgetall(key)
        if not data:
            return None
        return {
            "player_name": data.get("player_name", ""),
            "team": int(data.get("team", 0))
        }

    def get_team_player_count(self, game_id: str, team: int) -> int:
        """Get current player count for a specific team"""
        players = self.get_game_players(game_id)
        count = 0
        for player_id in players:
            player_info = self.get_player_info(game_id, player_id)
            if player_info and player_info.get("team") == team:
                count += 1
        return count

    # ==================== Invite Codes ====================

    def store_invite_code(self, invite_code: str, game_id: str, team: int, ttl: int):
        """Store invite code mapping to game_id and team"""
        key = f"invite_code:{invite_code}"
        data = {"game_id": game_id, "team": team}
        self.client.setex(key, ttl, json.dumps(data))

    def get_invite_code_info(self, invite_code: str) -> Optional[Dict]:
        """Get game_id and team from invite code"""
        key = f"invite_code:{invite_code}"
        data = self.client.get(key)
        if data:
            return json.loads(data)
        return None

    def delete_invite_code(self, invite_code: str):
        """Delete an invite code (when game ends or code revoked)"""
        key = f"invite_code:{invite_code}"
        self.client.delete(key)

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

    # ==================== Game Variables ====================

    def store_game_variables(self, game_id: str, variables: Dict[str, Any]):
        """Store game variables as JSON"""
        key = f"game:{game_id}:variables"
        self.client.set(key, json.dumps(variables))
        self._refresh_game_ttl(game_id)

    def get_game_variables(self, game_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve game variables"""
        key = f"game:{game_id}:variables"
        data = self.client.get(key)
        return json.loads(data) if data else None

    # ==================== Robot Management ====================

    def store_robots(self, game_id: str, robots: List[Dict[str, Any]]):
        """Store all robots as JSON list"""
        key = f"game:{game_id}:robots"
        self.client.set(key, json.dumps(robots))
        self._refresh_game_ttl(game_id)

    def get_robots(self, game_id: str) -> List[Dict[str, Any]]:
        """Retrieve all robots"""
        key = f"game:{game_id}:robots"
        data = self.client.get(key)
        return json.loads(data) if data else []

    def get_robot(self, game_id: str, robot_id: str) -> Optional[Dict[str, Any]]:
        """Get a specific robot by ID"""
        robots = self.get_robots(game_id)
        for robot in robots:
            if robot["robot_id"] == robot_id:
                return robot
        return None

    def update_robot(self, game_id: str, robot_id: str, updates: Dict[str, Any]):
        """Update a specific robot's fields"""
        robots = self.get_robots(game_id)
        for robot in robots:
            if robot["robot_id"] == robot_id:
                robot.update(updates)
                break
        self.store_robots(game_id, robots)

    def update_robot_position(self, game_id: str, robot_id: str, position: List[int]):
        """Update robot's position"""
        self.update_robot(game_id, robot_id, {"position": position})

    def update_robot_energy(self, game_id: str, robot_id: str, energy: int):
        """Update robot's energy level"""
        self.update_robot(game_id, robot_id, {"energy": energy})

    def update_robot_state(self, game_id: str, robot_id: str, state: str):
        """Update robot's state (active/stunned)"""
        self.update_robot(game_id, robot_id, {"state": state})

    # ==================== Role Management ====================

    def assign_role(self, game_id: str, team: int, player_id: str, role_name: str):
        """Assign a role to a player on a team"""
        key = f"game:{game_id}:team:{team}:roles"
        self.client.hset(key, player_id, role_name)
        self._refresh_game_ttl(game_id)

    def get_team_roles(self, game_id: str, team: int) -> Dict[str, str]:
        """Get all role assignments for a team"""
        key = f"game:{game_id}:team:{team}:roles"
        return self.client.hgetall(key)

    def get_player_role(self, game_id: str, team: int, player_id: str) -> Optional[str]:
        """Get a specific player's role"""
        key = f"game:{game_id}:team:{team}:roles"
        return self.client.hget(key, player_id)

    def get_player_team(self, game_id: str, player_id: str) -> Optional[int]:
        """Find which team a player is on by checking roles"""
        for team in [0, 1]:
            roles = self.get_team_roles(game_id, team)
            if player_id in roles:
                return team
        # Check player_info as fallback
        info = self.get_player_info(game_id, player_id)
        if info:
            return info["team"]
        return None

    # ==================== Hex Objects ====================

    def get_hex_objects(self, game_id: str) -> List[Dict[str, Any]]:
        """Get all hex objects"""
        key = f"game:{game_id}:hex_objects"
        data = self.client.get(key)
        return json.loads(data) if data else []

    def store_hex_objects(self, game_id: str, objects: List[Dict[str, Any]]):
        """Store all hex objects"""
        key = f"game:{game_id}:hex_objects"
        self.client.set(key, json.dumps(objects))
        self._refresh_game_ttl(game_id)

    def add_hex_object(self, game_id: str, hex_obj: Dict[str, Any]):
        """Add a hex object"""
        objects = self.get_hex_objects(game_id)
        objects.append(hex_obj)
        self.store_hex_objects(game_id, objects)

    def remove_hex_object(self, game_id: str, position: List[int], obj_type: str = None) -> Optional[Dict[str, Any]]:
        """Remove a hex object at position (optionally filtered by type). Returns removed object."""
        objects = self.get_hex_objects(game_id)
        removed = None
        new_objects = []
        for obj in objects:
            if obj["position"] == position and (obj_type is None or obj["type"] == obj_type):
                if removed is None:
                    removed = obj
                    continue  # Remove first match
            new_objects.append(obj)
        self.store_hex_objects(game_id, new_objects)
        return removed

    def get_hex_object_at(self, game_id: str, position: List[int], obj_type: str = None) -> Optional[Dict[str, Any]]:
        """Get hex object at a position (optionally filtered by type)"""
        objects = self.get_hex_objects(game_id)
        for obj in objects:
            if obj["position"] == position:
                if obj_type is None or obj["type"] == obj_type:
                    return obj
        return None

    def add_hex_objects_batch(self, game_id: str, new_objects: List[Dict[str, Any]]):
        """Add multiple hex objects at once"""
        objects = self.get_hex_objects(game_id)
        objects.extend(new_objects)
        self.store_hex_objects(game_id, objects)

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

    # ==================== Turn Replay ====================

    def store_turn_replay(self, game_id: str, turn: int, replay: Dict[str, Any]):
        """Store turn replay data"""
        key = f"game:{game_id}:turn:{turn}:replay"
        self.client.set(key, json.dumps(replay))
        self.client.expire(key, Config.TTL_ACTIVE_GAME)
        self._refresh_game_ttl(game_id)

    def get_turn_replay(self, game_id: str, turn: int) -> Optional[Dict[str, Any]]:
        """Get turn replay data"""
        key = f"game:{game_id}:turn:{turn}:replay"
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
