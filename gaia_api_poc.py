#!/usr/bin/python3
#
# checkpoint python api example and poc
# 
# this is just an example script. the source example is taken from the check point 
# gaia api reference documentation at https://sc1.checkpoint.com/documents/latest/GaiaAPIs/#ws~v1.7%20
# 
# had to remove typos first. then removed hard coded credentials. instead, i use
# netrc (https://everything.curl.dev/usingcurl/netrc) which is supported natively
# with netrc module.
#
# achtung: this is just some kind of poc with just basic input/output checking 
# and limited practical use (same information could be obtained with a bash oneliner)!
# also, the check point gaia api call to get a specific route has its flaws:
#
# - the show-static-route call returns an error if the requested route is not explicitly set.
#   this is wrong. there is always a route if there is a default gateway.
#
# - the show-static-route call does not return the outgoing interface,  
#   which significantly limits the usefulness of this api call
#
# conclusion: better use bash scripts via ssh/cpridutil in this specific case but maybe
# some code fragments are useful for other tasks...
#
# dj0Nz mar 2023

import os, requests, json, netrc, ipaddress

# next two lines and "verify = False" in request needed to suppress warnings if self signed certificates are used
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
    status_code = r.status_code
    return [status_code, r.json()]

# login function. self explaining.
def api_login(ip_addr,user,password):
    payload = {'user':user, 'password' : password}
    response = api_call(host,'login',payload,'')
    if str(response[0]) == '200':
        return response[1]["sid"]
    else:
        return 'Login error'

# check point gateway and route to query 
host = '192.168.1.2'
route = '192.168.100.0/24'

# check credentials file
auth_file = '.netrc'
exists = os.path.isfile(auth_file)
if not exists:
    quit('Credentials file not found. Exiting.')

# get login credentials from .netrc file
auth = netrc.netrc(auth_file)
token = auth.authenticators(host)
if token:
    user = token[0]
    password = token[2]
else:
    quit('Host not found in netrc file. Exiting.')

# get ip / mask separated for api call
ip = ipaddress.IPv4Network(route)
dest_ip = str(ip.network_address)
dest_mask = str(ip.prefixlen)

# get session id needed to authorize api call
sid = api_login(host,user,password)
if sid == 'Login error':
    quit('Login error. Exiting.')

# request route with api
request_data = {"address": dest_ip, "mask-length": dest_mask}
get_route_result = api_call(host, 'show-static-route', request_data, sid)

if str(get_route_result[0]) == '200':
    # scratch next hop ip from response data
    gateway = get_route_result[1]['next-hop'][0]['gateway']
    print(gateway)
else:
    print('No explicit routing')

# be nice and log out
logout_result = api_call(host, "logout",{},sid)
logout_message = logout_result[1]['message']
if logout_message != 'OK':
    print('Logout unsuccessful.')
