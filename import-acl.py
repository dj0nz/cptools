#!/usr/bin/python3

# Import Cisco acls and objects exported with parse-acl.py to Check Point database
# dj0Nz mar 2024

# Modules needed to query mgmt api, parse input and format output 
import ast, os, requests, json, netrc, re, sys, socket, time

# Next two lines needed to suppress warnings if self signed certificates are used
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

##########
# Variables

# Check Point management server - has to be reachable (https) or this program will exit soon...
host = '192.168.1.11'
# The netrc file holds credentials for the Check Point management server
# See https://everything.curl.dev/usingcurl/netrc for syntax and other information
auth_file = '/home/api/api/.netrc'

# Check credentials file, quit if not there
exists = os.path.isfile(auth_file)
if not exists:
    quit('Credentials file not found. Exiting.')

# Input files:
# - netobjects.txt holds network objects exported with parse-acl.py
# - rules.txt has the Cisco ACLs
# - services.json is manually created and has a kind of conversion table i
#   between Cisco and Check Point service names. Self-Explaining. ;)
objects_in = 'netobjects.txt'
rules_in = 'rules.txt'
service_replace = 'services.json'

# Lists for network objects and rules
# - service_table: List object for the service conversion table
# - net2cp_table:  Cisco to Check Point object conversion table. Because you don't use names 
#                  in Cisco ACLs, a Check Point object gets created from IP and subnet mask
# - netobjects_in: List temporarily needed for object creation 
# - netobjects:    List that finally holds host and network objects
# - rules:         Thats (surprise, surprise) the rules list
service_table = []
net2cp_table = []
netobjects_in = []
netobjects = []
rules = []

# Shared layer for migrated rules
# The idea behind is, to create all rules in a separate but shared layer in order to prevent 
# interferences with existing rules. Obviously, needs to be improved if amount of ACLs is high 
# but mostly, there are no more than 200-300 ACLs if any.
layer_name = 'Core'

# Comment for every newly created object, also for firewall rules and layers
comments = 'Migrated from Cisco ACL'

# End variables section
##########

##########
# Functions

