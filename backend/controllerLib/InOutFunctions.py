#############################
# define functions that can be called by the Game Controller
#
#
#############################

# generate a random funny name
def nameYourself(n=0):
    import random
    fName = ['Fred','Velma','Shaggy','Daphne','Scooby']
    mName = ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z']
    lName = ['Einstein','Heisenberg','Rutherford','Newton','Feynmen','Curie','Galilei','Bohr','Faraday']
    outName = str( random.choice(fName) + ' ' + random.choice(mName) + '. ' + random.choice(lName))
    return(outName)

# generate a random funny name
def nameTheGame(n=0):
    import random
    fName = ['angry', 'bold', 'brutal', 'cutthroat', 'dangerous', 'ferocious', 'fiery', 'furious', 'intense', 'murderous', 'passionate', 'powerful', 'raging', 'relentless', 'savage', 'stormy', 'strong', 'terrible', 'vehement', 'vicious', 'animal']
    mName = ['delicate', 'devilish', 'disobedient', 'elfish', 'frolicsome', 'impish', 'little', 'minute', 'misbehaving', 'naughty', 'petite', 'playful', 'prankish', 'puckish', 'puny', 'slight']
    lName = ['action', 'assault', 'attack', 'bloodshed', 'bombing', 'campaign', 'clash', 'combat', 'conflict', 'crusade', 'encounter', 'fighting', 'hostility', 'skirmish', 'strife', 'struggle', 'war', 'warfare', 'barrage', 'brush', 'carnage', 'contention', 'engagement', 'fray', 'havoc', 'onset', 'onslaught', 'press', 'ravage', 'scrimmage', 'sortie']
    outName = str( random.choice(fName) + ' and ' + random.choice(mName) + ' ' + random.choice(lName) + ' ' + str(random.randint(1, 100)) )
    return(outName)


# put the json file where you need it
def createJSON( inputDict, FilePath):
    import json
    jsonObject = json.dumps(inputDict, indent = 4)
    # export dictionary to filepath as json
    with open(FilePath,'w') as f:
            json.dump(inputDict, f, indent = 4)

# file ACK function
def FileAck(inputFileName, inputControllerName, outPath, gameName, errStatus='good'):
    returnStatus = 0
    outDict = {'FileName': inputFileName, 'GameController': inputControllerName, 'NameOfGame':gameName, 'status': errStatus}
    if errStatus == 'good':
        outputFileName = str('ack_' + inputFileName)
    else:
        outputFileName = str('err_' + inputFileName)
    outputFullFilePath = outPath / outputFileName
    print(outputFullFilePath)
    try:
        createJSON(outDict,outputFullFilePath)
    except:
        returnStatus = 1
    return(outputFileName, returnStatus)

# game controller error function
def gameControlError(errMessage):
    outDict = {'ControllerId': inputFileName, 'status': errStatus}
    if errStatus == 'good':
        outputFileName = str('ack_' + inputFileName)
    else:
        outputFileName = str('err_' + inputFileName)
    outputFullFilePath = OutputsDirectoryPath / outputFileName
    print(outputFullFilePath)
    try:
        createJSON(outDict,outputFullFilePath)
    except:
        returnStatus = 1
    return(outputFileName, returnStatus)

def moveToArchive(fileName, currPath, archPath, gameName):
    import shutil
    import os
    uniqueName = gameName.replace(' ','_')
    gameArchiveDirectoryPath = archPath / uniqueName
    fileToArch = currPath / fileName
    fileArchive = gameArchiveDirectoryPath / fileName
    # create archive folder if it does not exist
    if os.path.exists(archPath):
        pass 
    else:
        os.mkdir(archPath)
    # create subfolder specific to game if it does not exist
    if os.path.exists(gameArchiveDirectoryPath):
        pass 
    else:
        os.mkdir(gameArchiveDirectoryPath)
    #  print('Processing ' + fileName)
    shutil.copy2(fileToArch, fileArchive)
    os.remove(fileToArch)
