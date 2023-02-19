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
import shutil
import sys


# working directory management
from pathlib import Path
import sys as sys
import time
cwd = Path()
cwd = cwd.absolute()
ProjDirectory = cwd
# only change these parameters if the structure of the project folders changes
InputsDirectoryName = 'controller_inputs'
InputsDirectoryPath = cwd / InputsDirectoryName
OutputsDirectoryName = 'controller_outputs'
OutputsDirectoryPath = cwd / OutputsDirectoryName
ArchiveDirectoryName = 'archive'
ArchiveDirectoryPath = cwd / ArchiveDirectoryName

# get local functions
FunctionsDirectoryName = 'controllerLib'
FunctionsDirectoryPath = cwd / FunctionsDirectoryName
sys.path.append(FunctionsDirectoryPath)
os.chdir(FunctionsDirectoryPath)
from InOutFunctions import nameYourself, nameTheGame, createJSON, FileAck, gameControlError, moveToArchive
# from gameFunctions  import 
os.chdir(ProjDirectory)

#############################
# set key parameters

# set a random name for this contoller
controllerName = nameYourself()
# for stray files that come in a gunk up the works
validProcessingStates = ['No','Restart','Shut Down','Ready','Timeout']
startFileName = 'startGame.json'
endFileName   = 'endGame.json'
# name the game for this run
gameName = nameTheGame()

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
        currCount = 0
        for f in inputFileList:
            if f[-5:] == '.json':
                currCount += 1
            else:
                pass
        p1Expected = str('P1_M' + str(moveNum) + '.json')
        p2Expected = str('P2_M' + str(moveNum) + '.json')
        if currCount > 0:
            for i in range(0,currCount):
                if startFileName in inputFileList:
                    ProcessingInputs = 'Restart'
                    # allFilesProcessed = []
                    filesToProcess = []
                    # remove files from directory
                    x, y = FileAck(inputFileName=startFileName, inputControllerName=controllerName, outPath=OutputsDirectoryPath, gameName=gameName, errStatus='good')
                    moveToArchive(startFileName, InputsDirectoryPath, ArchiveDirectoryPath, gameName)
                    #exit
                    run = 1
                elif endFileName in inputFileList:
                    ProcessingInputs = 'Shut Down'
                    # allFilesProcessed = []
                    filesToProcess = []
                    # remove files from directory
                    x, y = FileAck(inputFileName=endFileName, inputControllerName=controllerName, outPath=OutputsDirectoryPath, gameName=gameName, errStatus='good')
                    moveToArchive(endFileName, InputsDirectoryPath, ArchiveDirectoryPath, gameName)
                    #exit
                    run = 1
                elif p1Expected in inputFileList and p2Expected in inputFileList:
                    if p1Expected in filesToProcess:
                        pass
                    else:
                        filesToProcess.append(p1Expected)
                        allFilesProcessed.append(p1Expected)
                    if p2Expected in filesToProcess:
                        pass
                    else:
                        filesToProcess.append(p2Expected)
                        allFilesProcessed.append(p2Expected)
                    ProcessingInputs = 'Ready'
                else:
                    WaitForFileCount += 1
                    time.sleep(10)
        else:
            WaitForFileCount += 1
            if WaitForFileCount > 30:
                ProcessingInputs = 'Timeout'
            else:
                time.sleep(2)

    
    if ProcessingInputs in validProcessingStates:
        pass
    else:
        # do things to clear up the game space
        print('Value for ProcessingInputs is incorrect:')
        print(ProcessingInputs)
        print('Exiting application')
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

    # code for scenario where both players files have been recieved and need to be processed 
    if ProcessingInputs == 'Ready':
        # do things to clear up the game space
        print('Play the turn!!!')
        print('Generate results!!')
        errStatus = 0
        for i in range(0,2):
            fileName = filesToProcess[i]
            try:
                x, y = FileAck(inputFileName=fileName, inputControllerName=controllerName, outPath=OutputsDirectoryPath, gameName=gameName, errStatus='good')
                errStatus = max(0,errStatus)
                moveToArchive(fileName, InputsDirectoryPath, ArchiveDirectoryPath, gameName)
            except:
                # do things to clear up the game space
                print('Either the FileAck function or the moveToArchive function failed. Exiting.')
                run = 1
        if errStatus > 0:
            print('Error status returned from FileAck')
            print('Check output folder to see if file was acknowledged')
            run = 1
        else:
            ProcessingInputs = 'No'
    else:
        pass
        
    print(filesToProcess)
    




