##############################
#
#  JSON files generator
#
#  a script to construct JSON files for testing purposes
#
#  Goal: to ensure a set of well formatted files are
#  available for stub testing
#
#
#
##############################

# Import Librariescwd
import json
from pathlib import Path
import sys as sys
from time import time

# working directory management
from pathlib import Path
import sys as sys
from time import time
cwd = Path()
cwd = cwd.absolute()
ProjDirectory = cwd
# only change these parameters if the structure of the project folders changes
TestsDirectoryName = 'tests'
JsonDirectoryName = 'input_moves'
JsonDirectoryPath = cwd / TestsDirectoryName / JsonDirectoryName


##############################
# define cool functions

def randoMove( coords ):
    import random
    x = coords[0]
    y = coords[1]
    z = coords[2]
    evalSet = []
    moveSet = []
    m1 = [x+1, y-1, z]
    m2 = [x+1, y,   z-1]
    m3 = [x-1, y+1, z]
    m4 = [x-1, y,   z+1]
    m5 = [x,   y-1, z+1]
    m6 = [x,   y+1, z-1]
    evalSet = [m1, m2, m3, m4, m5, m6]
    x = len(evalSet)
    for i in range(0,x):
        # print(i)
        m = evalSet[i]
        # print(m)
        if max(m) > 3 or min(m) < -3:
            pass
        else:
            moveSet.append(m)
    # print(evalSet)
    # print(moveSet)
    rando = random.choice(moveSet)
    return(rando)

##############################
# function to export dictionaries as JSON
# inputs: two dictionaries, file location
# output: JSON file in the output location

def createJSON( inputDict, FilePath):
    jsonObject = json.dumps(inputDict, indent = 4)
    # export dictionary to filepath as json
    with open(FilePath,'w') as f:
            json.dump(inputDict, f, indent = 4)


##############################
# create player 1 move
FileName = 'P1_M1.json'
FilePath = JsonDirectoryPath / FileName 
start1 = [-3,0,3]
start2 = [-2,-1,3]
start3 = [-3,1,2]
dict = {
    'robot1' : {'start' : start1, 'move1' : randoMove(start1), 'move2' : [] , 'health' : 6, 'armor' : 3, 'attack' : 3, 'initiative' : 1 },
    'robot2' : {'start' : start2, 'move1' : randoMove(start2), 'move2' : [] , 'health' : 6, 'armor' : 3, 'attack' : 3, 'initiative' : 2 },
    'robot3' : {'start' : start3, 'move1' : randoMove(start3), 'move2' : [] , 'health' : 6, 'armor' : 3, 'attack' : 3, 'initiative' : 3 },
    'player' : { 'player' : 1}
}
dict['robot1']['move2'] = randoMove(dict['robot1']['move1'])
dict['robot2']['move2'] = randoMove(dict['robot2']['move1'])
dict['robot3']['move2'] = randoMove(dict['robot3']['move1'])

createJSON(dict, FilePath)


##############################
# create player 1 move
FileName = 'P2_M1.json'
FilePath = JsonDirectoryPath / FileName 
start1 = [3,0,-3]
start2 = [3,-1,-2]
start3 = [2,1,-3]
dict = {
    'robot1' : {'start' : start1, 'move1' : randoMove(start1), 'move2' : [] , 'health' : 6, 'armor' : 3, 'attack' : 3, 'initiative' : 1 },
    'robot2' : {'start' : start2, 'move1' : randoMove(start2), 'move2' : [] , 'health' : 6, 'armor' : 3, 'attack' : 3, 'initiative' : 2 },
    'robot3' : {'start' : start3, 'move1' : randoMove(start3), 'move2' : [] , 'health' : 6, 'armor' : 3, 'attack' : 3, 'initiative' : 3 },
    'player' : { 'player' : 2}
}
dict['robot1']['move2'] = randoMove(dict['robot1']['move1'])
dict['robot2']['move2'] = randoMove(dict['robot2']['move1'])
dict['robot3']['move2'] = randoMove(dict['robot3']['move1'])

createJSON(dict, FilePath)



##############################
# export player move files






##############################
# export game state update files


