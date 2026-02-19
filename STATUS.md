# Project Status - Robot Battle

**Last Updated:** 2026-02-17
**Current Phase:** Phase 2 - Real Game Mechanics (Implementation Complete, Needs Deployment)

---

## Completed Phases

### Phase 1: Backend Deployment ✅

**All tasks complete:**

- Backend fully implemented (FastAPI + Redis, 6 endpoints)
- Deployed to Railway: https://robotbattle-production.up.railway.app
- Redis connected and healthy (`"redis": true`)
- Player counting bug fixed (creator was counted twice)
- All 14 integration tests passing (`python test_api.py`)
- Two game mechanics documents committed to git

**Railway Project:**
- Project: `marvelous-wholeness`
- Project ID: `773c40ec-eaec-4331-873b-4972b42dbe9d`
- Backend URL: https://robotbattle-production.up.railway.app
- Redis: `redis.railway.internal:6379` (internal)
- Environment variables: `REDIS_URL`, `API_SECRET` set (ENVIRONMENT still shows "development" - harmless typo in Railway dashboard)

**Git:**
- Main branch: up to date
- Latest commit: `ed4f1e3` - Fix player counting bug
- New docs committed: `robot_game_backend_mechanics.md`, `robot_game_client_mechanics.md`

---

## Current Phase: Phase 2 - Real Game Mechanics ✅ (Locally Complete)

### What Was Implemented

All Phase 2 sub-phases are complete in local code. Needs deployment to Railway.

**Implemented:**
- 4 robot types with correct stats (Captain, Scout, Defender, Engineer)
- 3 player roles for 2-player teams (Captain, Huntsman) and 3-player teams (Captain, Huntsman, Engineer)
- 6-round turn processing engine with all 12 collision cases
- All 4 deploy actions (EMP, Firewall, Supply Drop, Extra Moves)
- Stun mechanics, Captain capture win condition
- Replay generation with animation types per round
- Sight range filtering (fog of war)
- Realistic map generation with obstacles and spawn zones
- New endpoints: assign_roles, spawn_robots, initial_state
- Comprehensive integration tests in `test_full_game.py`
- Backward compatibility with old test_api.py format

### What Was Previously Missing

~~The deployed backend has **stub implementations** only:~~
~~- No robot types — generic "soldier" units~~
~~- No real turn processing — moves accepted but nothing actually happens~~
~~- No win condition — games never end~~
~~- No deploy actions — no EMP, Firewall, Supply Drop~~
~~- No player roles — no Captain, Huntsman, or Engineer roles~~
~~- No replay data — turn results are bare-bones~~

### Phase 2 Implementation Plan (6 Sub-phases)

#### Phase 2a: Core Data Models *(Simple, ~400-500 lines)*
**File:** `backend/models.py`
- Add `RobotTypeStats` model + `ROBOT_TYPE_STATS` constant for all 4 robot types:
  - **Captain:** 3 moves, max 2 energy, EMP deploy, strength 7, team_order 1
  - **Scout:** 4 moves, max 6 energy, Extra Moves deploy, strength 3, team_order 3
  - **Defender:** 2 moves, max 3 energy, Firewall deploy, strength 5, team_order 3
  - **Engineer:** 6 moves, max 3 energy, Supply Drop deploy, strength 0, team_order 0
- Add `GameVariables` model (team_size, map_size, input_time, review_time, starting_energy)
- Add `PlayerRole` model defining robot counts per role:
  - 2-player teams: Captain (1 Captain + 2 Defender + 2 Engineer), Huntsman (4 Scout + 1 Engineer)
  - 3-player teams: Captain (1 Captain + 3 Defender), Huntsman (5 Scout), Engineer (5 Engineer)
