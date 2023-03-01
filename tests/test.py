

################################
#
# robot_battle_test_client
#
#
#
#
################################


import requests
import json
from datetime import datetime
import random


################################
#

baseURL = 'http://localhost:678/'

helloUrl = baseURL + 'hello/' 
contactUrl = baseURL + 'contact' 
submitUrl = baseURL + 'submit/' 


################################
# ping the hello page and see results

r = requests.post(helloUrl)
print(r.status_code)
x = r.text
print(x)


###############################
# if you want to use the broser to check the application, try these URLs

# import webbrowser
# webbrowser.open('http://localhost:678/hello/', new=2)
# webbrowser.open('http://localhost:678/contact', new=2)
# webbrowser.open('http://localhost:678/person/', new=2)


################################
# ping the contacts page and see results

r = requests.post(contactUrl)
if r.status_code != 200:
    print('\n')
    print('WARNING: YOU GOT AN ERROR')
    print(r.status_code)
    print('\n')
else:    
    x = r.text
    print(x)



###############################

# create rando data for dictionary
now = datetime.now() # current date and time
dateTime = now.strftime("%m/%d/%Y, %H:%M:%S")
namePool1 = ['Fred','Velma','Shaggy','Daphne','Scooby','Otto','Simon','Karl']
namePool2 = ['Einstein','Heisenberg','Rutherford','Newton','Feynmen','Curie','Galilei','Bohr','Faraday','Eiholzer','Rhodes']
randoName = str( random.choice(namePool1) + '_' + random.choice(namePool2) )
# construct the dictionary which will be the JSON
InnerRandoDict = {'firstField':'firstData',
             'secondField':'secondData',
             'thirdField':'thirdData'}
randoDict = {'playerName': randoName,
             'timestamp':dateTime,
             'innerDict':InnerRandoDict}

# create function that posts the JSON to the correct API URL
def postSomeJson(targetUrl, postData):
    print(targetUrl)
    print(postData)
    r = requests.post(targetUrl, json=postData)
    if r.status_code != 200:
        print("Error: " + str( r.status_code ) )
        data = str( r.status_code )
    else:
        data = r.json()
    return(data)
# call the function
x = postSomeJson(submitUrl, randoDict)
print(x)