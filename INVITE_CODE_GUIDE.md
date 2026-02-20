# Dual Invite Code System - Quick Guide

## Visual Flow Comparison

### OLD SYSTEM (Auto-assign by join order)
```
┌─────────────────────────────────────────────────────────┐
│ Creator: POST /game/create                              │
│ Response: { game_id: "game_abc123" }                    │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Creator shares ONE game_id with EVERYONE                │
│ "Join my game: game_abc123"                             │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Players join in random order:                           │
│  - Player2: POST /game/game_abc123/join → Team 0        │
│  - Player3: POST /game/game_abc123/join → Team 0        │
│  - Player4: POST /game/game_abc123/join → Team 1        │
│  - Player5: POST /game/game_abc123/join → Team 1        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
              ❌ NO CONTROL OVER TEAMS
           Friends may end up on opposing teams!
```

### NEW SYSTEM (Explicit team selection)
```
┌─────────────────────────────────────────────────────────┐
│ Creator: POST /game/create                              │
│ Response: {                                             │
│   game_id: "game_abc123"                                │
│   team_0_invite_code: "golden-dragon-castle"            │
│   team_1_invite_code: "swift-tiger-moon"                │
│ }                                                        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Creator shares TWO codes with SPECIFIC groups:          │
│ To teammates: "Join Team 0: golden-dragon-castle"       │
│ To opponents: "Join Team 1: swift-tiger-moon"           │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Players join their assigned team:                       │
│  - Friend1: Uses "golden-dragon-castle" → Team 0        │
│  - Friend2: Uses "golden-dragon-castle" → Team 0        │
│  - Enemy1:  Uses "swift-tiger-moon" → Team 1            │
│  - Enemy2:  Uses "swift-tiger-moon" → Team 1            │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
              ✅ FULL CONTROL OVER TEAMS
         Creator decides exactly who plays together!
```

## Example Invite Codes

The system generates memorable 3-word codes:

```
✨ Team 0 (Your Team):
   - golden-dragon-castle
   - cosmic-phoenix-nexus
   - swift-laser-fortress
   - mystic-wolf-vault

🔥 Team 1 (Opponents):
   - shadow-tiger-moon
   - neon-rocket-tower
   - crystal-falcon-grid
   - thunder-shark-portal
```

## API Endpoint Changes

### Create Game
**Response updated** to include invite codes:

```json
POST /game/create

{
  "game_id": "game_abc123",
  "creator_player_id": "player_xyz",
  "api_key": "key_...",
  "team_0_invite_code": "golden-dragon-castle",  ← NEW
  "team_1_invite_code": "swift-tiger-moon",       ← NEW
  "state": "waiting_for_players",
  "max_players": 4,
  "team": 0
}
```

### Join Game
**Endpoint changed** from game_id to invite code:

```diff
- POST /game/{game_id}/join
+ POST /game/invite/{invite_code}/join

Request body (unchanged):
{
  "player_name": "Alice"
}

Response (team now determined by code):
{
  "game_id": "game_abc123",
  "player_id": "player_new",
  "api_key": "key_...",
  "map": {...},
  "current_players": 2,
  "max_players": 4,
  "state": "waiting_for_players",
  "team": 0  ← Assigned based on which code was used
}
```

## Frontend UI Changes

### Main Menu (Before)
```
┌─────────────────────────────────┐
│ [Player Name Input]              │
│ [Create Game]                    │
│ ─────────────────────────────   │
│ [Game ID Input]                  │
│ [Join Game]                      │
│                                  │
│ Game ID: game_abc123             │
│ [Copy Game ID]                   │
└─────────────────────────────────┘
```

### Main Menu (After)
```
┌─────────────────────────────────┐
│ [Player Name Input]              │
│ [Create Game]                    │
│ ─────────────────────────────   │
│ [Invite Code Input]              │
│ [Join Game]                      │
│                                  │
│ Team 0 Code (Your Team):         │
│ golden-dragon-castle             │
│ [Copy Team 0 Code]               │
│                                  │
│ Team 1 Code (Opponents):         │
│ swift-tiger-moon                 │
│ [Copy Team 1 Code]               │
└─────────────────────────────────┘
```