- Add `Robot` model for runtime state (position, energy, state, spawn_position)
- Add `RoundAction` and `DeployAction` models for turn submission
- Add `HexObject` model (EMP/Firewall/SupplyDrop/Obstacle)
- Add `RobotRoundReplay` and `TurnReplay` models for animation data
- Add `AssignRolesRequest` model
- Update `CreateGameRequest` to include `game_variables`
- Update `SubmitMoveRequest` to accept `List[RoundAction]`

#### Phase 2b: Redis Extensions *(Medium, ~300-400 lines)*
**File:** `backend/redis_client.py`
- Add 5 new Redis key namespaces:
  - `game:{id}:robots` — all Robot objects
  - `game:{id}:team:{team}:roles` — player_id → role_name
  - `game:{id}:hex_objects` — EMP/Firewall/SupplyDrop/Obstacle list
  - `game:{id}:turn:{turn}:replay` — TurnReplay object
  - `game:{id}:variables` — GameVariables object
- Add 20+ new methods: store/get robots, roles, hex objects, replay, variables

#### Phase 2c: Role Assignment & Robot Spawning API *(Medium, ~300-400 lines)*
**Files:** `backend/main.py`, `backend/game_logic.py`
- **New endpoint:** `POST /game/{game_id}/team/{team}/assign_roles`
- **New endpoint:** `POST /game/{game_id}/spawn_robots`
- **New endpoint:** `GET /game/{game_id}/initial_state` (customized per player)
- Add `spawn_robots_for_game()` — creates Robot objects from role assignments
- Add `calculate_spawn_positions()` — team 0 left/bottom, team 1 right/top
- Add `validate_role_assignment()` — checks role combinations are legal

#### Phase 2d: Core Turn Processing Engine *(Complex, ~800-1000 lines)*
**File:** `backend/game_logic.py` — major rewrite of stubs
- `establish_robot_order()` — initiative team first, then team_order, then random tiebreak
- `process_round()` — loop all robots in order for each of 6 rounds
- `process_robot_action()` — 12 collision cases from mechanics doc:
  1. Robot stunned → skip (animation: "Stunned")
  2. Wait + Firewall → destroy firewall, send to spawn, stun
  3. Wait + EMP → stun in place
  4. Wait (normal) → process deploy (animation: "Waiting")
  5. Move to empty → move, process deploy (animation: "Move")
  6. Move to enemy Captain → WIN (animation: "Bump")
  7. Move to same-team robot → fail (animation: "Bump")
  8. Move to weaker enemy → push, move (animation: "Power Move")
  9. Move to stronger enemy → fail (animation: "Bump")
  10. Move to obstacle → error (animation: "Bump")
  11. Move to supply drop → gain energy, move (animation: "Move")
  12. Else → error (animation: "Puzzled")
- `process_deploy_action()` — EMP/Firewall/SupplyDrop/ExtraMoves
- `check_win_condition()` — Captain capture detection

#### Phase 2e: Enhanced Submit & Results Endpoints *(Medium, ~200-300 lines)*
**File:** `backend/main.py`
- Update `POST /game/{game_id}/submit` — validate actions (robot ownership, move counts, energy), accept new `RoundAction` format
- Update `GET /game/{game_id}/results` — return `TurnReplay`, filtered robot list (sight range), hex objects, winner
- Add `validate_player_actions()` function
- Add `filter_robots_by_sight()` function (fog of war)

#### Phase 2f: Map Generation & Comprehensive Tests *(Medium, ~300-400 lines)*
**Files:** `backend/game_logic.py`, `test_api.py`
- Replace stub `generate_default_map()` with realistic generator:
  - Use GameVariables.map_size (small 30x20, medium 40x40, large 60x40)
  - Place obstacles avoiding spawn zones
  - Strategic terrain layout
- Add comprehensive integration tests:
  - Full 2v2 game flow (create → roles → spawn → turns → Captain capture)
  - Full 3v3 game flow
  - Deploy action tests (EMP, Firewall, Supply Drop, Extra Moves)
  - Collision/stun tests
  - Fog of war test

