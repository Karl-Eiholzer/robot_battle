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
dict = {
    'robot1' : {'start' : [-2,3,1], 'move1' : [-2,3,1], 'move2' : [-2,3,1] , 'health' : 6, 'armor' : 3, 'attack' : 3},



    'robot2' : {'start' : [-2,3,1], 'move1' : [-2,3,1], 'move2' : [-2,3,1] , 'health' : 6, 'armor' : 3, 'attack' : 3},



    'robot3' :  {'start' : [-2,3,1], 'move1' : [-2,3,1], 'move2' : [-2,3,1] , 'health' : 6, 'armor' : 3, 'attack' : 3},



    'player' : { 'player' : 1}

}

createJSON(dict, FilePath)


##############################
# create player 1 move




##############################
# export player move files






##############################
# export game state update files
