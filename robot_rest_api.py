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

#############################
# define the app
app = Flask(__name__)

@app.route('/hello/', methods=['GET', 'POST'])
def welcome():
    return "Hello World!"

@app.route('/contact')
def contact():
    return "Contact page<BR>See https://github.com/Karl-Eiholzer/robot_battle for more information <BR><BR>Goodbye!!"

@app.route('/person/')
def person():
    return jsonify({'names':'Karl, Otto, Simon',
                    'git':'https://github.com/Karl-Eiholzer/robot_battle'})

@app.route('/submit/<string:name>/<string:move>/')
def submit():
    if name == 'Fred':
        return "Data Recieved from " + name + ":" + move
    else:
       return jsonify({'names':'Karl, Otto, Simon',
                       'git':'https://github.com/Karl-Eiholzer/robot_battle'})



#############################
# run the app

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=openPort)

#
# will run locally on http://localhost:[openPort]/hello/
#
