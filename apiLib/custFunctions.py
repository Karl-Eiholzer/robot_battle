#############################
# define functions that can be called by the API
#
#
#############################

# 
def sendSubmissionToInputs(InPath, jsonIn):
    import json
    try:
        with open(InPath, 'w') as f:
            json.dump(jsonIn, f)
        result='Success'
    except Exception as e:
        result=str(e)
    return(result)
