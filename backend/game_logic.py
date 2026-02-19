import random
import uuid
from typing import Dict, Any, List, Optional, Tuple
from redis_client import redis_client
from models import (
    Robot, RoundAction, DeployAction, HexObject, TurnReplay, RobotRoundReplay,
    ROBOT_TYPE_STATS, PLAYER_ROLES, GameVariables
)


# ==================== Hex Math ====================

def hex_distance(a: List[int], b: List[int]) -> int:
    """Calculate hex grid distance between two axial coordinates"""
    aq, ar = a[0], a[1]
    bq, br = b[0], b[1]
    return (abs(aq - bq) + abs(aq + ar - bq - br) + abs(ar - br)) // 2


def hex_neighbors(pos: List[int]) -> List[List[int]]:
    """Get all 6 neighboring hex positions"""
    q, r = pos[0], pos[1]
    directions = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1)]
    return [[q + dq, r + dr] for dq, dr in directions]


def hex_line(start: List[int], end: List[int]) -> List[List[int]]:
    """Get hexes in a straight line from start to end (inclusive)"""
    dist = hex_distance(start, end)
    if dist == 0:
        return [start]
    results = []
    for i in range(dist + 1):
        t = i / dist
        # Cube coordinates for interpolation
        sq, sr = start[0], start[1]
        ss = -sq - sr
        eq, er = end[0], end[1]
        es = -eq - er
        rq = sq + (eq - sq) * t
        rr = sr + (er - sr) * t
        rs = ss + (es - ss) * t
        # Round cube coords
        rq_r, rr_r, rs_r = round(rq), round(rr), round(rs)
        dq, dr, ds = abs(rq_r - rq), abs(rr_r - rr), abs(rs_r - rs)
        if dq > dr and dq > ds:
            rq_r = -rr_r - rs_r
        elif dr > ds:
            rr_r = -rq_r - rs_r
        results.append([rq_r, rr_r])
    return results


def hexes_within_radius(center: List[int], radius: int) -> List[List[int]]:
    """Get all hexes within radius of center"""
    result = []
    for q in range(-radius, radius + 1):
        for r in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
            result.append([center[0] + q, center[1] + r])
    return result


# ==================== Robot & Map Helpers ====================

def get_robot_at_position(robots: List[Dict], position: List[int]) -> Optional[Dict]:
    """Find robot at a given position"""
    for robot in robots:
        if robot["position"] == position and robot["state"] != "stunned":
            return robot
    return None


def get_robot_at_position_any_state(robots: List[Dict], position: List[int]) -> Optional[Dict]:
    """Find robot at position regardless of state"""
    for robot in robots:
        if robot["position"] == position:
            return robot
    return None


def is_hex_obstructed(map_data: Dict, position: List[int]) -> bool:
    """Check if a hex is an impassable obstacle on the map"""
    hexes = map_data.get("hexes", [])
    for hex_data in hexes:
        if hex_data.get("q") == position[0] and hex_data.get("r") == position[1]:
            return not hex_data.get("passable", True)
    return True  # Out of bounds = obstructed


def is_in_map_bounds(map_data: Dict, position: List[int]) -> bool:
    """Check if position is within map bounds"""
    width = map_data.get("width", 0)
    height = map_data.get("height", 0)
    q, r = position[0], position[1]
    return 0 <= q < width and 0 <= r < height


def establish_robot_order(robots: List[Dict], initiative_team: int) -> List[Dict]:
    """
    Sort robots by initiative order:
    1. Initiative team robots go first
    2. Within team: sort by team_order (lowest first)
    3. Ties broken randomly
    """
    initiative_robots = [r for r in robots if r["team"] == initiative_team]
    other_robots = [r for r in robots if r["team"] != initiative_team]

    def sort_key(robot):
        stats = ROBOT_TYPE_STATS.get(robot["type"])
        team_order = stats.team_order if stats else 99
        return (team_order, random.random())

    initiative_robots.sort(key=sort_key)
    other_robots.sort(key=sort_key)

    return initiative_robots + other_robots


# ==================== Deploy Action Processing ====================

