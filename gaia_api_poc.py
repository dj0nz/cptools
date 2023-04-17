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
# conclusion: use the show-routes-static call and query the complete routing table for destination
#
# dj0Nz apr 2023

import os, requests, json, netrc

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

# get session id needed to authorize api call
sid = api_login(host,user,password)
if sid == 'Login error':
    quit('Login error. Exiting.')

# request routing table with api
get_route_result = api_call(host, 'show-routes-static', {}, sid)

# check web server response
if str(get_route_result[0]) == '200':
    static_routes = get_route_result[1]['objects']
    num=len(static_routes)
    found = False
    # query json structure to find route
    for index in range(0, num):
        dest = str(static_routes[index].get('address'))
        mask = str(static_routes[index].get('mask-length'))
        gateway = str(static_routes[index].get('next-hop').get('gateways')[0].get('address'))
        interface = str(static_routes[index].get('next-hop').get('gateways')[0].get('interface'))
        # note default gateway for future use
        if dest == '0.0.0.0':
            def_gw = gateway
            def_if = interface
        else:
            ip = dest + '/' + mask
            if ip == route:
                found = True
else:
    print('Failed to get static routes')

# output - just for testing/validating
if found:
    print(f'static route for dst {route} via {gateway} dev {interface} found')
else:
    print(f'dst {route} routed via default gateway {def_gw} dev {def_if}')

# be nice and log out
logout_result = api_call(host, "logout",{},sid)
logout_message = logout_result[1]['message']
if logout_message != 'OK':
    print('Logout unsuccessful.')
