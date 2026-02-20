# Dual Invite Code System - Implementation Summary

## Overview

Successfully implemented a dual invite code system to replace the old game_id-based joining. The creator now receives **two invite codes** (one for each team) instead of a single game ID, allowing full control over team composition.

## What Changed

### Backend Changes

#### 1. **New File: `backend/invite_codes.py`**
- Word list generator with ~47 adjectives, ~46 nouns, and ~39 objects
- Format: `adjective-noun-object` (e.g., `golden-dragon-castle`)
- Collision detection with Redis
- ~81,000 possible unique combinations

#### 2. **Updated: `backend/models.py`**
- **CreateGameResponse**: Added `team_0_invite_code` and `team_1_invite_code` fields
- **New model**: `InviteCodeJoinRequest` with `player_name` field
- **JoinGameResponse**: Updated comment to reflect team assignment by invite code

#### 3. **Updated: `backend/redis_client.py`**
- **New methods**:
  - `store_invite_code(code, game_id, team, ttl)`: Store code → game mapping
  - `get_invite_code_info(code)`: Lookup game_id and team from code
  - `delete_invite_code(code)`: Remove expired codes
  - `get_team_player_count(game_id, team)`: Count players on specific team

#### 4. **Updated: `backend/main.py`**
- **POST /game/create**: Now generates and returns two invite codes
- **NEW POST /game/invite/{invite_code}/join**: Join via invite code
- **REMOVED POST /game/{game_id}/join**: Old join endpoint deleted
- Added `InviteCodeJoinRequest` to imports

### Frontend Changes

#### 5. **Updated: `game_client/scenes/main_menu.gd`**
- Replaced single game ID input with invite code input
- Added UI for displaying both team codes after creation
- Added two copy buttons (one per team code)
- Updated join handler to use invite codes
- Updated `_on_game_created` to display both codes

#### 6. **Updated: `game_client/scenes/main_menu.tscn`**
- Replaced `GameIDInput` with `InviteCodeInput`
- Replaced `GameIDDisplay` and `CopyGameIDBtn` with:
  - `Team0CodeLabel`, `Team0CodeDisplay`, `CopyTeam0Btn`
  - `Team1CodeLabel`, `Team1CodeDisplay`, `CopyTeam1Btn`

#### 7. **Updated: `game_client/scripts/api_client.gd`**
- Replaced `join_game(game_id, player_name)` with:
- `join_game_by_code(invite_code, player_name)`

#### 8. **Updated: `game_client/scripts/game_state.gd`**
- Added `team_0_invite_code` and `team_1_invite_code` storage
- Updated `initialize_from_create_response` to store codes
- Updated `save_state()` and `load_saved_state()` to persist codes

### Test Changes

#### 9. **Updated: `test_api.py`**
- Added `team_0_code` and `team_1_code` fields to APITester
- Updated `test_create_game()` to extract and log invite codes
- Updated `test_join_game()` to accept invite_code parameter
- Updated join calls: Player 2&4 use team_0_code, Player 3 uses team_1_code

#### 10. **Updated: `test_full_game.py`**
- Replaced `join_game(game_id, name)` with `join_game_by_code(code, name)`
- Updated all 7 test functions to:
  1. Extract invite codes from create response
  2. Join players with appropriate team codes
  3. Ensure correct team distribution (2v2: 2+2, 3v3: 3+3)

## How It Works

### Old Flow (Removed)
```
Creator: POST /game/create → get game_id
Creator: share game_id with everyone
Player: POST /game/{game_id}/join → auto-assigned by join order
```

### New Flow
```
Creator: POST /game/create → get team_0_code + team_1_code
Creator: share team_0_code with teammates
Creator: share team_1_code with opponents
Player: POST /game/invite/{code}/join → assigned to code's team
```

## Team Assignment Logic

### Backend (main.py: join_game_by_invite_code)
1. Lookup invite code in Redis → get `game_id` and `assigned_team`
2. Verify game exists and is accepting players
3. Check if that specific team has space (max = max_players / 2)
4. Assign player to the team encoded in the invite code
5. Auto-transition to `in_progress` when all slots filled

