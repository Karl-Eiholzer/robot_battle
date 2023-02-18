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


# put the json file where you need it
def createJSON( inputDict, FilePath):
    import json
    jsonObject = json.dumps(inputDict, indent = 4)
    # export dictionary to filepath as json
    with open(FilePath,'w') as f:
            json.dump(inputDict, f, indent = 4)

# file ACK function
def FileAck(inputFileName, inputControllerName, outPath, errStatus='good'):
    returnStatus = 0
    outDict = {'FileName': inputFileName, 'GameController': inputControllerName, 'status': errStatus}
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
def gameControlError(errStatus='good'):
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