def process_deploy_action(
    game_id: str,
    robot: Dict,
    deploy: Dict,
    current_turn: int,
    hex_objects_created: List[Dict]
) -> bool:
    """
    Process a deploy action. Returns True if successful.
    Modifies robot energy in-place and adds hex objects to game state.
    """
    deploy_type = deploy.get("type")
    target_hexes = deploy.get("target_hexes", [])

    # Deduct 1 energy
    if robot["energy"] <= 0:
        return False

    robot["energy"] -= 1

    if deploy_type == "emp":
        # Create EMP objects on all target hexes
        for pos in target_hexes:
            obj = {
                "type": "emp",
                "position": pos,
                "created_turn": current_turn,
                "created_by": robot["player_id"]
            }
            hex_objects_created.append(obj)

    elif deploy_type == "firewall":
        # Create firewall objects on all target hexes
        for pos in target_hexes:
            obj = {
                "type": "firewall",
                "position": pos,
                "created_turn": current_turn,
                "created_by": robot["player_id"]
            }
            hex_objects_created.append(obj)

    elif deploy_type == "supply_drop":
        # Create supply drop on target hex
        for pos in target_hexes:
            obj = {
                "type": "supply_drop",
                "position": pos,
                "created_turn": current_turn,
                "created_by": robot["player_id"]
            }
            hex_objects_created.append(obj)

    elif deploy_type == "extra_moves":
        # Extra moves are handled client-side; server just records energy cost
        robot["extra_moves_this_turn"] = robot.get("extra_moves_this_turn", 0) + 2

    return True


# ==================== Core Turn Processing ====================

def process_robot_action(
    robot: Dict,
    action: Dict,
    all_robots: List[Dict],
    hex_objects: List[Dict],
    map_data: Dict,
    current_turn: int,
    hex_objects_created: List[Dict],
    hex_objects_destroyed: List[Dict]
) -> Tuple[Dict, str, str]:
    """
    Process a single robot's action for one round.

    Returns: (updated_robot, animation_type, action_status)
    where animation_type is one of: Stunned, Waiting, Move, Bump, PowerMove, Puzzled
    and action_status is one of: stunned, success, fail, error, win
    """
    action_type = action.get("action_type", "wait")
    before_pos = action.get("before_position", robot["position"])
    after_pos = action.get("after_position", before_pos)
    deploy = action.get("deploy")

    # Case 1: Robot is stunned - skip
    if robot["state"] == "stunned":
        return robot, "Stunned", "stunned"

    # Check if robot is standing on a stronger enemy (from previous round's positioning)
    # This check: if robot's CURRENT position has a stronger enemy robot
    robots_at_before = [r for r in all_robots
                        if r["position"] == before_pos
                        and r["robot_id"] != robot["robot_id"]
                        and r["state"] != "stunned"]
    for occupant in robots_at_before:
        if occupant["team"] != robot["team"]:
            occupant_strength = ROBOT_TYPE_STATS[occupant["type"]].strength
            robot_strength = ROBOT_TYPE_STATS[robot["type"]].strength
            if occupant_strength > robot_strength:
                # Case 1 (variant): Standing on stronger enemy - stun and send to spawn
                robot["position"] = robot["spawn_position"][:]
                robot["state"] = "stunned"
                return robot, "Stunned", "stunned"

    if action_type == "wait":
        # Check hex objects at current position
        obj_at_pos = None
        for obj in hex_objects:
            if obj["position"] == before_pos:
                obj_at_pos = obj
                break

        if obj_at_pos and obj_at_pos["type"] == "firewall":
            # Case 2: Wait + Firewall - destroy firewall, stun, send to spawn
            hex_objects_destroyed.append(obj_at_pos)
            hex_objects[:] = [o for o in hex_objects if o is not obj_at_pos]
            robot["position"] = robot["spawn_position"][:]
            robot["state"] = "stunned"
            return robot, "Stunned", "stunned"

        elif obj_at_pos and obj_at_pos["type"] == "emp":
            # Case 3: Wait + EMP - stun in place
            robot["state"] = "stunned"
            return robot, "Stunned", "stunned"

        else:
            # Case 4: Wait (normal) - process deploy
            if deploy:
                process_deploy_action(game_id=None, robot=robot, deploy=deploy,
                                      current_turn=current_turn,
                                      hex_objects_created=hex_objects_created)
            return robot, "Waiting", "success"

    elif action_type == "move":
        # Find robot at target position
        target_robot = get_robot_at_position(all_robots, after_pos)

        if target_robot is None:
            # Check if obstructed by terrain
            if is_hex_obstructed(map_data, after_pos):
                # Case 10: Move to obstacle
                return robot, "Bump", "error"

            # Check for supply drop at target
            supply_obj = next((o for o in hex_objects
                               if o["position"] == after_pos and o["type"] == "supply_drop"), None)

            if supply_obj:
                # Case 11: Move to supply drop - gain energy
                stats = ROBOT_TYPE_STATS[robot["type"]]
                robot["energy"] = min(robot["energy"] + 1, stats.max_energy)
                hex_objects_destroyed.append(supply_obj)
                hex_objects[:] = [o for o in hex_objects if o is not supply_obj]
                robot["position"] = after_pos[:]
                if deploy:
                    process_deploy_action(game_id=None, robot=robot, deploy=deploy,
                                          current_turn=current_turn,
                                          hex_objects_created=hex_objects_created)
                return robot, "Move", "success"

            # Case 5: Move to empty hex
            robot["position"] = after_pos[:]
            if deploy:
                process_deploy_action(game_id=None, robot=robot, deploy=deploy,
                                      current_turn=current_turn,
                                      hex_objects_created=hex_objects_created)
            return robot, "Move", "success"

        else:
            # There's a robot at the target
            if target_robot["team"] == robot["team"]:
                # Case 7: Move to same-team robot - blocked
                return robot, "Bump", "fail"

            else:
                # Enemy robot at target
                robot_strength = ROBOT_TYPE_STATS[robot["type"]].strength
                target_strength = ROBOT_TYPE_STATS[target_robot["type"]].strength

                if target_robot["type"] == "captain":
                    # Case 6: Move to enemy Captain - WIN
                    return robot, "Bump", "win"

                elif robot_strength > target_strength:
                    # Case 8: Power move - push enemy, robot moves in
                    # Enemy robot gets stunned and sent to spawn
                    target_robot["position"] = target_robot["spawn_position"][:]
                    target_robot["state"] = "stunned"
                    robot["position"] = after_pos[:]
                    if deploy:
                        process_deploy_action(game_id=None, robot=robot, deploy=deploy,
                                              current_turn=current_turn,
                                              hex_objects_created=hex_objects_created)
                    return robot, "PowerMove", "success"

                else:
                    # Case 9: Move to stronger enemy - blocked
                    return robot, "Bump", "fail"

    # Case 12: Unrecognized action
    return robot, "Puzzled", "error"


