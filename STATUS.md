# Project Status — Robot Battle

**Last Updated:** 2026-02-19
**Current Phase:** Phase 3 Complete — All three phases implemented

---

## Summary

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | FastAPI backend + Redis + Railway deployment | ✅ Complete, deployed, tested |
| Phase 2 | Full game mechanics (robots, roles, turns, replay) | ✅ Complete, deployed, tested |
| Phase 3 | Godot 4.x game client | ✅ Complete (needs in-engine test) |

---

## Deployment

- **Backend URL:** https://robotbattle-production.up.railway.app
- **Railway Project:** `marvelous-wholeness` (ID: `773c40ec-eaec-4331-873b-4972b42dbe9d`)
- **Redis:** `redis.railway.internal:6379` (internal to Railway network)
- **Auto-deploy:** Pushing to `main` branch triggers immediate Railway redeploy
- **Health check:** `GET /health` returns `{"status":"healthy","redis":true}`

**Environment variables set in Railway:**
- `REDIS_URL` — set
- `API_SECRET` — set
- `ENVIRONMENT` — shows "development" (harmless typo in Railway dashboard; does not affect behavior)

---

## Git

- **Branch:** `main`
- **Latest commits:**
  ```
  cf0655a  Update api_architecture.md to match Phase 2 implementation
  61b2158  Update godot_architecture.md to match Phase 3 implementation
  e3847c3  Implement Phase 3: Godot 4.x game client
  aea6fe5  Fix test helper: use 'is not None' check for HTTP error responses
  807707b  Implement Phase 2: Full robot battle game mechanics
  ed4f1e3  Fix player counting bug in game creation
  ```

---

## Phase 1: Backend ✅

FastAPI + Redis backend with 9 API endpoints, deployed to Railway.

**Endpoints:**
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Redis health check |
| POST | `/game/create` | Create game, get `game_id` + `api_key` |
| POST | `/game/{id}/join` | Join game, get `player_id` |
| GET | `/game/{id}/status` | Poll game state |
| POST | `/game/{id}/team/{t}/assign_roles` | Assign player→role for a team |
| POST | `/game/{id}/spawn_robots` | Spawn robots from assigned roles |
| GET | `/game/{id}/initial_state` | Get map + starting robot positions |
| POST | `/game/{id}/submit` | Submit 6-round action plan |
| GET | `/game/{id}/results` | Poll for turn replay data |

**Backend files:** `backend/main.py`, `backend/models.py`, `backend/redis_client.py`, `backend/game_logic.py`, `backend/auth.py`, `backend/config.py`

---

## Phase 2: Game Mechanics ✅

Full game logic engine. All Phase 2 success criteria met and deployed.

**Implemented:**
- 4 robot types: Captain (str 7, 3 moves), Scout (str 3, 4 moves), Defender (str 5, 2 moves), Engineer (str 0, 6 moves)
- Role system: 2-person teams (Captain+Huntsman), 3-person teams (Captain+Huntsman+Engineer)
- Robot counts per role (e.g. Captain role = 1 Captain + 2 Defenders + 2 Engineers for 2-person teams)
- 6-round simultaneous turn processing with initiative ordering
- 12 collision cases (stun, push, capture, destroy firewall, etc.)
- 4 deploy action types: EMP (stun area), Firewall (zone denial), Supply Drop (energy), Extra Moves (self buff)
- Captain capture win condition
- Fog of war: sight range filtering per robot type
- Realistic map generation with obstacles and spawn zones
- Full `TurnReplay` replay data with per-robot `animation_type` per round
- Backward compatibility: old `moves: List[MoveAction]` format still accepted

**Robot type stats:**

| Type | Strength | Moves | Max Energy | Deploy | Sight |
|------|----------|-------|------------|--------|-------|
| Captain | 7 | 3 | 2 | EMP | 5 |
| Scout | 3 | 4 | 6 | Extra Moves | 6 |
| Defender | 5 | 2 | 3 | Firewall | 4 |
| Engineer | 0 | 6 | 3 | Supply Drop | 3 |

---

## Phase 3: Godot 4.x Client ✅ (code written, not yet run in engine)

Complete Godot 4.x game client in `game_client/`. Functional prototype — colored shapes, no art assets.

**Files:**
```
game_client/
├── project.godot               # 4 autoloads, 1280×720, Compatibility renderer
├── icon.svg
├── scripts/
│   ├── hex_math.gd             # Autoload: flat-top axial math (HEX_SIZE=48)
│   ├── api_client.gd           # Autoload: all HTTP; signal-based async
│   ├── game_state.gd           # Autoload: single source of truth for all game data
│   └── turn_input.gd           # Autoload: 6-round action planning state machine
├── scripts/ (also)
│   ├── hex_map.gd              # Node2D: renders hex grid, fog of war, click input
│   └── robot_sprite.gd         # Node2D: per-robot visual + tween animations
└── scenes/
    ├── main_menu.tscn/.gd      # Enter name, create/join game, wait for players
    ├── role_assignment.tscn/.gd # Each player picks their own role; any player spawns
    ├── game_view.tscn/.gd      # Main gameplay: input phase + replay playback
    └── game_end.tscn/.gd       # Win screen, return to menu
```

