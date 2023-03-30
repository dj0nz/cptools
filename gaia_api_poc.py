#!/usr/bin/python3
#
# checkpoint python api example and poc
# 
# this is a modified example from the check point gaia api reference documentation
# https://sc1.checkpoint.com/documents/latest/GaiaAPIs/#ws~v1.7%20
# 
# had to remove typos first. then removed hard coded credentials. instead, i use
# netrc (https://everything.curl.dev/usingcurl/netrc) which is supported natively
# with netrc module.
#
# achtung: this is just a python api example without proper input/output checking 
# and with limited practical use (same information could be obtained with a bash onliner)!
#
# dj0Nz mar 2023

import requests, json, netrc

# next two lines needed to suppress warnings if self signed certificates are used
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

# modified api_call function. typos and hardcoded stuff removed
def api_call(ip_addr, command, json_payload, sid):
    url = 'https://' + ip_addr + '/gaia_api/' + command
    if sid == '':
        request_headers = {'Content-Type' : 'application/json'}
    else:
        request_headers = {'Content-Type' : 'application/json', 'X-chkp-sid' : sid}
    r = requests.post(url,data=json.dumps(json_payload), headers=request_headers, verify = False)
    return r.json()

# login function. self explaining.
def api_login(ip_addr,user,password):
    payload = {'user':user, 'password' : password}
    response = api_call(host,'login',payload,'')
    return response["sid"]

# check point gateway and route to query 
host = '192.168.1.2'
route = '192.168.100.0/24'

# get login credentials from .netrc file
auth = netrc.netrc('./.netrc')
token = auth.authenticators(host)
user = token[0]
password = token[2]

# get ip / mask separated for api call
dest_ip = route.split('/')[0]
dest_mask = route.split('/')[1]

# get session id needed to authorize api call
sid = api_login(host,user,password)

# request route with api
request_data = {"address": dest_ip, "mask-length": dest_mask}
get_route_result = api_call(host, 'show-static-route', request_data, sid)

# scratch next hop ip from response data
gateway = get_route_result['next-hop'][0]['gateway']

print(gateway)

# be nice and log out
logout_result = api_call(host, "logout",{},sid)
logout_message = logout_result['message']
if logout_message != 'OK':
    print('Logout unsuccessful.')
