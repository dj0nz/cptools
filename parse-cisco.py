#!/usr/bin/python3

# Python script to convert a named Cisco (IOS) ACL into Check Point Objects and Rules

####################
# WORK IN PROGRESS #
####################

# Attention: Due to the different nature of the filter logic on Cisco devices and Check Point firewalls,
# it is absolutely mandatory to manually verify the access rules produced by this script 
# before activating them in production environments. Some of them may even not work at all.

# dj0Nz Mar 2024

import re, ipaddress, json

# Input: Cisco Extended ACL, named
infile = 'acl.txt'

# Output files (should ;)) contain Check Point API commands to import objects or rules 
objects_out = 'network-objects.txt'
rules_out = 'rules.txt'

# Lists for network objects and rules
ciscoacls_filtered = []
netobjects = []
rules = []

# Regex pattern to filter unneeded rules
established_pattern = re.compile('established')
ospf_pattern = re.compile('ospf')

# Regex pattern to identify wildcard masks
wildcard_pattern = re.compile('^0\\.')

# Function: Valid IPv4 address?
def is_ipv4(input_address):
    try:
        valid_ip = ipaddress.IPv4Address(input_address)
        return True
    except:
        return False

# Function: Convert wildcard mask to prefix length
def convert_wildcard (wildcardmask):
    prefixlen=str(ipaddress.IPv4Address._prefix_from_ip_int(int(ipaddress.IPv4Address(wildcardmask))^(2**32-1)))
    return(prefixlen)

# Function: Get source and destination for rule
def get_src_dst (acl_local,netobjects_local):

    # Get source from netobjects list or any
    src_local = ''
    if acl_local[2] == 'any':
        src_local = 'any'
    elif acl_local[2] == 'host':
        num=len(netobjects_local)
        for index in range(0, num):
            found = re.search(rf'^{acl_local[3]}',netobjects_local[index])
            if found:
                src_local = netobjects_local[index]
    else:
        num=len(netobjects_local)
        for index in range(0, num):
            found = re.search(rf'^{acl_local[2]}',netobjects_local[index])
            if found:
                src_local = netobjects_local[index]

    # Get destination from netobjects list
    dst_local = ''
    if acl_local[2] == 'any':
        if acl_local[3] == 'host':
            num=len(netobjects_local)
            for index in range(0, num):
                found = re.search(rf'^{acl_local[4]}',netobjects_local[index])
                if found:
                    dst_local = netobjects_local[index]
        elif acl_local[3] == 'any':
            dst_local = 'any'
        else:
            num=len(netobjects_local)
            for index in range(0, num):
                found = re.search(rf'^{acl_local[3]}',netobjects_local[index])
                if found:
                    dst_local = netobjects_local[index]
    else:
        if not acl_local[4] == 'any':
            num=len(netobjects_local)
            if acl_local[4] == 'host':
                dest_search = acl_local[5]
            else:
                dest_search = acl_local[4]
            for index in range(0, num):
                found = re.search(rf'^{dest_search}',netobjects_local[index])
                if found:
                    dst_local = netobjects_local[index]
        else:
            dst_local = 'any'

    # return values
    return(src_local,dst_local)

# Function: Convert Cisco ip acl to "any" rule
def create_ip_rule (name_local,acl_local,netobjects_local):

    rule_local = []

    # Set action based on acl[0]
    if acl_local[0] == 'permit':
        action = 'accept'
    else:
        action = 'drop'

    # This is an "ip any" ACL
    proto = 'ip'
    service = 'any'

    srcdst = get_src_dst(acl_local,netobjects_local)
    source = srcdst[0]
    destination = srcdst[1]

    rule_local=[proto,source,destination,service,action]
    return(rule_local)

