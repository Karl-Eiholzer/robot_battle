# Description of Robot Game Client Mechanics

Describes game set-up and how turns are input by the Godot game client

## Overview

Each player has a robot that is "Captain" and multiple other robots. Your team wins if one of your robots legally moves into the hex occupied by the other team's "Captain", which is called "Capture".

Players are trying to keep their Captain from being captured while simultaneously trying to capture the opponent's Captain.

### Full game steps

1. One player initiates the game and gets a "game ID" to share with other players. This player sets game variables. See **Game Variables** below
2. Other players obtain the game ID and enter the same game
3. Players signal readiness and the player who initiated the game assigns roles to each player on their team. See **Player Roles** below.
4.  by downloading the map. See **Initial Download** below
5. Game starts and proceeds in a series of "turns" where all players enter their moves for that "turn" at the same time and all players get the results back at the same time.  Each turn consists of 6 rounds - see **Player options within a turn** below
6. Turns continue until win condition is met for one teams. When the win condition is met, backend processing stops and a final replay and score are sent to the players. See **Single turn steps** below

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


## **Game Start**

* Players should be prompted to provide a username. If none is provided, a humorous username is auto-generated and click "Ready"
* When all players select "Ready", the player that initiated the game assigns player role to each player.

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