# Check if https to management is working (port 443 open)
def port_open(ip,port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.settimeout(1)
        sock.connect((ip, int(port)))
        return True
    except:
        return False

# The main function: Do web_api call and return json structure to work on
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

# Check if service exists in Check Point database
def service_exists(service_local,type_local,host_local,sid_local):
    if type_local == 'tcp':
        api_command = 'show-services-tcp'
    else:
        api_command = 'show-services-udp'
    payload_local = { "filter" : service_local }
    response_local = api_call(host_local,api_command,payload_local,sid_local) 
    if str(response_local[0]) == '200':
        total = response_local[1]['total']
        if total > 0:
            return(True)
        else:
            return(False)
    else:
        print(response[1])
        quit('Unknown response in api call')

##################
## main section
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
# A comment (see variables) will be added in order to better identify newly created objects in Object Explorer.
#
# Second: Create internal table (net2cp_table) to assign netobject to checkpoint-object names for easier rule creation
# Acl names are in line[0], Check Point object names in line[1]
#
# Third: Create shared layer for imported access rules and create access rules in there
# by reading and interpreting rules file line by line. Rules will also get the same comment as objects.

print('Importing network and host objects...')

# Check if object exists, create, if not
# Note: There is no syntax checking of ip addresses. This is done already in the export script (parse-acl.py) 
objects_skipped = 0
for netobject in netobjects_in:
    # check if host or network object, check if already present, tag if not
    new_object = False
    # init net2cp table entry
    net2cp = []
    split_object = netobject.split('/')
    net2cp.append(netobject)
    if split_object[1] == '32':
        # this is a host object
        object_name = 'host' + '_' + str(split_object[0])
        object_addr = str(split_object[0])
        object_type = 'host'
        if object_exists(object_name,object_type,host,sid):
            objects_skipped += 1
            net2cp.append(object_name)
        else:
            netobjects.append(object_name)
            api_command = 'add-host'
            payload = { "name" : object_name, "ip-address" : object_addr, "comments" : comments }
            new_object = True
            net2cp.append(object_name)
    else:
        # this is a network object
        object_name = 'net' + '_' + str(split_object[0]) + '_' + str(split_object[1])
        object_addr = str(split_object[0])
        object_mask = str(split_object[1])
        object_type = 'network'
        if object_exists(object_name,object_type,host,sid):
            objects_skipped += 1
            net2cp.append(object_name)
        else:
            netobjects.append(object_name)
            api_command = 'add-network'
            payload = { "name" : object_name, "subnet" : object_addr, "mask-length" : object_mask, "comments" : comments }
            new_object = True
            net2cp.append(object_name)
    # create new object
    if new_object:
        response = api_call(host,api_command,payload,sid)
        if str(response[0]) == '200':
            new_obj_count += 1
            net2cp_table.append(net2cp)
        else:
            print('Unknown response:')
            print(json.dumps(response[1]))
    else:
        net2cp_table.append(net2cp)

# publish if new object count > 0
if new_obj_count > 0:
    print('Publishing objects...')
    response = api_call(host, 'publish', {}, sid)
    task_id = response[1]['task-id']
    payload = { "task-id" : task_id, "details-level" : "full" }
    task_status = ''
    while not (task_status == 'succeeded'):
        time.sleep(1)
        response = api_call(host,'show-task',payload,sid)
        task_status = response[1]['tasks'][0]['status']
    if objects_skipped > 0:
        print('Objects skipped: ', str(objects_skipped))
else:
    print('No objects created.')

# Read service replacement table from file
with open(service_replace) as file:
    service_table = json.load(file)

# open rules.txt in a list removing line feeds and do data format magic with ast because
# lines in rules.txt already has list format (['item','item']). Pretty sure this could be done much easier...     
with open(rules_in) as file:
    rules_raw=file.read().splitlines()
rules = [ast.literal_eval(line) for line in rules_raw]

# create shared layer
payload = { }
response = api_call(host, 'show-access-layers', payload, sid)
if str(response[0]) == '200':
    access_layers = response[1]['access-layers']
    layer_name_check = False
    for check_layer in access_layers:
        if check_layer['name'] == layer_name:
            layer_name_check = True
    if layer_name_check:
        print('Layer ' + layer_name + ' already created, skipping.')
    else:
        payload = { "name" : layer_name, "shared" : "true", "comments" : comments }
        print('Creating shared layer...')
        response = api_call(host, 'add-access-layer', payload, sid)
        if str(response[0]) == '200':
            response = api_call(host, 'publish', {}, sid)
            task_id = response[1]['task-id']
            payload = { "task-id" : task_id, "details-level" : "full" }
            task_status = ''
            while not (task_status == 'succeeded'):
                response = api_call(host,'show-task',payload,sid)
                task_status = response[1]['tasks'][0]['status']
        else:
            print(response[1]['message'])
else:
    print(response[1]['message'])

# loop through rules and create firewall rules
rule_count = 0
dummy_count = 0
skipped_count = 0
print('Creating firewall rules...')
for rule in rules:
    # Get source and destination, common for all kinds of rules
    if rule[1] == 'any':
        src = 'Any'
    else:
        for line in net2cp_table:
            if rule[1] == line[0]:
                src = line[1]
    if rule[2] == 'any':
        dst = 'Any'
    else:
        for line in net2cp_table:
            if rule[2] == line[0]:
                dst = line[1]
    # First: IP Any rules
    if rule[0] == 'ip':
        if rule[4] == 'accept':
            action = 'Accept'
        else:
            action = 'Drop'
        payload = { 
            "layer" : layer_name, 
            "position" : "bottom", 
            "action" : action, 
            "destination" : dst,
            "service" : "Any",
            "source" : src,
            "track" : { "type" : "Log" },
            "comments" : comments
        }    
        response = api_call(host, 'add-access-rule', payload, sid)
        if str(response[0]) == '200':
            rule_count += 1
        else:
            print('Rule creation failed', str(rule))
    elif rule[0] == 'icmp':
        if rule[4] == 'accept':
            action = 'Accept'
        else:
            action = 'Drop'
        if rule[3] == 'any':
            service = 'icmp-proto'
        else:
            try:
                service = service_table[str(rule[3])]
            except KeyError:
                skipped_count += 1
                continue
        payload = {
            "layer" : layer_name,
            "position" : "bottom",
            "action" : action,
            "destination" : dst,
            "service" : service,
            "source" : src,
            "track" : { "type" : "Log" },
            "comments" : comments
        }
        response = api_call(host, 'add-access-rule', payload, sid)
        if str(response[0]) == '200':
            rule_count += 1
        else:
            print('Rule creation failed', str(rule))
    elif rule[0] in ('tcp', 'udp'):
        if rule[5] == 'accept':
            action = 'Accept'
        else:
            action = 'Drop'
        if rule[3] == 'eq':
            try:
                service = service_table[str(rule[4])]
            except KeyError:
                skipped_count += 1
                continue
        # Skip rules with service any and protocol set. There is no firewalling use case for that. 
        elif rule[4] == 'any':
            skipped_count += 1
            continue
        else:
            skipped_count += 1
            continue
        payload = {
            "layer" : layer_name,
            "position" : "bottom",
            "action" : action,
            "destination" : dst,
            "service" : service,
            "source" : src,
            "track" : { "type" : "Log" },
            "comments" : comments
        }
        response = api_call(host, 'add-access-rule', payload, sid)
        if str(response[0]) == '200':
            rule_count += 1
        else:
            print('Rule creation failed', str(rule))
    else:
        print('unknown service')
if rule_count > 0:
    print('Publish rules...')
    response = api_call(host, 'publish', {}, sid)
    task_id = response[1]['task-id']
    payload = { "task-id" : task_id, "details-level" : "full" }
    task_status = ''
    while not (task_status == 'succeeded'):
        time.sleep(1)
        response = api_call(host,'show-task',payload,sid)
        task_status = response[1]['tasks'][0]['status']
    if skipped_count > 0:
        print('Skipped rules:', str(skipped_count))
 
#################
### end main section
##################

# be nice and log out
logout_result = api_call(host, "logout",{},sid)
logout_message = logout_result[1]['message']
if logout_message != 'OK':
    print('Logout unsuccessful.')
