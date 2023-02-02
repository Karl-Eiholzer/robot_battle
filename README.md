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
