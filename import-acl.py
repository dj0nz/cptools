#!/usr/bin/python3

# Import filtered Cisco acls and objects to Check Point database
# dj0Nz mar 2024

# modules needed to query mgmt api, parse input and format output 
import os, requests, json, netrc, re, sys, socket, time

# next two lines needed to suppress warnings if self signed certificates are used
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

##########
# Variables

# check point management server
host = '192.168.1.11'
auth_file = '/home/api/api/.netrc'

# check credentials file, quit if not there
exists = os.path.isfile(auth_file)
if not exists:
    quit('Credentials file not found. Exiting.')

# Input files  
objects_in = 'netobjects.txt'
rules_in = 'rules.txt'

# Lists for network objects and rules
netobjects_in = []
netobjects = []
rules_in = []
rules = []

# Comment for every newly created object
comments = 'Migrated from Cisco ACL'

# End variables section
##########

##########
# Functions

# check if port open
def port_open(ip,port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.settimeout(1)
        sock.connect((ip, int(port)))
        return True
    except:
        return False

# do web_api call and return json structure to work on
def api_call(ip_addr, command, json_payload, sid):
    url = 'https://' + ip_addr + '/web_api/' + command
    if sid == '':
        request_headers = {'Content-Type' : 'application/json'}
    else:
        request_headers = {'Content-Type' : 'application/json', 'X-chkp-sid' : sid}
    response = requests.post(url,data=json.dumps(json_payload), headers=request_headers, verify = False)
    status_code = response.status_code
    return [status_code, response.json()]

# login: read netrc file and extract credentials for host if any
# then do login and return sid or login error
def api_login(cp_mgmt,netrc_file):
    # get login credentials from .netrc file
    auth = netrc.netrc(netrc_file)
    token = auth.authenticators(cp_mgmt)
    if token:
        user = token[0]
        password = token[2]
    else:
        quit('Host not found in netrc file. Exiting.')
    # do login
    payload_local = {'user':user, 'password' : password}
    response = api_call(cp_mgmt,'login',payload_local,'')
    if str(response[0]) == '200':
        return response[1]["sid"]
    else:
        return 'Login error'

# Check if object with given name is present in Check Point database
def object_exists(object_local,type_local,host_local,sid_local):
    # set payload for api call - other settings (limit etc.) not needed here
    payload = { 
        "type" : type_local,
        "filter" : object_local 
    }
    # issue api call and store response elements (0 = response code, 1 = data)
    response = api_call(host_local, 'show-objects', payload, sid_local)
    if str(response[0]) == '200':
        total = response[1]['total']
        if total > 0:
            return(True)
        else:
            return(False) 
    else:
        print(response[1])
        quit('Unknown response in api call') 


##################
### main section
##################

# check if management server reachable, quit if not
if not port_open(host,443):
    quit('Management unrechable.')

# get session id needed to authorize api call
sid = api_login(host,auth_file)
if sid == 'Login error':
    quit('Login error. Exiting.')

# read objects
with open(objects_in) as file:
    # read lines without \n
    netobjects_in=file.read().splitlines()

# Counter to determine if publish is necessary
new_obj_count = 0

# First step: Import host and network object. Naming schema is:
# - 'host_<ipaddress>'
# - 'net_<subnet address>_<mask length>'
# Also, a comment (see variables) will be added in order to better identify newly created objects in Object Explorer.
print('Importing network and host objects...')

# Check if object exists, create, if not
# Note: There is no syntax checking of ip addresses. This is done already in the export script (parse-acl.py) 
for netobject in netobjects_in:
    # check if host or network object, check if already present, tag if not
    new_object = False
    split_object = netobject.split('/')
    if split_object[1] == '32':
        # this is a host object
        object_name = 'host' + '_' + str(split_object[0])
        object_addr = str(split_object[0])
        object_type = 'host'
        if object_exists(object_name,object_type,host,sid):
            print('Object ' + object_name + ' already exists in Check Point database.')
        else:
            netobjects.append(object_name)
            api_command = 'add-host'
            payload = { "name" : object_name, "ip-address" : object_addr, "comments" : comments }
            new_object = True
    else:
        # this is a network object
        object_name = 'net' + '_' + str(split_object[0]) + '_' + str(split_object[1])
        object_addr = str(split_object[0])
        object_mask = str(split_object[1])
        object_type = 'network'
        if object_exists(object_name,object_type,host,sid):
            print('Object ' + object_name + ' already exists in Check Point database.')
        else:
            netobjects.append(object_name)
            api_command = 'add-network'
            payload = { "name" : object_name, "subnet" : object_addr, "mask-length" : object_mask, "comments" : comments }
            new_object = True
    # create new object
    if new_object:
        response = api_call(host,api_command,payload,sid)
        if str(response[0]) == '200':
            print('Created object: ', object_name)
            new_obj_count += 1
        else:
            print('Unknown response:')
            print(json.dumps(response[1]))

# publish if new object count > 0
if new_obj_count > 0:
    print('Publishing.', end='')
    response = api_call(host, 'publish', {}, sid)
    task_id = response[1]['task-id']
    payload = { "task-id" : task_id, "details-level" : "full" }
    task_status = ''
    while not (task_status == 'succeeded'):
        time.sleep(1)
        print('.', end='')
        response = api_call(host,'show-task',payload,sid)
        task_status = response[1]['tasks'][0]['status']
    print('.Done')
else:
    print('No objects created.')

#################
### end main section
##################

# be nice and log out
logout_result = api_call(host, "logout",{},sid)
logout_message = logout_result[1]['message']
if logout_message != 'OK':
    print('Logout unsuccessful.')