## User Experience

### Creator Workflow
1. Click "Create Game"
2. See TWO codes appear
3. Copy "Team 0 Code" and send to friends
4. Copy "Team 1 Code" and send to opponents
5. Wait for players to join

### Joiner Workflow
1. Receive invite code from friend (e.g., "golden-dragon-castle")
2. Paste code into "Invite Code" field
3. Click "Join Game"
4. Automatically assigned to correct team
5. See "Joined game as Team 0" confirmation

## Error Messages

| Situation | Error Message |
|-----------|---------------|
| Invalid code | HTTP 404: "Invalid or expired invite code" |
| Wrong team code | Works fine! Code determines team automatically |
| Team already full | HTTP 409: "Team 0 is full" |
| Game started | HTTP 409: "Game is not accepting new players" |
| Empty code | Frontend: "Please enter an invite code" |

## Code Format Rules

✅ **Valid Examples:**
- `golden-dragon-castle` (all lowercase, 3 words, hyphens)
- `swift-tiger-moon`
- `crystal-falcon-grid`

❌ **Invalid Examples:**
- `GoldenDragonCastle` (not lowercase)
- `golden_dragon_castle` (underscores instead of hyphens)
- `golden-dragon` (only 2 words)
- `game_abc123` (not word-based)

## Testing Examples

### cURL Testing
```bash
# 1. Create game
curl -X POST http://localhost:8000/game/create \
  -H "Content-Type: application/json" \
  -d '{"max_players": 4, "map_config": {"width": 15, "height": 15}, "game_variables": {"team_size": 2}}'

# Response shows:
# "team_0_invite_code": "golden-dragon-castle"
# "team_1_invite_code": "swift-tiger-moon"

# 2. Join team 0
curl -X POST http://localhost:8000/game/invite/golden-dragon-castle/join \
  -H "Content-Type: application/json" \
  -d '{"player_name": "Alice"}'

# 3. Join team 1
curl -X POST http://localhost:8000/game/invite/swift-tiger-moon/join \
  -H "Content-Type: application/json" \
  -d '{"player_name": "Bob"}'
```

### Python Testing
```python
import requests

# Create game
resp = requests.post("http://localhost:8000/game/create", json={
    "max_players": 4,
    "map_config": {"width": 15, "height": 15},
    "game_variables": {"team_size": 2}
})
game = resp.json()
team_0_code = game["team_0_invite_code"]
team_1_code = game["team_1_invite_code"]

# Join team 0
resp = requests.post(f"http://localhost:8000/game/invite/{team_0_code}/join",
                     json={"player_name": "Alice"})
print(f"Alice joined as Team {resp.json()['team']}")  # Should be 0

# Join team 1
resp = requests.post(f"http://localhost:8000/game/invite/{team_1_code}/join",
                     json={"player_name": "Bob"})
print(f"Bob joined as Team {resp.json()['team']}")  # Should be 1
```

## Benefits

✅ **Creator Control**: Decide exactly who plays on which team
✅ **User-Friendly**: Memorable word-based codes (not random UUIDs)
✅ **Shareable**: Easy to communicate verbally or via text
✅ **Secure**: ~81,000 unique combinations, auto-expire with game
✅ **Clear Intent**: Code name indicates which team you're joining

## Migration Notes

⚠️ **Breaking Change**: Old clients using `/game/{game_id}/join` will fail
⚠️ **No Backward Compatibility**: All clients must update
⚠️ **Deployment**: Backend and frontend must be deployed together

## Word Lists

The system uses curated word lists for code generation:

- **Adjectives (47)**: ancient, brave, cosmic, electric, golden, mystic, shadow, swift, etc.
- **Nouns (46)**: apex, dragon, eagle, falcon, hunter, phoenix, robot, tiger, wolf, etc.
- **Objects (39)**: castle, citadel, fortress, galaxy, grid, nexus, portal, tower, vault, etc.

Total combinations: 47 × 46 × 39 = **84,318 unique codes**
