#!/usr/bin/python3

# Check Point web api script, that shows object from given name
# Purpose: Testing behaviour of the show_objects api call
# Doc: https://sc1.checkpoint.com/documents/latest/APIs/index.html?#web/
# dj0Nz feb 2024

# modules needed to query mgmt api, parse input and format output 
import os, requests, json, netrc, re, sys, socket

# next two lines needed to suppress warnings if self signed certificates are used
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

##################
# Variables

# Check Point management server and netrc file, which holds credentials.
# See https://everything.curl.dev/usingcurl/netrc for netrc documentation
host = '192.168.1.11'
auth_file = '/home/api/.netrc'

# Check netrc file, quit if not there
exists = os.path.isfile(auth_file)
if not exists:
    quit('Credentials file not found.')

# End variables section
##################

##################
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
        quit('Host not found in netrc file.')
    # do login
    payload_local = {'user':user, 'password' : password}
    response = api_call(cp_mgmt,'login',payload_local,'')
    if str(response[0]) == '200':
        return response[1]["sid"]
    else:
        return 'Login error'

# End functions section
##################

##################
### main program

# check if management server reachable, quit if not
if not port_open(host,443):
    quit('Management unrechable.')

# get session id needed to authorize api call
sid = api_login(host,auth_file)
if sid == 'Login error':
    quit('Login error.')

# get search pattern from command line
try:
    input = sys.argv[1]
except IndexError:
    quit('No input.')

# see api documentation for explanation of limit and offset settings. below values for them are defaults. 
# you may use regex elements in the filter expression on the command line (e.g. ^searchpattern$) for exact matching
payload = { 
  "limit" : 5, 
  "offset" : 0, 
  "filter" : input 
}

# issue api call and store response elements (0 = response code, 1 = data)
response = api_call(host, 'show-objects', payload, sid)
limit = payload['limit']
if str(response[0]) == '200':
    total = response[1]['total']
    if total == 1:
        print(json.dumps(response[1]['objects'][0], indent=2))
    elif total == 0:
        print('No objects matching search pattern (\"' + input + '\")', sep='')
    elif total > limit:
        print('Request returned ' + str(total) + ' elements, which is more than the currently configured limit (' + str(limit) + ').', sep='')
    else:
        print('There are ' + str(total) + ' objects matching search pattern (\"' + input + '\"):', sep='')
        num = 0
        while num < total:
            object_name = json.dumps(response[1]['objects'][num]['name']).strip('"')
            print(object_name)
            num = num +1
else:
    print('Unknown response:') 
    print(json.dumps(response[1], indent=2))


### end main program
##################

##################
# be nice and log out
logout_result = api_call(host, "logout",{},sid)
logout_message = logout_result[1]['message']
if logout_message != 'OK':
    print('Logout unsuccessful.')
