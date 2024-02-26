#!/usr/bin/python3

# Export access rules from Check Point Management to a json file
# To view a single rule, use following syntax (replace placeholders):
# jq -r '."rulebase"[]|select(."name" == "$RULE")' $FILE
# dj0Nz feb 2024

# modules needed
import os, requests, json, netrc, re, sys, socket

# next two lines needed to suppress warnings if self signed certificates are used
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

# check point management server
host = '192.168.1.11'

# Rulebase to show and file to write to
# To find out rule name, use the "show-access-layers" api call and filter output like that: jq -r '."access-layers"[]|.name'
export_rulebase = 'gw1_policy Network'
output_file = 'rulebase.json'

# Local credentials (.netrc file) for authenticating requests
auth_file = '/home/api/api/.netrc'
exists = os.path.isfile(auth_file)
if not exists:
    quit('Credentials file not found. Exiting.')

# check if port open
def port_open(ip,port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.settimeout(1)
        sock.connect((ip, int(port)))
        return True
    except:
        return False

# api_call function
# do web_api call and return json structure to work on
def api_call(ip_addr, command, json_payload, sid):
    url = 'https://' + ip_addr + '/web_api/' + command
    if sid == '':
        request_headers = {'Content-Type' : 'application/json'}
    else:
        request_headers = {'Content-Type' : 'application/json', 'X-chkp-sid' : sid}
    r = requests.post(url,data=json.dumps(json_payload), headers=request_headers, verify = False)
    status_code = r.status_code
    return [status_code, r.json()]

# login function.
# read netrc file and extract credentials for host if any
# then do login and return sid or login error
def api_login(ip_addr):
    # get login credentials from .netrc file
    auth = netrc.netrc(auth_file)
    token = auth.authenticators(host)
    if token:
        user = token[0]
        password = token[2]
    else:
        quit('Host not found in netrc file.')
    # do login
    payload = {'user':user, 'password' : password}
    response = api_call(ip_addr,'login',payload,'')
    if str(response[0]) == '200':
        return response[1]["sid"]
    else:
        return 'Login error'

##################
### main section
##################

# get session id needed to authorize api call
if port_open(host,443):
    sid = api_login(host)
    if sid == 'Login error':
        quit('Login error.')
else:
    quit('Management unrechable.')

# define payload data for the api call
payload = {
  "offset" : 0,
  "limit" : 500,
  "name" : export_rulebase,
  "details-level" : "standard",
  "use-object-dictionary" : "true"
}

# finally, get policy and write it to file
response = api_call(host, 'show-access-rulebase', payload, sid)
if str(response[0]) == '200':
    rulebase = json.dumps(response[1], indent=2)
    with open(output_file, 'w') as file:
        file.write(rulebase)

##################
### end main section
##################

# be nice and log out
logout_result = api_call(host, "logout",{},sid)
logout_message = logout_result[1]['message']
if logout_message != 'OK':
    print('Logout unsuccessful.')
~
