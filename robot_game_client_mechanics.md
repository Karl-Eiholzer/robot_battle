# Description of Robot Game Client Mechanics

Describes game set-up and how turns are input by the Godot game client

**Related Documentation:**
- [INVITE_CODE_GUIDE.md](./INVITE_CODE_GUIDE.md) - Visual guide for invite code system
- [robot_game_backend_mechanics.md](./robot_game_backend_mechanics.md) - Backend game mechanics

## Overview

Each player has a robot that is "Captain" and multiple other robots. Your team wins if one of your robots legally moves into the hex occupied by the other team's "Captain", which is called "Capture".

Players are trying to keep their Captain from being captured while simultaneously trying to capture the opponent's Captain.

### Full game steps

1. **Game Creation:** One player initiates the game and receives **two invite codes** (one for each team). This player sets game variables. See **Game Variables** below
2. **Team Formation:** The creator shares the **Team 0 code** with intended teammates and the **Team 1 code** with opponents. Players join by entering their invite code, which automatically assigns them to the correct team.
3. **Role Assignment:** Once all players have joined (4 for 2v2, or 6 for 3v3), each team assigns player roles. See **Player Roles** below.
4. **Robot Spawning:** After both teams have assigned roles, robots are spawned and players download the initial map state.
5. **Gameplay:** Game proceeds in a series of "turns" where all players enter their moves for that "turn" simultaneously and all players get the results back at the same time. Each turn consists of 6 rounds - see **Player options within a turn** below
6. **Win Condition:** Turns continue until the win condition is met for one team. When the win condition is met, backend processing stops and a final replay and score are sent to the players. See **Single turn steps** below

### Single turn steps

Teams alternate having the "Initiative".

1. **Action Entry** Using Godot game client, all players enter the actions they want each robots to take before time runs out. Actions are entered one round at a time up to six rounds.
2. **Action Review** Player can step forward and backward through the 6 rounds of actions to confirm all the actions
3. **Submit and Transmit** Players click on "Submit Moves" button and the Godot game client sends the actions to the backend processor via API
4. **Wait for Results** Upon receipt of moves from all players, the backend processor combines the moves together, generates results, and makes results available for players to download.
5. **Replay** Godot game client shows a replay of what happened during the turn, including the actions of any Robots controlled by other players that are in sight. Player


### Player options within a turn

* Each "Turn" consists of 6 "Rounds"
* In each "round" a Robot can either (a) "move" - move to an adjacent hex or (b) "wait" - stay in the same hex without moving
* In addition to any "move" or "wait" action, Robots can choose the "Deploy" action
* After entering actions for all Robots for a round, the player can then enter actions for the next round
* if the Robot begins the Turn in a "Stunned" state, it will have "move" actions reduced to zero
* Turn data for the Robots are initiated with the assumption that all Robots will execute 6 consecutive "wait" actions and not take any "deploy" actions
* as the players input their actions, the initial data is overwritten - starting with the first round, moving to the second, etc...
* Robots have different numbers of "move" actions that Robot can make each turn, depending on the type of robot.  See **Robot Types** below.
* Robots are not required to use all "move" actions.
* Robots can combine "move" and "wait" actions in any order in the 6 rounds
* Player cannot enter a "move" action that would cause them to move into a hex occupied by another Robot or "obstructed"
* Some hexes on the map have have terrain or obstructions such that the robot cannot legally move into that
* What happens when the Robot uses the "Deploy" action depends on the type of robot.  See **Robot Types** below.
* Each "deploy" action costs the Robot one "Energy Point"
* A "deploy" action cannot happen if the Robot has zero energy points
* If no actions are entered prior to the time running out, the Robot perform 6 consecutive "wait" actions and 0 "deploy" actions
* While inputting actions for each Robot, the player cannot see the actions being input by the other Players
* While inputting actions for each Robot, the player can see the positions of all Robots

### Player Timeout

