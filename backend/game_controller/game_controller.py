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
# from gameFunctions  import 
os.chdir(ProjDirectory)

#############################
# set key parameters

# set a random name for this contoller
controllerName = nameYourself()
validProcessingStates = ['No','Restart','Shut Down','Ready','Timeout']
startFileName = 'startGame.json'
endFileName   = 'endGame.json'

#############################
# main function
run = 0
errorMsg = ''
allFilesProcessed = []
moveNum = 0

while run == 0:
    # set control and tracking variables
    PlayerOneRecieved = 0 # did we get payer 1
    PlayerTwoRecieved = 0 # did we get payer 1
    ProcessingInputs = 'No'
    filesToProcess = []
    moveNum += 1

    # cycle while waiting for inputs to arrive
    WaitForFileCount = 0
    while ProcessingInputs == 'No':        
        # check input directory for new files
        inputFileList = os.listdir(InputsDirectoryPath)
        currCount = len(inputFileList)
        p1Expected = str('P1_M' + str(moveNum) + '.json')
        p2Expected = str('P2_M' + str(moveNum) + '.json')
        if currCount > 0:
            for i in range(0,currCount):
                if startFileName in inputFileList:
                    ProcessingInputs = 'Restart'
                    allFilesProcessed = []
                    fileToRemove = InputsDirectoryPath / startFileName
                    os.remove(fileToRemove)
                    # remove files from directory
                elif endFileName in inputFileList:
                    ProcessingInputs = 'Shut Down'
                    allFilesProcessed = []
                    fileToRemove = InputsDirectoryPath / endFileName  # replace with something that removes all files
                    os.remove(fileToRemove)
                    # remove files from directory
                elif p1Expected in inputFileList and p2Expected in inputFileList:
                    filesToProcess.append(p1Expected)
                    allFilesProcessed.append(p1Expected)
                    filesToProcess.append(p2Expected)
                    allFilesProcessed.append(p2Expected)
                    ProcessingInputs = 'Ready'
                else:
                    WaitForFileCount += 1
                    time.sleep(3)
        else:
            WaitForFileCount += 1
            if WaitForFileCount > 10:
                ProcessingInputs = 'Timeout'
            else:
                time.sleep(3)

    
    if ProcessingInputs in validProcessingStates:
        pass
    else:
        # do things to clear up the game space
        print('Value for ProcessingInputs is incorrect:')
        print(ProcessingInputs)
        run = 1

    if ProcessingInputs == 'Restart':
        # do things to clear up the game space
        print('Gamespace reset - waiting')
    else:
        pass

    if ProcessingInputs == 'Shut Down':
        # do things to clear up the game space
        print('Game end message recieved')
        print('Game is shutting down')
        run = 1
    else:
        pass

    if ProcessingInputs == 'Timeout':
        # do things to clear up the game space
        print('Timed out waiting for files - shutting down')
        run = 1
    else:
        pass

    if ProcessingInputs == 'Ready':
        # do things to clear up the game space
        print('Play the turn!!!')
        print('Generate results!!')
        run = 1
    else:
        pass
        

    x, y = FileAck(inputFileName='p1_m1.json', inputControllerName=controllerName, outPath=OutputsDirectoryPath, errStatus='good')




