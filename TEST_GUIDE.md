# Test Guide — Robot Battle

## Overview

There are two integration test scripts at the repo root. Both test against a live HTTP API (local or deployed). Neither requires a running Godot client.

| Script | Phase | Suites | Checks |
|--------|-------|--------|--------|
| `test_api.py` | Phase 1 (basic flow) | 1 | 14 |
| `test_full_game.py` | Phase 2 (full mechanics) | 6 | ~30 |

---

## 1. What Tests Have Been Written

### `test_api.py` — Phase 1 Integration Tests

A single end-to-end test suite (`run_full_game_flow`) that validates the original 2v2 game flow using the legacy move format.

| Test Function | What It Tests |
|---------------|---------------|
| `test_health_check` | `GET /health` returns 200 and reports Redis connected |
| `test_create_game` | `POST /game/create` returns `game_id`, `player_id`, `api_key` |
| `test_join_game` | `POST /game/{id}/join` for 3 additional players; game reaches `in_progress` |
| `test_game_status` | `GET /game/{id}/status` returns `state: "in_progress"` |
| `test_submit_moves` | `POST /game/{id}/submit` with legacy `moves: [MoveAction]` format (all 4 players submit) |
| `test_poll_results` | `GET /game/{id}/results` with retry loop until `ready: true` |
| *(result checks)* | Verifies turn increments to 2, result data is present |

---

### `test_full_game.py` — Phase 2 Integration Tests

Six test suites exercising Phase 2 game mechanics: roles, robot types, deploy actions, win conditions, and replay data.

#### Suite 1: `test_2v2_game_flow`
Full 4-player game from creation to first turn replay.

- Creates a 2v2 game with `game_variables`
- Joins 3 additional players
- Assigns roles for both teams (captain+huntsman each)
- Calls `spawn_robots` → verifies robots exist in `initial_state`
- Verifies player robot counts (5 per team × 2 = 10 total)
- All 4 players submit wait actions for all 6 rounds
- Polls results until `ready: true`
- Verifies replay has exactly 6 rounds
- Verifies no winner yet

#### Suite 2: `test_captain_capture_win`
Tests win condition detection when an enemy Captain is captured.

- Creates a 2v2 game, spawns robots
- Finds a Scout (high movement) on one team and the enemy Captain position
- Submits moves routing the Scout toward the Captain
- Polls results and checks `winner` field is set in `TurnReplay`

#### Suite 3: `test_3v3_game_flow`
Full 6-player game with the 3-person team role set.

- Creates a 3v3 game
- Joins 5 additional players
- Assigns captain+huntsman+engineer roles for both teams
- Spawns robots → verifies 28 total robots (14 per team)
- All 6 players submit wait actions
- Verifies 6-round replay structure

#### Suite 4: `test_deploy_actions`
Tests the EMP deploy action and hex object creation.

- Creates a 2v2 game, spawns robots
- Finds a Captain robot (which can deploy)
- Submits a `deploy` action of type `emp` with a valid target hex
- Polls results and verifies `hex_objects_created` contains an EMP entry

#### Suite 5: `test_role_validation`
Tests server-side validation of role assignments.

- Rejects an invalid role name (e.g. `"wizard"`) with HTTP 400
- Rejects a duplicate role (two Captains on one team) with HTTP 400
- Accepts a valid captain+huntsman assignment with HTTP 200

#### Suite 6: `test_backward_compatibility`
Verifies old clients still work after Phase 2 changes.

- Creates a game without a `game_variables` field (legacy format)
- Verifies the game is created successfully
- Verifies the game auto-starts when full (no role assignment step needed)

---

## 2. How to Run the Tests

### Prerequisites

```bash
pip install requests
```

Both scripts take an optional base URL argument. If omitted, they default to `http://localhost:8000`.

### Run Against Local Backend

Start the backend locally first:

```bash
cd backend
uvicorn main:app --reload
```

Then in a separate terminal:

```bash
python test_api.py
python test_full_game.py
```

### Run Against Deployed API (Railway)

```bash
python test_api.py https://robotbattle-production.up.railway.app
python test_full_game.py https://robotbattle-production.up.railway.app
```

### Exit Codes

Both scripts exit with code `0` if all tests pass, `1` if any test fails. This allows use in CI pipelines:

```bash
python test_full_game.py https://robotbattle-production.up.railway.app && echo "All tests passed"
```

---

## 3. How to Review Results

### Terminal Output Format

Both scripts use ANSI color codes for easy scanning:

| Color | Meaning |
|-------|---------|
| **Green** `✓` | Check passed |
| **Red** `✗` | Check failed (with failure detail) |
| **Cyan** | Section/suite header |
| **Yellow** | Informational message (e.g. polling status) |

### `test_api.py` Output Structure

```
=== Phase 1 Integration Tests ===

--- Health Check ---
  ✓ Health check passed
  ✓ Redis is connected

--- Create Game ---
  ✓ Game created: abc123
  ✓ Got player_id and api_key

... (more checks) ...

=== Results: 14/14 passed ===
```

### `test_full_game.py` Output Structure

Each suite prints its own section header and per-check results, followed by a summary table:

```
=== Phase 2 Integration Tests ===

--- 2v2 Game Flow ---
  ✓ Game created
  ✓ All players joined
  ✓ Roles assigned (team 0)
  ✓ Roles assigned (team 1)
  ✓ Robots spawned
  ✓ Initial state received (10 robots)
  ✓ All players submitted
  ✓ Results ready
  ✓ Replay has 6 rounds
  ✓ No winner yet

... (remaining suites) ...

=== Test Summary ===
  2v2 Game Flow          PASS  (10/10)
  Captain Capture Win    PASS  ( 3/3)
  3v3 Game Flow          PASS  ( 8/8)
  Deploy Actions         PASS  ( 4/4)
  Role Validation        PASS  ( 3/3)
  Backward Compat        PASS  ( 2/2)

  Total: 30/30 passed
```

### What to Do When a Test Fails

- **Red `✗` with a message** — The message shows what was expected vs. received. Check the API response body for details.
- **Suite marked FAIL** — Only that suite failed; others may still pass. Scroll up to find the first red line in that suite.
- **Network/connection errors** — Printed in red with the exception message. Verify the API URL and that the backend is running.
- **Polling timeout** — If `test_poll_results` or result polling retries exhaust without `ready: true`, the turn processing background task may have crashed. Check backend logs.

### Checking Backend Logs (Railway)

```bash
railway logs
```

Or view in the Railway dashboard under the deployment's log tab.
