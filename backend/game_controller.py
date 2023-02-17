############################
#
# game_controller.py
#
# runs while game is running to resolve player moves
# and send back results.
#
# Inputs:  files dropped into inputs folder
#           - game start file (causes to reset to initial conditions)
#           - player move files
#           - game end file (causes to terminate run)
# Outputs: replay files sent to outputs folder
#           - file recieved/being processed
#           - replay files
#           - error file (indicates error in processing)
#
#############################

# Import Libraries
import json
import os 

# working directory management
from pathlib import Path
import sys as sys
import time
cwd = Path()
cwd = cwd.absolute()
ProjDirectory = cwd
# only change these parameters if the structure of the project folders changes
locationName = 'backend'
InputsDirectoryName = 'controller_inputs'
InputsDirectoryPath = cwd / locationName / InputsDirectoryName
OutputsDirectoryName = 'controller_outputs'
OutputsDirectoryPath = cwd / locationName / OutputsDirectoryName

# get local functions
FunctionsDirectoryName = 'controllerLib'
FunctionsDirectoryPath = cwd / locationName / FunctionsDirectoryName
os.chdir(FunctionsDirectoryPath)
from InOutFunctions import nameYourself, createJSON, FileAck, gameControlError
from gameFunctions  import 
os.chdir(ProjDirectory)

#############################
# set key parameters

# set a random name for this contoller
controllerName = nameYourself()
startFileName = 'startGame.json'
endFileName   = 'endGame.json'

#############################
# main function
run = 0
errorMsg = ''
allFilesProcessed = []

while run == 0:
    # set control and tracking variables
    PlayerOneRecieved = 0 # did we get payer 1
    PlayerTwoRecieved = 0 # did we get payer 1
    ProcessingInputs = 'No'
    filesToProcess = []

    # cycle while waiting for inputs to arrive
    while ProcessingInputs == 'No':        
        # check input directory for new files
        inputFileList = os.listdir(InputsDirectoryPath)
        currCount = len(inputFileList)
        if len(inputFileList) = 1:
            for i in  
        else:
            print(inputFileList)

        time.sleep(2)

    x, y = FileAck(inputFileName='p1_m1.json', inputControllerName=controllerName, outPath=OutputsDirectoryPath, errStatus='good')