# Function: Convert Cisco icmp acl
def create_icmp_rule (name_local,acl_local,netobjects_local):

    rule_local = []

    # Set action based on acl[0]
    if acl_local[0] == 'permit':
        action = 'accept'
    else:
        action = 'drop'

    # This is an icmp ACL, typecode defaults to any
    proto = 'icmp'
    service = 'any'

    srcdst = get_src_dst(acl_local,netobjects_local)
    source = srcdst[0]
    destination = srcdst[1]

    # get icmp type 
    if source == 'any':
        if destination == 'any':
            try: 
                service = acl_local[4]
            except IndexError:
                service = 'any'
        else:
            try: 
                service = acl_local[5]
            except IndexError:
                service = 'any'
    else:
        if destination == 'any':
            try: 
                service = acl_local[5]
            except IndexError:
                service = 'any'
        else:
            try: 
                service = acl_local[6]
            except IndexError:
                service = 'any'

    rule_local=[proto,source,destination,service,action]
    return(rule_local)

# Function: Convert Cisco tcp/udp acl
def create_tcpudp_rule(name_local,acl_local,netobjects_local):

    rule_local = []

    # Set action based on acl[0]
    if acl_local[0] == 'permit':
        action = 'accept'
    else:
        action = 'drop'

    # port defaults to any
    proto = acl[1]
    port = 'any'

    srcdst = get_src_dst(acl_local,netobjects_local)
    source = srcdst[0]
    destination = srcdst[1]

    # get service operator (eq,lt,gt,neq,range)
    if source == 'any':
        if destination == 'any':
            try:
                operator = acl_local[4]
                pos = 5
            except IndexError:
                port = 'any'
        else:
            try:
                operator = acl_local[5]
                pos = 6
            except IndexError:
                port = 'any'
    else:
        if destination == 'any':
            try:
                operator = acl_local[5]
                pos = 6
            except IndexError:
                port = 'any'
        else:
            try:
                operator = acl_local[6]
                pos = 7
            except IndexError:
                port = 'any'

    # set operator and port for output
    single_port = ['eq','lt','gt','neq']
    if operator == 'range':
        port = str(acl_local[pos]) + '-' + str(acl_local[pos+1])
    elif operator in single_port:
        port = str(acl_local[pos])
    else:
        operator = ''

    rule_local=[proto,source,destination,operator,port,action]
    return(rule_local)

# Function: Check for rule duplicate 
def is_dup(rule_local,rulebase_local):
    for rule_check in rulebase_local:
        if rule_check:
            if rule_local == rule_check:
                return(True)
    return(False)

# Funtion: Check if there is already a rule with same source and destination
def is_any_rule(rule_local,rulebase_local):
    for rule_check in rulebase_local:
        if rule_check[1] == rule_local[1]:
            if rule_check[2] == rule_local[2]:
                return(True)
        else:
            return(False)

# Open ACL file and read contents into list
with open(infile) as aclfile:
    ciscoacls = aclfile.readlines()

# Initialize num and skipped rules
num = 0
skipped = 0

####
# Object extraction and filtering
####

# Loop through file containing cisco acls, filter unwanted and collect network objects 
for line in ciscoacls:
    # Remove leading and trailing whitespace if any
    line.strip(' ')
    # Transform line to list
    acl = line.split()

    # This is a named access list, so first access-list line always contains name and no rules
    if acl[1] == 'access-list':
        acl_type = acl[2]
        rule_name = acl[3]
        continue

    # Skip standard acls for the moment...
    if acl_type == 'standard':
        continue

    ###
    # Begin filter section: Skip rules that cannot be translated properly

    # Delete log keyword
    last = acl[-1]
    if last == 'log':
        del acl[-1]
    # Acls for "established" connections
    established = re.search(established_pattern, line)
    if established:
        # removing list entry does not work reliably, check later
        # ciscoacls.remove(line)
        continue
    # Acls for ospf connections
    ospf = re.search(ospf_pattern, line)
    if ospf:
        continue
    # Source = any rules with source port set
    if acl[2] == 'any':
        if acl[3] == 'eq':
            continue
        if acl[3] == 'range':
            continue
    # Rules with source port and source host set 
    if acl[2] == 'host':
        if acl[4] == 'eq':
            continue
    # Any-Any rules ("permit ip any any")
    if len(acl) == 4:
        continue

    # End filter section 
    ####

    ####
    # Collect network objects

    # Loop through complete line
    num = len(acl)
    for index in range(0, num):
        # If host keyword found, next field is ip address
        if acl[index] == 'host':
            nextindex = index + 1
            # Check if valid ip address
            if is_ipv4(acl[nextindex]):
                # Check if hostobject already in list and add, if not
                hostobject = acl[nextindex] + '/32'
                hostcheck = netobjects.count(hostobject)
                if not hostcheck:
                    netobjects.append(hostobject)
        # Check if field is wildcard mask
        wildcard = re.search(wildcard_pattern, acl[index])
        # If yes, then previous field contains network address
        if wildcard:
            # Check if valid ipv4 address
            lastindex = index - 1
            if is_ipv4(acl[lastindex]):
                netobject = acl[lastindex] + '/' + convert_wildcard(acl[index]) 
                netcheck = netobjects.count(netobject)
                if not netcheck:
                    netobjects.append(netobject)

    # End of collect section
    ####

    # store filtered version of ciscoacls
    acl.append(rule_name)
    ciscoacls_filtered.append(acl)