def process_turn_with_robots(
    game_id: str,
    turn: int,
    all_moves: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Full 6-round turn processing using the new robot mechanics.

    Args:
        game_id: Game identifier
        turn: Current turn number
        all_moves: Dict mapping player_id -> move submission data

    Returns:
        Results dict with replay, updated robot states, win info
    """
    # Load game state
    robots_data = redis_client.get_robots(game_id)
    if not robots_data:
        return {"updates": [], "events": [], "error": "No robots found"}

    meta = redis_client.get_game_meta(game_id)
    initiative_team = meta.get("initiative_team", 0)
    hex_objects = redis_client.get_hex_objects(game_id)
    map_data = redis_client.get_game_map(game_id)
    game_vars = redis_client.get_game_variables(game_id)

    # Work with mutable copies of robots
    robots = [dict(r) for r in robots_data]

    # Parse all player actions into round-based structure
    # Structure: {robot_id: [list of RoundAction dicts, sorted by round_number]}
    robot_actions: Dict[str, List[Dict]] = {}
    for player_id, player_data in all_moves.items():
        if isinstance(player_data, dict) and "actions" in player_data:
            # New format
            for action in player_data["actions"]:
                rid = action.get("robot_id")
                if rid not in robot_actions:
                    robot_actions[rid] = []
                robot_actions[rid].append(action)

    # Sort actions by round number for each robot
    for rid in robot_actions:
        robot_actions[rid].sort(key=lambda a: a.get("round_number", 0))

    # For robots with no submitted actions, create 6 "wait" actions
    for robot in robots:
        rid = robot["robot_id"]
        if rid not in robot_actions:
            robot_actions[rid] = [
                {
                    "robot_id": rid,
                    "round_number": i,
                    "action_type": "wait",
                    "before_position": robot["position"][:],
                    "after_position": robot["position"][:],
                    "deploy": None,
                    "status": "pending"
                }
                for i in range(6)
            ]

    # Track action processing state
    # action_index[robot_id] = index of next action to process
    action_index: Dict[str, int] = {r["robot_id"]: 0 for r in robots}

    # Establish robot order (constant throughout the turn)
    ordered_robots = establish_robot_order(robots, initiative_team)
    # Keep references in order list
    robot_order_ids = [r["robot_id"] for r in ordered_robots]

    # Build replay structure
    replay_rounds: List[List[Dict]] = [[] for _ in range(6)]
    hex_objects_created_all: List[Dict] = []
    hex_objects_destroyed_all: List[Dict] = []
    winner = None
    winning_team = None

    # Process 6 rounds
    for round_num in range(6):
        if winner:
            break

        round_hex_objects_created: List[Dict] = []
        round_hex_objects_destroyed: List[Dict] = []

        # Process each robot in order
        for robot_id in robot_order_ids:
            # Find robot in current state
            robot = next((r for r in robots if r["robot_id"] == robot_id), None)
            if not robot:
                continue

            # Find the earliest pending action
            actions = robot_actions.get(robot_id, [])
            action = None
            for idx in range(action_index.get(robot_id, 0), len(actions)):
                if actions[idx].get("status", "pending") == "pending":
                    action = actions[idx]
                    action_index[robot_id] = idx
                    break

            if action is None:
                # No more actions - robot waits
                action = {
                    "robot_id": robot_id,
                    "round_number": round_num,
                    "action_type": "wait",
                    "before_position": robot["position"][:],
                    "after_position": robot["position"][:],
                    "deploy": None,
                    "status": "pending"
                }

            before_pos = robot["position"][:]

            # Process the action
            updated_robot, animation, status = process_robot_action(
                robot=robot,
                action=action,
                all_robots=robots,
                hex_objects=hex_objects,
                map_data=map_data if map_data else {"hexes": [], "width": 0, "height": 0},
                current_turn=turn,
                hex_objects_created=round_hex_objects_created,
                hex_objects_destroyed=round_hex_objects_destroyed
            )

            after_pos = robot["position"][:]

            # Always advance action index by 1 per round (each round consumes one action slot)
            # Stunned robots skip their action but still use up a round slot
            ai = action_index.get(robot_id, 0)
            if status not in ("stunned",) and ai < len(actions):
                # Mark the processed action with its outcome
                actions[ai]["status"] = status
            action_index[robot_id] = ai + 1

            # Record replay frame
            replay_frame = {
                "robot_id": robot_id,
                "round": round_num,
                "animation_type": animation,
                "before_position": before_pos,
                "after_position": after_pos,
                "status": status
            }
            replay_rounds[round_num].append(replay_frame)

            # Check win condition
            if status == "win":
                winner = robot_id
                winning_team = robot["team"]
                break

        # Apply created hex objects to the active list
        hex_objects.extend(round_hex_objects_created)
        hex_objects_created_all.extend(round_hex_objects_created)
        hex_objects_destroyed_all.extend(round_hex_objects_destroyed)

        if winner:
            break

    # Save updated robot states back to Redis
    redis_client.store_robots(game_id, robots)
    redis_client.store_hex_objects(game_id, hex_objects)

    # Build replay object
    replay = {
        "turn": turn,
        "rounds": replay_rounds,
        "hex_objects_created": hex_objects_created_all,
        "hex_objects_destroyed": hex_objects_destroyed_all,
        "winner": winning_team
    }

    # Store replay
    redis_client.store_turn_replay(game_id, turn, replay)

    # Build legacy-format results for backward compatibility
    updates = []
    events = []
    for robot in robots:
        updates.append({
            "type": "robot_updated",
            "robot_id": robot["robot_id"],
            "player_id": robot["player_id"],
            "position": robot["position"],
            "state": robot["state"],
            "energy": robot["energy"]
        })

    if winning_team is not None:
        events.append({
            "type": "game_won",
            "winning_team": winning_team,
            "message": f"Team {winning_team} wins!"
        })

    return {
        "updates": updates,
        "events": events,
        "replay": replay,
        "robots": robots,
        "hex_objects": hex_objects,
        "winner": winning_team
    }


def calculate_turn_results(moves: Dict[str, Any], game_id: str) -> Dict[str, Any]:
    """
    Process all player moves and return delta updates.
    Supports both old format (moves) and new format (actions).
    """
    # Check if this game has robots (new format)
    robots = redis_client.get_robots(game_id)
    meta = redis_client.get_game_meta(game_id)
    current_turn = meta.get("current_turn", 0) if meta else 0

    if robots:
        # New format: process with robot mechanics
        return process_turn_with_robots(game_id, current_turn, moves)

    # Old format fallback: stub implementation
    updates = []
    events = []

    for player_id, player_moves in moves.items():
        if not isinstance(player_moves, dict):
            continue

        move_list = player_moves.get("moves", [])

        for move in move_list:
            unit_id = move.get("unit_id")
            action = move.get("action")
            target = move.get("target")

            if action == "move":
                updates.append({
                    "type": "unit_moved",
                    "player_id": player_id,
                    "unit_id": unit_id,
                    "new_position": target
                })
                events.append({
                    "type": "move_completed",
                    "player_id": player_id,
                    "unit_id": unit_id,
                    "message": f"Unit {unit_id} moved"
                })

    return {
        "updates": updates,
        "events": events
    }


def check_win_condition(game_id: str) -> Optional[int]:
    """
    Check if game has reached a win condition.
    Returns winning team (0 or 1) or None if no winner yet.
    """
    # Check last turn replay for winner
    meta = redis_client.get_game_meta(game_id)
    if not meta:
        return None

    current_turn = meta.get("current_turn", 0)
    replay = redis_client.get_turn_replay(game_id, current_turn)
    if replay and replay.get("winner") is not None:
        return replay["winner"]

    # Also check robots directly - if no Captain exists on a team, that team lost
    robots = redis_client.get_robots(game_id)
    if robots:
        team_has_captain = {0: False, 1: False}
        for robot in robots:
            if robot["type"] == "captain":
                team_has_captain[robot["team"]] = True

        for team, has_captain in team_has_captain.items():
            if not has_captain and len(robots) > 0:
                return 1 - team  # Other team wins

    return None


# ==================== Map Generation ====================

MAP_SIZES = {
    "small": (30, 20),
    "medium": (40, 40),
    "large": (60, 40)
}

# Spawn zone radius to keep clear of obstacles
SPAWN_ZONE_RADIUS = 3


def get_spawn_positions(map_size: str, team_size: int) -> Dict[int, List[List[int]]]:
    """
    Calculate spawn positions for each team.
    Team 0 spawns on left side, Team 1 on right side.
    Returns: {team: [list of spawn positions]}
    """
    width, height = MAP_SIZES.get(map_size, MAP_SIZES["medium"])

    # Count total robots per team based on roles
    roles = PLAYER_ROLES.get(team_size, PLAYER_ROLES[2])
    robots_per_team = 0
    for role in roles.values():
        robots_per_team += (role.captain_count + role.scout_count +
                            role.defender_count + role.engineer_count)

    # Generate spawn positions: team 0 on left (q=1), team 1 on right (q=width-2)
    team0_spawns = []
    team1_spawns = []

    center_r = height // 2
    spacing = max(1, height // (robots_per_team + 1))

    for i in range(robots_per_team):
        r = center_r - (robots_per_team // 2) * spacing + i * spacing
        r = max(1, min(height - 2, r))
        team0_spawns.append([1, r])
        team1_spawns.append([width - 2, r])

    return {0: team0_spawns, 1: team1_spawns}


def generate_default_map(width: int, height: int, terrain_data: Dict[str, Any] = None,
                         game_variables: Dict[str, Any] = None) -> Dict[str, Any]:
    """
    Generate a hex map with obstacles based on game variables.
    """
    hexes = []
    map_size = "medium"
    if game_variables:
        map_size = game_variables.get("map_size", "medium")
        # Use map_size dimensions if provided
        if map_size in MAP_SIZES:
            width, height = MAP_SIZES[map_size]

    # Determine spawn zones to keep clear
    spawn_zones = set()
    # Left side spawn zone (team 0)
    for q in range(0, SPAWN_ZONE_RADIUS + 2):
        for r in range(height):
            spawn_zones.add((q, r))
    # Right side spawn zone (team 1)
    for q in range(width - SPAWN_ZONE_RADIUS - 2, width):
        for r in range(height):
            spawn_zones.add((q, r))

    for q in range(width):
        for r in range(height):
            passable = True
            terrain = "grass"

            # Skip obstacle placement in spawn zones
            in_spawn = (q, r) in spawn_zones

            if not terrain_data and not in_spawn:
                # Create obstacle pattern: water and forest
                if (q + r * 2) % 11 == 0:
                    terrain = "water"
                    passable = False
                elif (q * 2 + r) % 13 == 0:
                    terrain = "water"
                    passable = False
                elif (q + r) % 7 == 0 and q % 3 == 0:
                    terrain = "forest"
                    passable = False

            hexes.append({
                "q": q,
                "r": r,
                "terrain": terrain,
                "passable": passable,
                "occupied_by": None
            })

    team_size = 2
    if game_variables:
        team_size = game_variables.get("team_size", 2)

    spawn_positions = get_spawn_positions(map_size, team_size)

    return {
        "width": width,
        "height": height,
        "hexes": hexes,
        "spawn_positions": spawn_positions,
        "spawn_points": [  # Backward compatibility
            {"q": 0, "r": 0, "player_slot": 1},
            {"q": width - 1, "r": 0, "player_slot": 2},
            {"q": 0, "r": height - 1, "player_slot": 3},
            {"q": width - 1, "r": height - 1, "player_slot": 4}
        ]
    }


# ==================== Robot Spawning ====================

def spawn_robots_for_game(
    game_id: str,
    game_variables: Dict[str, Any],
    map_data: Dict[str, Any]
) -> List[Dict]:
    """
    Create Robot instances based on role assignments.
    Returns list of created robot dicts.
    """
    team_size = game_variables.get("team_size", 2)
    starting_energy = game_variables.get("starting_energy", 2)
    map_size = game_variables.get("map_size", "medium")
    roles_config = PLAYER_ROLES.get(team_size, PLAYER_ROLES[2])

    spawn_positions = map_data.get("spawn_positions", {})
    # Convert keys from int to str if needed (JSON serialization)
    if spawn_positions:
        spawn_positions = {
            int(k): v for k, v in spawn_positions.items()
        }

    all_robots = []
    robot_counter = {}  # track spawn position index per team

    for team in [0, 1]:
        robot_counter[team] = 0
        team_spawn_list = spawn_positions.get(team, [])
        team_roles = redis_client.get_team_roles(game_id, team)

        for player_id, role_name in team_roles.items():
            role = roles_config.get(role_name)
            if not role:
                continue

            # Create robots for each type in this role
            robot_types = [
                ("captain", role.captain_count),
                ("scout", role.scout_count),
                ("defender", role.defender_count),
                ("engineer", role.engineer_count),
            ]

            for robot_type, count in robot_types:
                stats = ROBOT_TYPE_STATS[robot_type]
                for _ in range(count):
                    spawn_idx = robot_counter[team]
                    if spawn_idx < len(team_spawn_list):
                        spawn_pos = team_spawn_list[spawn_idx]
                    else:
                        # Fallback spawn position
                        side_q = 1 if team == 0 else map_data.get("width", 40) - 2
                        spawn_pos = [side_q, spawn_idx]

                    robot_counter[team] += 1

                    # Clamp starting energy to robot's max
                    energy = min(starting_energy, stats.max_energy)

                    robot_id = f"robot_{uuid.uuid4().hex[:8]}"
                    robot = {
                        "robot_id": robot_id,
                        "player_id": player_id,
                        "team": team,
                        "type": robot_type,
                        "position": spawn_pos[:],
                        "energy": energy,
                        "state": "active",
                        "spawn_position": spawn_pos[:],
                        "extra_moves_this_turn": 0
                    }
                    all_robots.append(robot)

    return all_robots


def validate_role_assignment(
    team_size: int,
    role_assignments: Dict[str, str],
    existing_roles: Dict[str, str]
) -> List[str]:
    """
    Validate role assignments for a team.
    Returns list of error messages (empty = valid).
    """
    errors = []
    valid_roles = PLAYER_ROLES.get(team_size, {})

    # Check each role assignment is valid
    for player_id, role_name in role_assignments.items():
        if role_name not in valid_roles:
            errors.append(f"Invalid role '{role_name}' for team size {team_size}")

    # Check for duplicate roles (only one Captain, one Huntsman, one Engineer allowed)
    combined = {**existing_roles, **role_assignments}
    role_counts = {}
    for role in combined.values():
        role_counts[role] = role_counts.get(role, 0) + 1

    for role, count in role_counts.items():
        if count > 1:
            errors.append(f"Role '{role}' assigned to multiple players (only one per team)")

    return errors


def validate_player_actions(
    player_id: str,
    actions: List[Dict],
    robots: List[Dict],
    game_id: str
) -> List[str]:
    """
    Validate submitted actions for a player.
    Returns list of validation error messages.
    """
    errors = []

    # Get player's robots
    player_robots = {r["robot_id"]: r for r in robots if r["player_id"] == player_id}

    if not player_robots:
        errors.append("No robots found for this player")
        return errors

    # Group actions by robot_id
    robot_actions: Dict[str, List[Dict]] = {}
    for action in actions:
        rid = action.get("robot_id")
        if rid not in robot_actions:
            robot_actions[rid] = []
        robot_actions[rid].append(action)

    for robot_id, robot_action_list in robot_actions.items():
        if robot_id not in player_robots:
            errors.append(f"Robot {robot_id} does not belong to player {player_id}")
            continue

        robot = player_robots[robot_id]
        stats = ROBOT_TYPE_STATS.get(robot["type"])
        if not stats:
            errors.append(f"Unknown robot type: {robot['type']}")
            continue

        # Count move actions
        move_count = sum(1 for a in robot_action_list if a.get("action_type") == "move")
        max_moves = stats.moves_per_turn + robot.get("extra_moves_this_turn", 0)
        if move_count > max_moves:
            errors.append(
                f"Robot {robot_id} ({robot['type']}) has {move_count} move actions "
                f"but max is {max_moves}"
            )

        # Validate deploy actions
        deploy_count = 0
        for action in robot_action_list:
            deploy = action.get("deploy")
            if deploy:
                deploy_type = deploy.get("type")
                if deploy_type != stats.deploy_type:
                    errors.append(
                        f"Robot {robot_id} ({robot['type']}) cannot use deploy type "
                        f"'{deploy_type}' (must use '{stats.deploy_type}')"
                    )
                deploy_count += 1

        # Check energy for deploys
        if deploy_count > robot["energy"]:
            errors.append(
                f"Robot {robot_id} has {robot['energy']} energy but {deploy_count} deploy actions"
            )

    return errors


def filter_robots_by_sight(
    player_id: str,
    all_robots: List[Dict]
) -> Tuple[List[Dict], List[Dict]]:
    """
    Filter robots based on sight range.
    Returns (player_robots_full, other_robots_limited).
    - player_robots_full: full data for player's own robots
    - other_robots_limited: limited data for visible enemy/other robots
    """
    player_robots = [r for r in all_robots if r["player_id"] == player_id]
    other_robots = [r for r in all_robots if r["player_id"] != player_id]

    # Calculate visible positions (within any player robot's sight range)
    visible_positions = set()
    for robot in player_robots:
        stats = ROBOT_TYPE_STATS.get(robot["type"])
        if stats:
            sight = stats.sight_range
            for other in other_robots:
                if hex_distance(robot["position"], other["position"]) <= sight:
                    visible_positions.add(tuple(other["position"]))

    # Filter other robots to only visible ones, with limited info
    visible_others = []
    for robot in other_robots:
        if tuple(robot["position"]) in visible_positions:
            visible_others.append({
                "robot_id": robot["robot_id"],
                "team": robot["team"],
                "type": robot["type"],
                "position": robot["position"],
                "state": robot["state"]
                # Note: energy intentionally excluded
            })

    return player_robots, visible_others
