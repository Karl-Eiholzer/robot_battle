# RPG Tactical Fantasy Game - Robot Battle
## Fast Simultaneous Turn Strategic Game

the game is a Tactical Fantasy RPG, turn-based and in 2D.
multi-player with web server resolving turn actions between clients

## Architecture Concept

***Web site has django REST API fron end***
* starting code copied from this tutorial: https://www.youtube.com/watch?v=c708Nf0cHrs
* github here: https://github.com/codingforentrepreneurs/Django-Rest-Framework-Tutorial

***Client is pygame***
* but it posts actions to the REST API (POST)
* and it retrieves game status from REST API (GET)
* it then uses the data from the REST API to update the player game state

***The django REST API has the game manager running behind it***
* the game manager resolves the simultaneous turns
* the game manager also combines the actions from the various clients and determines what the results are
* results are then sent back (as JSON) for the client to update its game state

## Game Process Concept

***Phase 1: Players enter moves***
* handled by client
* converted by client into JSON
* POST move JSON to REST API
* client begins to repeatedly ping REST API turn results to see if results are available (the REST API will return a "please wait" response)

***Phase 2: Turn Resolution***
* REST API passes move information to game_manager.py
* game_manager.py resolves actions of both players and determines new game state
* game_manger.py makes results available

***Phase 3: Players Updated***
* client is pinging REST API turn results and suddenly gets results
* client downloads JSON with updated game state (robot positions and health)
* client renders/displays updated game state to player
* results may indicate that a player has won, triggering end-game actions

***Return to Phase 1***
* if end game actions not triggered


## Movement Conflict Resolution Rules

***Player actions***
* at the start of a turn each player is given four points to allocate to attack and defense across your entire team (For example, you could add 4 points to a single robot's armor, or 1 point each to all three's armor plus one to one of the robot's attacks)
* each robot must try to make two moves per turn

***Attack, defense, and Health***
* when two robot attempt to enter the same hex on the same move, they battle
* the robot deals damage equal to their attack points
* damage is first applied against armor, and then against health
* once health reaches 0 the robot is dead
* each time you attack your attack point are reduced by 1

***Initiative*** Do we want this rule?
* robots assigned initiative order by player
* robots move in initiative order
* players can block themselves if they are not careful

***Resolving Movement - two robots move into same hex on same move***
* robot with higher initiative moves in
* second robot attacks from the hex where it is
* robots battle
* if defending robot is killed, attacking robot moves into hex
* if defending robot kills attacking robot, the hex the attacking robot was entering from is free
* if neither robot wins and it was the first move:
  * defending robot will execute next move
  * attacking robot will attempt the same move (i.e., try to move into the hex again)
* if neither robot wins and it was the second move:
  * both robots stay where they are

***Resolving Movement - chasing robot has higher initiative, catches other***
* even if a robot is leaving a square, it can be attacked before leaving
* the robot moving in must have higher Initiative
* battle occurs and points are resolved
* robot with higher initiative has move "pend"
* if leaving robot able to leaves hex on it's initiative order
  * leaving robot leaves
  * hex is now free for next highest initiative robot attempting to move in
  * may not be the robot that attacked
* if leaving robot NOT able to leaves hex on it's initiative order
  * attacking robot's move is marked fail
  * if move 1, attacking robot will attempt the same move on a second move


***Resolving Movement - more than 2 robots move into same hex on same move***


***Resolving Movement - enemy robots exchange hexes***
Example: robot 1 goes from A to B, while simultaneously robot 2 moves from B to A


***Resolving Movement - robot blocked, cannot advance***
Example: target hex becomes occupied by robot with higher Initiative
Example: following another robot that itself becomes blocked

***Pseudo-code for back end turn resolution***
* initiate: robots all placed to MoveStatus = PENDING and Initiative values updated, Buffs to stats are applied
* put starting positions and metrics in the MoveLog
  * Nested Dictionary: MoveLog:
    MoveNum - [Robot -
      [Id - n, Status - n, Health - n, Armor - n, Attack - n],
               Moves -
      [ Start - , End - ]
              ]
* CurrentPositions dictionary (initiate if start of game, otherwise same from prior end-of-turn)
    * CurrentPositions dictionary: HexPosition - RobotId
* CurrentRobotStatus nested dictionary (initiate if start of game, otherwise same from prior end-of-turn)
    * RobotId - [RobotStatus - n, MoveStatus - CHAR, Initiative - n, Team - n, Health - n, Armor - n, Attack - n]

* while RUN flag 0 select robot to attempt move
  * Construct list from CurrentRobotStatus with RobotID, RobotStatus - n, MoveStatus - CHAR, Initiative - n
  * if all RobotStatus in DEAD or COMPLETE status
    * update RUN flag to 1
    * pass
  * else
    * if LastMoveStatus returns DEFER
      * select robot with highest initiate in PENDING status
      * call MoveResolution function for selected robot
    * else LastMoveStatus status != DEFER
      * select robot with highest initiate in DEFER status
      * call MoveResolution function for selected robot
* while run flag != 0
  * call return gamestate function

* MoveResolution function(RobotId, )
  * inputs: robot ID
  * output: move status, robot position, updated robot statistics
  * move status return is DEFER, COMPLETE, or DEAD
* call IsHexOccupied function
* if square is free
  * update location
  * set move status = COMPLETE
  * return
* else square is not free
  * if occupied by friendly
    * no location update
    * set move status = DEFER
    * return
  * else occupied by enemy
        * call BATTLE function
        * if robot status returns DEAD
          * update location (not on board)
          * return
        * else robot status returns ALIVE
          * no location update
          * set move status = DEFER (because other robot may yet move out)

* IsHexOccupied function (HexPosition)
  * Check if HexPosition in CurrentPositionStatus
  * If yes, retrieve

* get RobotCurrentStateFunction
  * TBD