####
# Rules section

# Loop through filterd acl, ip (src/dst/any) rules first
for acl in ciscoacls_filtered:
    if acl[1] == 'ip':
        rule = create_ip_rule(rule_name,acl,netobjects)
        # Dont export "any-rules"
        if 'any' in rule[1] and 'any' in rule[2] and 'any' in rule[3]:
            skipped += 1
        else:
            if is_dup(rule,rules):
                skipped += 1
            else:
                rules.append(rule)

# Cleanup - does not work on all acls - why?
for acl in ciscoacls_filtered:
    if acl[1] == 'ip':
        ciscoacls_filtered.remove(acl)

# Loop through filterd acl, extract icmp rules
for acl in ciscoacls_filtered:
    if acl[1] == 'icmp':
        rule = create_icmp_rule(rule_name,acl,netobjects)
        # Dont export "any-rules"
        if 'any' in rule[1] and 'any' in rule[2] and 'any' in rule[3]:
            skipped += 1
        else:
            # check if there is already an identical rule
            if is_dup(rule,rules):
                skipped += 1
            else:
                # check if there is already an ip-any rule with same source and destination
                if is_any_rule(rule,rules):
                    skipped += 1
                else:
                    # allowing echo-reply doesn't make sense in a stateful firewall
                    if 'echo-reply' in rule[3]:
                        skipped += 1
                    else:
                        rules.append(rule)

# Cleanup - does not work on all acls - why?
for acl in ciscoacls_filtered:
    if acl[1] == 'icmp':
        ciscoacls_filtered.remove(acl)

# Get tcp and udp rules
for acl in ciscoacls_filtered:
    if acl[1] == 'udp' or acl[1] == 'tcp':
        if acl[2] == 'any':
            if acl[3] == 'eq':
                skipped += 1
                continue
        elif acl[4] == 'eq':
            skipped += 1
            continue
        else:
            rule = create_tcpudp_rule(rule_name,acl,netobjects)
            # check if there is already an identical rule
            if is_dup(rule,rules):
                skipped += 1
            else:
                # check if there is already an ip-any rule with same source and destination
                if is_any_rule(rule,rules):
                    skipped += 1
                else:
                    rules.append(rule)

# Cleanup - does not work on all acls - why?
for acl in ciscoacls_filtered:
    if acl[1] == 'udp' or acl[1] == 'tcp':
        ciscoacls_filtered.remove(acl)

# End of rules section
####

####
# Output section
# Screen output of objects, rules and acls for manual verification purposes
# Will be same kind of json export in final version, maybe straight API commands with CP management...

# Check list contents
print('#######################################')
print('# Cisco to Check Point ACL Conversion #')
print('#######################################')
print()
print('Raw ACLs:')
print(*ciscoacls)
print('---------------')
print('Filtered ACLs:')
print(*ciscoacls_filtered, sep = '\n')
print('---------------')
print('Network objects:')
print(*netobjects, sep = '\n')
print('---------------')
print('Firewall rules:')
print(*rules, sep = '\n')
print('Skipped rules:',str(skipped))