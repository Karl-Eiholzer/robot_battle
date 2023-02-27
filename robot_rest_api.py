############################
#
# robot_rest_api.py
#
# runs while game is running pass data from the client 
#  to the server and from the server to the client.
#
# is built on FLASK
#
# Inputs/Outputs:  routes added to API allow POST, GET, etc... functions:
#
# Inputs              Output
# ------------------- --------------------------------------------------------
# start game (GET?)   acknowledgent with certain IDs assigned to client
# submit turn (PUT?)  200 
# are results ready   simple Y or N
# get results         file with information necessary to reply events and update statistics
#
#############################

# assign port to run on
openPort = '678'
playerOneName = 'Fred'

from flask import Flask
from flask import jsonify
from flask import request
import json
from apiLib.custFunctions import sendSubmissionToInputs

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


#############################
# define the app
app = Flask(__name__)

# @app.before_first_request
# def before_first_request_func():
#     import game_controller
#     game_controller()

@app.route('/hello/', methods=['GET', 'POST'])
def welcome():
    return "Hello World!<BR><BR><em>You have reached ROBOT BATTLE</em>"

@app.route('/contact', methods=['GET', 'POST'])
def contact():
    return "Contact page<BR>See https://github.com/Karl-Eiholzer/robot_battle for more information <BR><BR>Goodbye!!"

@app.route('/person/')
def person():
    return jsonify({'names':'Karl, Otto, Simon',
                    'git':'https://github.com/Karl-Eiholzer/robot_battle'})

@app.route('/submit/', methods=['POST'])
def submit():
    # initialize dictionary to capture various outputs
    finalOut = {}
    # try to get data from put request
    try:
        instantRecord = json.loads(request.data)
        instantOut = 'Success'
    except Exception as e:
        instantOut=str(e)
    # append results of getting data to output package
    finalOut["DataCapture"] = instantOut
    # create filename for output file - depending on which play input the json
    fileName= cwd / InputsDirectoryName / 'P1_M1.json'
    # export dictionary to filepath as json
    try:
        writeResult = sendSubmissionToInputs(InPath=fileName, jsonIn=instantRecord)
        if writeResult == 'Success':
            writeOut = instantRecord
        else: 
            writeOut = writeResult
    except Exception as e:
        writeOut = str(e)
    # append results of write action to the output package
    finalOut["DataWrite"] = writeOut
    return jsonify(finalOut)     
    


#############################
# run the app

if __name__ == '__main__':    
    app.run(host='0.0.0.0', port=openPort, debug=True)


#
# will run locally on http://localhost:[openPort]/hello/
#
