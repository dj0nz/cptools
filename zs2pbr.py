#!/usr/bin/python3

# python program to create source routing command to source-route zscaler ipv4 hubs via specific gateway in checkpoint gaia
#
# purpose: let clients in your network have their surf traffic routed via a separate internet connection to get more 
# bandwidth for your business critical applications.
#
# zscaler hubs: https://config.zscaler.com/zscaler.net/hubs
# checkpoint admin guide: https://sc1.checkpoint.com/documents/R81.20/WebAdminGuides/EN/CP_R81.20_Gaia_Advanced_Routing_AdminGuide/Content/Topics-GARG/Policy-Based-Routing-Configuring-in-Gaia-Clish.htm
#
# cannot be run on gateway itself because requests module is missing there
# just run it on any linux machine, scp output to your gateways and deploy with clish -f
# use updatable object "zscaler services" in your access rules
#
# dj0Nz oct 2024

import json, ipaddress, requests

# function to check if input is a valid ipv4 address or network
def is_ipv4(input_address):
    try:
        valid_addr = ipaddress.IPv4Address(input_address)
        return True
    except:
        try:
            valid_net = ipaddress.IPv4Network(input_address)
            return True
        except:
            return False

# output file containing gaia clish commands
output_file = 'pbr.cfg'

# next hop gateway for zscaler access
zs_gateway = '192.168.1.1'

# zscaler client network
zs_clients = '192.168.88.0/24'

# zscaler routing table name
table_name = 'zscaler'

# api requests url
zs_api_url = 'https://api.config.zscaler.com/zscaler.net/hubs/cidr/json/recommended'

# if proxy is needed to pull the hub list, put it here. empty ('') if no proxy.
# see https://requests.readthedocs.io/en/latest/api/#id1
http_proxy = 'http://192.168.10.10:8080'
proxies = { 'http' : http_proxy, 'https' : http_proxy, 'ftp' : http_proxy }

print()
print('Fetching zscaler hubs and preparing pbr rules...')
# get zscaler hubs
try:
    if http_proxy:
        response = requests.get(zs_api_url, proxies=proxies)
    else:
        response = requests.get(zs_api_url)
except:
    print('Cant connect to zscaler api service. Check url.')
    quit()

# extract ipv4 hub prefixes from json response
resp_json = response.json()
hub_prefixes = [ hub for hub in resp_json['hubPrefixes'] if is_ipv4(hub) ]

print()
# write commands to file
with open(output_file,'w') as file:
    # create zscaler route table
    file.write('set pbr table ' + table_name + ' static-route default nexthop gateway address ' + str(zs_gateway) + ' on\n')
    route_prio = 1
    # create routing rules
    for hub in hub_prefixes:
        file.write('set pbr rule priority ' + str(route_prio) + ' match from ' + str(zs_clients) + '\n')
        file.write('set pbr rule priority ' + str(route_prio) + ' to ' + str(hub) + '\n')
        route_prio += 1

print('Done. Clish commands in ' + output_file)
print('Copy file to gateway(s) and import config with "clish -f ' + output_file + ' -s"')
print()
