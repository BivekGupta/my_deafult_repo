import json
def getKey(obj: dict):
    keys = list(obj)
    if len(keys) != 1:
        raise Exception('Multiple keys are present or empty dict found')
    else:
        return keys[0]


def getNestedValue(obj: dict, key: str, isFound = False):
    #print(obj, key, isFound)
    if type(obj) is not dict and not isFound:
        return None
    if (isFound or (key in obj.keys())) :
        if type(obj[key]) is dict:
            return getNestedValue(obj[key], getKey(obj[key]), True)
        else:
            #print(f'obj[getKey(obj)]: {obj[getKey(obj)]}')
            return obj[getKey(obj)]
    else:
        nestedKey = getKey(obj)
        return getNestedValue(obj[nestedKey], key, False)

if __name__ == '__main__':
    obj_value = input("Enter a nested json: ")
    obj = json.loads(obj_value)
    key_value = input("Enter a key: ")
    value = getNestedValue(obj, key_value)
    print(value)