Two timers are operating:
1. Timer 1: time elapsed since result data was generated (counts forward from timestamp received from back-end - same for all players)
2. Timer 2: time elapsed since player started input of actions (counts forward from timestamp when Godot loaded screen to input actions - slightly different for each player)

Three different variables are used for calculations, as set at the beginning of the game: **Input Time**, **Review Time**, and **Buffer Time**

Initial time runs out if either condition is true:
1. Timer 1 is greater than **Input Time** plus **Review Time**
2. Timer 2 is greater than **Input Time**

While player is inputting actions Timer 2 displays on the screen. When initial time runs out the screen changes to new countdown timer (Timer 3) in bright red set to **Buffer Time**

When Timer 3 elapses, the game auto-submits the set of actions for the player. Note that actions default to "wait" action if no other action was written over that action.


## **Invite Code System**

### How Invite Codes Work

When a game is created, the backend generates two unique 3-word codes:
- **Format:** `adjective-noun-object` (e.g., `golden-dragon-castle`)
- **Team 0 Code:** Determines Team 0 membership
- **Team 1 Code:** Determines Team 1 membership

**Key Features:**
- Memorable and easy to share verbally or via text
- ~84,000 possible unique combinations
- Auto-expire when the game ends
- Cannot be reused across different games

**Team Control:**
The creator controls who plays on which team by deciding who gets which code:
- Share Team 0 code only with intended teammates
- Share Team 1 code only with intended opponents
- No risk of friends accidentally ending up on opposing teams

### Example Flow

**Creator (Alice):**
1. Creates game → receives codes:
   - Team 0: `swift-laser-fortress`
   - Team 1: `shadow-tiger-moon`
2. Texts Bob: "Join Team 0: swift-laser-fortress"
3. Tells Carol: "Join Team 1: shadow-tiger-moon"

**Bob (Teammate):**
1. Enters name: "Bob"
2. Pastes: `swift-laser-fortress`
3. Joins as Team 0 ✓

**Carol (Opponent):**
1. Enters name: "Carol"
2. Pastes: `shadow-tiger-moon`
3. Joins as Team 1 ✓

## **Game Start**

### Joining a Game

**Creating a Game:**
1. Player enters their name in the main menu
2. Selects team size (2v2 or 3v3) and other game variables
3. Clicks "Create New Game"
4. Receives two invite codes displayed on screen:
   - **Team 0 Code** (green) - for their teammates
   - **Team 1 Code** (red) - for opponents
5. Can copy each code separately to share via chat/voice

**Joining a Game:**
1. Player enters their name in the main menu
2. Pastes the invite code they received from the creator
3. Clicks "Join Game"
4. Automatically assigned to Team 0 or Team 1 based on which code was used
5. Waits for all player slots to fill (2 per team for 2v2, 3 per team for 3v3)

### Role Assignment Phase

Once all players have joined:
1. Game transitions from `waiting_for_players` to `in_progress` state
2. Each team sees the role assignment screen
3. **Each player assigns their own role** by selecting from available options:
   - 2v2 teams: Captain or Huntsman
   - 3v3 teams: Captain, Huntsman, or Engineer
4. Backend validates that each team has exactly one of each required role
5. Any player on a team can click "Spawn Robots" once both teams have assigned all roles

### Initial State Download

After robots are spawned:
1. Each player downloads the initial game state via `GET /game/{game_id}/initial_state`
2. Includes:
   - Player's own robots (full data: type, position, energy)
   - Visible enemy robots (limited by fog of war based on sight range)
   - Map terrain and hex objects
   - Which team has initiative for turn 0
3. Game view loads with all robots on the hex map

## **Robot Types**

### **Captain**
* Moves actions per turn: 3
* Starting number of energy points: set by variable
* Maximum Energy: 2
* Type of Deployment Action: **EMP**
* Sight Range: 5 hexes
* Team Order: 1

### **Scout**
* Moves actions per turn: 4
* Starting number of energy points: set by variable
* Maximum Energy: 6
* Type of Deployment Action: **Extra Moves**
* Sight Range: 7 hexes
* Team Order: 3