**Autoloads registered in project.godot:**
```
HexMath    → res://scripts/hex_math.gd
APIClient  → res://scripts/api_client.gd
GameState  → res://scripts/game_state.gd
TurnInput  → res://scripts/turn_input.gd
```

**Game client flow:**
1. `MainMenu` — player enters name, creates or joins a game; polls `/status` until full → `RoleAssignment`
2. `RoleAssignment` — each player selects their own role; polls `/initial_state` until robots exist → `GameView`
3. `GameView` — alternates input phase (action planning) and review phase (replay animation) until winner
4. `GameEnd` — shows winner, return to menu

**Visual design (prototype):**
- Team 0 = blue shades, Team 1 = red shades
- Captain = large circle, Scout = small circle, Defender = square, Engineer = diamond
- Terrain: plains (green), forest (dark green), mountain (brown), water (blue), spawn (tan)
- Hex objects: EMP (purple ⚡), Firewall (orange 🔥), Supply Drop (green 📦)
- Fog of war: hexes outside player robot sight range are dimmed

**Known status:** GDScript code written and committed. Has not yet been opened and tested in the Godot editor. Likely needs minor fixes when first run (node path issues, type errors, etc.).

---

## Testing

| Script | Coverage | How to Run |
|--------|----------|------------|
| `test_api.py` | Phase 1 flow (14 checks) | `python test_api.py [URL]` |
| `test_full_game.py` | Phase 2 mechanics (6 suites, ~30 checks) | `python test_full_game.py [URL]` |

Default URL is `http://localhost:8000`. Pass the Railway URL to test production.

Last verified: both scripts **all passing** against deployed Railway backend.

See `TEST_GUIDE.md` for full test documentation.

---

## Documentation

| File | Contents |
|------|----------|
| `CLAUDE.md` | Project overview for Claude Code |
| `api_architecture.md` | Backend: all endpoints, Redis keys, data models, auth, turn processing |
| `godot_architecture.md` | Client: all scripts, scene flow, action format, replay, persistence |
| `robot_game_backend_mechanics.md` | Game rules: 12 collision cases, turn order, deploy actions |
| `robot_game_client_mechanics.md` | Game rules: robot types, roles, deploy action details |
| `TEST_GUIDE.md` | Test descriptions, how to run, how to read output |

---

## Project Structure

```
robot_battle/
├── STATUS.md                         # This file
├── CLAUDE.md                         # Project overview
├── TEST_GUIDE.md                     # Test documentation
├── api_architecture.md               # Backend architecture (accurate, updated 2026-02-19)
├── godot_architecture.md             # Client architecture (accurate, updated 2026-02-19)
├── robot_game_backend_mechanics.md   # Game rules reference
├── robot_game_client_mechanics.md    # Client gameplay reference
├── test_api.py                       # Phase 1 integration tests
├── test_full_game.py                 # Phase 2 integration tests
├── backend/                          # FastAPI application (deployed to Railway)
│   ├── main.py
│   ├── models.py
│   ├── redis_client.py
│   ├── game_logic.py
│   ├── auth.py
│   ├── config.py
│   ├── requirements.txt
│   ├── Procfile
│   └── runtime.txt
└── game_client/                      # Godot 4.x game client (Phase 3)
    ├── project.godot
    ├── icon.svg
    ├── scripts/
    │   ├── hex_math.gd
    │   ├── api_client.gd
    │   ├── game_state.gd
    │   ├── turn_input.gd
    │   ├── hex_map.gd
    │   └── robot_sprite.gd
    └── scenes/
        ├── main_menu.tscn + main_menu.gd
        ├── role_assignment.tscn + role_assignment.gd
        ├── game_view.tscn + game_view.gd
        └── game_end.tscn + game_end.gd
```

---

## Quick Reference

```bash
# Run integration tests against production
python test_api.py https://robotbattle-production.up.railway.app
python test_full_game.py https://robotbattle-production.up.railway.app

# Check API health
curl https://robotbattle-production.up.railway.app/health

# View Railway deployment logs
railway logs

# Deploy: just push to main
git push origin main
```

---

## Next Steps

1. **Open `game_client/` in Godot 4.x editor** — first run will surface any GDScript errors
2. **Fix any editor errors** — likely minor: node path mismatches, type annotation issues
3. **End-to-end test** — run two Godot instances on the same machine against the Railway backend
4. **Multi-device test** — test on separate machines to validate multiplayer flow
