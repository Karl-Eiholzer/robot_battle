# Robot Game Backend Mechanics

Describes game start after initialization and how the backend should combine the collective set of moves submitted by the players and produce a result

This description of the backend does not cover the mechanics by which 4 or 6 players are assigned to the same game.

## **Prerequisites**

* Four or six players have exchanged information with the backed sufficient for each player to be uniquely identified
* The **Game Variables** were submitted by the player initiating the game sufficient to generate a map, generate Robots of correct types and number, assign Robots to players, set initial settings for Robots

## **Game Variables**

While the game is in development, certain variables need to be changeable to test the gameplay under different conditions.

The JSON posted to the API from the Godot Client by the player who initiates a new game will include variables which affect game set-up. These variables include:
* **Team Size** number of players on each team (2 or 3). Default 2
* **Map Size** defined by the number of tiles high and number of tiles wide. Default "medium" (40 height 40 width"). Choice of "small" (20 height by 30 width) or "Large" (40 height 60 width).
* **Input Time** amount of time each player has to enter their actions
* **Review Time** amount of time each player has to view the replay at the end of the Turn
* **Energy Points** number of energy points each Robot starts with, between 0 and 3 (up to that Robot type's maximum), default to 2

The backend processor uses these variables to configure the game at the start.

## **Start of Game**

One player on each team has assigned the roles to the players on that team and clicked "Ready", and that information is posted to the API

Once the Ready Signal is received from both sides, the map and starting positions are generated and made available to be retrieved

### Data to send to Godot Clients at start:

NOTE: a customized JSON is sent to each player

Minimum JSON contents at start of game:
* fields necessary for preventing cheating (customized to each player)
* which team has "initiative" the first turn
* timestamp of start-of-turn (same for all players)
* map data (same for all players)
* Player Robot data for each Robot controlled by Player: (a) Robot type, (b) Robot position at start of first turn, and (c) Robot energy level (customized to each player)
* Robot data for all other Robots: (a) Robot type, (b) Robot Team, and (b) Robot position at start of turn (customized to each player)

## **Turn Processing**

Upon receipt of submitted actions by all players, the backend moves through the following steps

NOTES:
* each turn consists of 6 rounds
* "initiative" alternates between teams each turn

###  Parse input data

Input data should include the following for each player for each Robot for each round in the turn:
 - **Robot ID**
 - **Coordinates Before Action** Hex coordinates the Robot started the round in, if all prior actions successful
 - **Coordinates After Action** Hex coordinates the Robot will end the round in, if that action is successful (same as **Coordinates Before Action** if "wait" action)
 - **Deploy action** May be NULL, will have Deploy Action Type and associated data is not NULL

### Establish order that robots will go in in each round
 1. all Robots on the team with "initiative" for the turn go first before any Robot on the team without initiative go
 2. on a given team, Robot Types have the variable "Team Order". All Robots go in order from lowest "Team Order" to highest "Team Order"
 3. if two Robots are on the same team and have the same "Team Order", one is chosen randomly to go next
The order established in this step should be repeated for every round of the turn.
All Robots should appear once in the list.

### Evaluating single round for single Robot - Repeat for each round
Stunned vs Active - all Robots should start the turn with a state of "Active" but may change to "Stunned" during the turn
 1. If Robot is in "Stunned" state: update replay file with animation type: "Stunned", do nothing and skip to next Robot in Order
 2. If Robot not in "Stunned" state: identify action with lowest round number where action status is not "Success" and evaluate that action, even if "round" for that action was prior round

Processing earliest action that has not been recorded as "Success":
 1. If Robot being evaluated **Coordinates Before Action** are the same as coordinates of a Robot on the opposing team that has a higher Strength Score: change the hex location of the Robot being processed to where it started at the beginning of the first turn of the game, set state to "Stunned", update replay file with animation type: "Stunned", and skip to next Robot in Order
 2. If "wait" action and hex has "Firewall" Object: delete the "Firewall" object, change the hex location of the Robot being processed to where it started at the beginning of the first turn of the game, set state to "Stunned", update replay file with animation type: "Stunned", and skip to next Robot in Order
 3. If "wait" action and hex has "EMP" object: set state to "Stunned", coordinates of robot being processed remain **Coordinates Before Action**, update replay file with animation type: "Stunned", and skip to next Robot in Order
 4. If "wait" action: process "deploy" action (if any), record action status as "Success", coordinates of robot being processed remain **Coordinates Before Action**, update replay file with animation type: "Waiting", and skip to next Robot in Order
 5. If "move" action and **Coordinates After Action** is unoccupied: process "deploy" action (if any), record action status as "Success", coordinates change to **Coordinates After Action**, update replay file with animation type: "Move", and skip to next Robot in Order
 6. If "move" action and **Coordinates After Action** have same hex coordinates as "Captain" Robot on other team: record game status as "Win" for team, record action status as "Win", coordinates of robot being processed remain **Coordinates Before Action**, update replay file with animation type: "Bump", and skip to next Robot in Order
 7. If "move" action and **Coordinates After Action** have same hex coordinates of a Robot on same team: do not process the deploy action (if any), record action status as "Fail", coordinates of robot being processed remain **Coordinates Before Action**, update replay file with animation type: "Bump", and skip to next Robot in Order
 8. If "move" action and **Coordinates After Action** have same hex coordinates as a Robot on opposing team and opposing Robot has lower strength score than Robot being processed: process deploy action (if any), record action status as "Success", coordinates change to **Coordinates After Action**, update replay file with animation type: "Power Move", and skip to next Robot in Order
 9. If "move" action and **Coordinates After Action** have same hex coordinates as a Robot on opposing team and opposing Robot has higher strength score than Robot being processed: do not process the deploy action (if any), record action status as "Fail", coordinates of robot being processed remain **Coordinates Before Action**, update replay file with animation type: "Bump", and skip to next Robot in Order
 10. If "move" action and **Coordinates After Action** have same hex coordinates as "obstructed" hex: record action status as "Error", coordinates of robot being processed remain **Coordinates Before Action**, log an error for the game, update replay file with animation type: "Bump", and skip to next Robot in Order
 11. If "move" action and **Coordinates After Action** have same hex coordinates as "Supply Drop" object, add one energy to the Robot energy count, delete the "Supply Drop" object, process deploy action (if any), record action status as "Success", coordinates change to **Coordinates After Action**, update replay file with animation type: "Move", and skip to next Robot in Order
 12. If none of the above, record action as "Error", log an error for the game, coordinates of robot being processed remain **Coordinates Before Action**, update replay file with animation type: "Puzzled", and skip to next Robot in Order

#### Processing Deploy Actions:

Deploy action is "EMP":
 - assign "EMP" object to all hexes identified by the submitted JSON

 Deploy action is "Firewall":
 - assign "Firewall" object to all hexes identified by the submitted JSON

 Deploy action is "Supply Drop":
 - assign "Supply Drop" object to the hex identified by the submitted JSON

### Creation of replay file for each players
As the actions are processed for each round for each turn, a replay file should be built so that the players can see the turn replayed after it downloads.
Animations may be of the following types for each round: "Stunned", "Waiting", "Move", "Bump", "Power Move", or "Puzzled".

## **Robot Types**

### **Captain**
* Moves actions per turn: 3
* Starting number of energy points: set by variable
* Maximum Energy: 2
* Type of Deployment Action: **EMP**
* Sight Range: 5 hexes
* Team Order: 1
* Strength: 7

### **Scout**
* Moves actions per turn: 4
* Starting number of energy points: set by variable
* Maximum Energy: 6
* Type of Deployment Action: **Extra Moves**
* Sight Range: 7 hexes
* Team Order: 3
* Strength: 3

### **Defender**
* Moves actions per turn: 2
* Starting number of energy points: set by variable
* Maximum Energy: 3
* Type of Deployment Action: **Firewall**
* Sight Range: 3 hexes
* Team Order: 3
* Strength: 5

### **Engineer**
* Moves actions per turn: 6
* Starting number of energy points: set by variable
* Maximum Energy: 3
* Type of Deployment Action: **Supply Drop**
* Sight Range: 5 hexes
* Team Order: 0
* Strength: 0
