# RPG Tactical Fantasy Game - Robot Battle
## Fast Simultaneous Turn Strategic Game

the game is a Tactical Fantasy RPG, turn-based and in 2D.
multi-player with web server resolving turn actions between clients

## Architecture Concept

***Web site has django REST API fron end***
* starting code copied from this tutorial: https://www.youtube.com/watch?v=c708Nf0cHrs

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