---

## Files to Modify in Phase 2

| File | Phases | Changes |
|------|--------|---------|
| `backend/models.py` | 2a | Add 15+ new Pydantic models |
| `backend/redis_client.py` | 2b | Add 20+ new Redis methods |
| `backend/game_logic.py` | 2c, 2d, 2f | Replace stubs with real game logic |
| `backend/main.py` | 2c, 2e | Add 3 new endpoints, enhance existing |
| `test_api.py` | 2f | Add comprehensive integration tests |

---

## Success Criteria for Phase 2

- [x] All 4 robot types with correct stats
- [x] Role assignment for 2-player and 3-player teams
- [x] 6-round turn processing with all 12 collision cases
- [x] All 4 deploy actions functional
- [x] Stun mechanics (Firewall + EMP)
- [x] Replay data with animation types per round
- [x] Captain capture win condition
- [x] Sight range filtering (fog of war)
- [x] Realistic map generation with obstacles
- [x] Full 2v2 and 3v3 integration tests in `test_full_game.py`
- [x] Old `test_api.py` backward compatibility maintained
- [ ] Deploy to Railway and run integration tests against production

---

## Backward Compatibility Strategy

Old `test_api.py` sends generic `MoveAction` format. New code will:
- Accept both old `moves: List[MoveAction]` and new `actions: List[RoundAction]` formats
- Convert old format to new internally
- Keep old test passing through all phases
- Add new `test_full_game.py` for comprehensive testing

---

## Project Structure

```
/Users/family/Projects/Git/robot_battle/
├── STATUS.md                         # This file
├── CLAUDE.md                         # Project overview for Claude Code
├── README.md                         # Project README
├── api_architecture.md               # Original backend architecture design
├── godot_architecture.md             # Game client architecture (future)
├── robot_game_backend_mechanics.md   # Game rules - turn processing ← KEY REFERENCE
├── robot_game_client_mechanics.md    # Game rules - client gameplay ← KEY REFERENCE
├── test_api.py                       # Integration tests (Phase 1 passing)
├── backend/                          # FastAPI application
│   ├── main.py                       # API endpoints (6 working)
│   ├── models.py                     # Pydantic models (8 basic, expanding in 2a)
│   ├── redis_client.py               # Redis data access (expanding in 2b)
│   ├── auth.py                       # API key authentication
│   ├── game_logic.py                 # Game processing (stub, rewriting in 2d)
│   ├── config.py                     # Configuration
│   ├── requirements.txt
│   ├── Procfile                      # Railway: uvicorn main:app
│   └── runtime.txt                   # Python 3.11.7
└── game_client/                      # Empty (Phase 3: Godot client)
```

---

## Quick Reference

```bash
# Test current deployed API
python test_api.py https://robotbattle-production.up.railway.app

# Check health
curl https://robotbattle-production.up.railway.app/health

# Railway operations (must be in project directory)
railway link          # Link CLI to Railway project
railway logs          # View deployment logs
railway status        # Check service status

# Git operations
git checkout main
git checkout test1
git push origin main  # Triggers Railway auto-deploy
```

---

## Railway Setup Checklist

- [x] Redis service running
- [x] Backend service deployed and reachable
- [x] Backend service linked to GitHub repo `robot_battle`
- [x] Backend service root directory: `/backend`
- [x] `REDIS_URL` environment variable set
- [x] `API_SECRET` environment variable set
- [ ] `ENVIRONMENT` set to `production` (currently shows "development" — typo in Railway dashboard)
- [x] Health endpoint returns `{"status":"healthy","redis":true}`

---

## Phase 3 Preview: Godot Client

After Phase 2 is complete:
- Build Godot 4.x game client following `godot_architecture.md`
- Implement APIClient autoload singleton
- Build UI: main menu, lobby, game view
- Implement hex map rendering
- Add turn submission and polling logic
- Test full multiplayer game