### Test Distribution Examples

**2v2 Game (4 players):**
- Team 0: Creator (code used: team_0), Player 2 (code: team_0)
- Team 1: Player 3 (code: team_1), Player 4 (code: team_1)

**3v3 Game (6 players):**
- Team 0: Creator (team_0), Player 2 (team_0), Player 4 (team_0)
- Team 1: Player 3 (team_1), Player 5 (team_1), Player 6 (team_1)

## Error Handling

### Backend Validations
- **Invalid code**: HTTP 404 "Invalid or expired invite code"
- **Game not found**: HTTP 404 "Game not found"
- **Game not accepting players**: HTTP 409 "Game is not accepting new players"
- **Team full**: HTTP 409 "Team {X} is full"

### Frontend Validations
- Empty invite code: "Please enter an invite code"
- Network errors: Display backend error message
- Team full: Show error from backend

## Backward Compatibility

**NONE** - This is a breaking change:
- Old `/game/{game_id}/join` endpoint completely removed
- All clients must use new `/game/invite/{code}/join` endpoint
- Old game IDs cannot be used for joining

## Redis Data Model

### New Keys
```
invite_code:{code} → JSON: {"game_id": "game_abc123", "team": 0}
  TTL: Same as game TTL (Config.TTL_ACTIVE_GAME)
```

## Files Modified

| File | Lines Changed | Type |
|------|---------------|------|
| `backend/invite_codes.py` | +85 | NEW |
| `backend/models.py` | +5 | Modified |
| `backend/redis_client.py` | +33 | Modified |
| `backend/main.py` | +59, -73 | Modified |
| `game_client/scenes/main_menu.gd` | +35, -20 | Modified |
| `game_client/scenes/main_menu.tscn` | +30, -10 | Modified |
| `game_client/scripts/api_client.gd` | +3, -3 | Modified |
| `game_client/scripts/game_state.gd` | +7 | Modified |
| `test_api.py` | +15, -5 | Modified |
| `test_full_game.py` | +90, -20 | Modified |

## Testing

### Manual Testing Steps

1. **Start local backend**:
   ```bash
   cd backend
   uvicorn main:app --reload
   ```

2. **Test API with curl**:
   ```bash
   # Create game
   curl -X POST http://localhost:8000/game/create \
     -H "Content-Type: application/json" \
     -d '{"max_players": 4, "map_config": {"width": 15, "height": 15}, "game_variables": {"team_size": 2}}'

   # Extract codes from response, then:

   # Join team 0
   curl -X POST http://localhost:8000/game/invite/{team_0_code}/join \
     -H "Content-Type: application/json" \
     -d '{"player_name": "Bob"}'

   # Join team 1
   curl -X POST http://localhost:8000/game/invite/{team_1_code}/join \
     -H "Content-Type: application/json" \
     -d '{"player_name": "Charlie"}'
   ```

3. **Run integration tests**:
   ```bash
   python test_api.py http://localhost:8000
   python test_full_game.py http://localhost:8000
   ```

4. **Test Godot client**:
   - Run 4 Godot instances
   - Instance 1: Create game → see both codes
   - Instance 2: Paste team 0 code → join → verify Team 0
   - Instance 3: Paste team 1 code → join → verify Team 1
   - Instance 4: Paste team 0 code → join → verify Team 0

### Deploy to Railway

```bash
git add -A
git commit -m "Implement dual invite code system"
git push origin main
```

Then test against production:
```bash
python test_api.py https://robotbattle-production.up.railway.app
python test_full_game.py https://robotbattle-production.up.railway.app
```

## Next Steps

1. Test locally with all integration tests
2. Test with multiple Godot client instances
3. Deploy to Railway
4. Run production tests
5. Update MEMORY.md with new system details

## Notes

- Invite codes are human-readable and easy to share verbally
- Codes are stored with same TTL as games (auto-expire)
- No migration needed (breaking change - old clients incompatible)
- Creator always joins team 0 automatically
- Each code can only be used to join its assigned team