### **Defender**
* Moves actions per turn: 2
* Starting number of energy points: set by variable
* Maximum Energy: 3
* Type of Deployment Action: **Firewall**
* Sight Range: 3 hexes
* Team Order: 3

### **Engineer**
* Moves actions per turn: 6
* Starting number of energy points: set by variable
* Maximum Energy: 3
* Type of Deployment Action: **Supply Drop**
* Sight Range: 5 hexes
* Team Order: 0


## **Player Roles**

The types and numbers of Robots available to the Player depends on their role

### Roles in Two-Person Teams
Only one of each type is allowed.

1. **Captain** has the following Robot types and counts
* 1 Captain Type
* 0 Scout Type
* 2 Defender Type
* 2 Engineer Type

2. **Huntsman**
* 0 Captain Type
* 4 Scout Type
* 0 Defender Type
* 1 Engineer Type

### Roles in Three-Person Teams
Only one of each type is allowed.

1. **Captain** has the following Robot types and counts
* 1 Captain Type
* 0 Scout Type
* 3 Defender Type
* 0 Engineer Type

2. **Huntsman**
* 0 Captain Type
* 5 Scout Type
* 0 Defender Type
* 0 Engineer Type

3. **Engineer**
* 0 Captain Type
* 0 Scout Type
* 0 Defender Type
* 5 Engineer Type

## **Deploy Actions**

Action required by player when using the "deploy" action

### **EMP**
1. User selects a hex between 4 and 6 hexes away from the Robot in a straight line (based on where the Robot is at the beginning of the "round")
2. Create list containing coordinates of (a) target hex and (b) all hexes within 3 hexes of target hex
3. Show location of EMP target hexes to user using EMP tokens
4. List of EMP hexes sent to backend processing API as part of "turn" submission
5. Effects handled by backend processing

### **Extra Moves**
1. Activate.
2. Effect handles immediately by Godot game client: makes 2 additional move actions available for Robot to use that turn

### **Firewall**
1. User selects a target hex 4 hexes away from the Robot in a straight line (based on where the Robot is at the beginning of the "round")
2. Calculate coordinates of target hex as well as the hexes in the line between the Robot hex and the target hex and add them to a list of firewall hexes
3. Show location of 4 Firewall hexes to the user using Firewall tokens
4. List of firewall hexes sent to backend processing API as part of "turn" submission
5. Effects handled by backend processing

### **Supply Drop**
1. Select a target hex adjacent to the Robot (based on where the Robot is at the beginning of the "round")
2. Cannot be select a hex for placement if that hex that is "obstructed" or that already has a supply drop in it
3. Add coordinates of the target hex to a list of new supply drops
4. List of new supply drop hexes sent to backend processing API as part of "turn" submission
5. Effects handled by backend processing

## **Game Variables**

While the game is in development, certain variables need to be changeable to test the gameplay under different conditions.

The player who initiates a new game is provided a menu of options to select the variables. These variables include:
* **Team Size** number of players on each team (2 or 3). Default 2
* **Map Size** defined by the number of tiles high and number of tiles wide. Default "medium" (40 height 40 width"). Choice of "small" (20 height by 30 width) or "Large" (40 height 60 width).
* **Input Time** amount of time each player has to enter their actions. Default to 90 seconds. Other options: 60 seconds, 120 seconds, 150 seconds.
* **Review Time** amount of time each player has to view the replay at the end of the Turn. Default to 40 seconds. Other options: 20 seconds, 30 seconds, 50 seconds, 60 seconds.
* **Energy Points** number of energy points each Robot starts with, between 0 and 3 (up to that Robot type's maximum), default to 2

Another variable **Buffer Time** defaults to 10 seconds

## **Game End**

If the win condition was met by one team, the game will show the replay but not allow new actions to be input. Instead the player will have an "End Game" option.

The "End Game" option will display a new page with:
* score, ranging from 0 to 1,000. The score will be calculated by the backend and provided at the end of the game.
* "restart game with same players" option
* "Return to main menu" option
