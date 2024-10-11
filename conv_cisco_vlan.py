#!/usr/bin/env /usr/bin/python3

# Cisco-To-Checkpoint Interface Konverter
#
# Skript konvertiert Vlan Subinterfaces von einem Cisco Switch in die entsprechenden Check Point Gaia
# Kommandos zum Einsatz auf einem Cluster. Als Cluster-IP wird die Original-Adresse des Interfaces
# auf dem Switch verwendet, die Cluster Member bekommen die darauf folgenden beiden Adressen, die natürlich
# frei sein müssen.
#
# Als Eingabe-Datei wird eine Textdatei erwartet, die nur die Vlan-Subinterface-Konfigurationen
# enthält.
#
# Ausgabe sind zwei Text-Dateien ('outfiles'), die die entsprechenden Kommandos enthalten, mit denen die
# Interfaces an den Gateways angelegt werden. Diese werden als Subinterface auf dem in der Variable 'iface'
# spezifizierten Interface angelegt.
#
# Der zweite Teil des Skripts legt die Interfaces per API in dem Check Point Cluster Objekt auf dem Management
# Server an. Das muss bereits existieren, das versteht sich aber denk ich von selbst.
#
# Das Skript läuft auf einem beliebigen Linux-System, das per API auf den Check Point Management Server zugreifen
# darf (Firewall-Regeln und Eintrag in GUI-Clienst). Vielleicht läufts auch auf Windows aber das ist mir egal.
#
# Voraussetzungen:
# - Linux Client mit einigermaßen aktuellem Python Version 3
# - Firewall-Freischaltungen zwischen diesem System und dem Firewall Management (ssh und https)
# - Check Point Version R81.10 oder höher
# - Check Point Management API Version
# - Einen API-Key User mit Schreibrechten auf das Cluster-Objekt
# - Den API-Key in einer Datei (Variable 'keyfile'), eine Zeile, nur den Key

# dj0Nz Oct 2024

import ipaddress
import cpapi
import json

# Variablen
cp_mgmt = '192.168.102.161'
keyfile = '.cpapi.key'
cluster_name = 'cluster'

# Test-Daten!
infile = 'test-if.txt'
iface = 'eth1'
dhcp_one = '192.168.100.8'
dhcp_two = '192.168.100.9'

# Initial-Werte
iphelper = False
cisco_config = []

# API Login
sid = cpapi.login(cp_mgmt,keyfile)

# Cluster Member Namen ermitteln
command = 'show-simple-cluster'
payload = { 'name' : cluster_name, 'show-advanced-settings' : 'true' }
cluster_info = cpapi.call(cp_mgmt,command,payload,sid)[1]['cluster-members']
member1 = cluster_info[0]['name']
member2 = cluster_info[1]['name']

# Ausgabedatei = Member-Name
outfile1 = str(member1) + '.txt'
outfile2 = str(member2) + '.txt'
outfiles = [ outfile1, outfile2 ]

# Relevante Informationen aus der Cisco-Konfiguration kratzen
with open(infile, 'r') as file:
    for line in file:
        if line.startswith('interface'):
            vlan = line.strip('interface Vlan').strip()
            sub_if = iface + '.' + str(vlan)
        elif 'description' in line:
            description = line.strip('description ').strip()
        elif 'ip address' in line:
            address_line = line.split()
            ip = address_line[2]
            netmask = address_line[3]
        elif 'helper-address' in line:
            iphelper = True
        elif line.startswith('---'):
            interface_config = {
                "vlan" : vlan,
                "ip" : ip,
                "mask" : netmask,
                "desc" : description,
                "relay" : iphelper
            }
            cisco_config.append(interface_config)
            iphelper = False
            continue
        else:
            continue

# Ausgabe der Gaia Clish Skripte für die Interface-Konfiguration an den Gateways
for index, outfile in enumerate(outfiles, start=1):
    with open(outfile, 'w') as file:
        for num in range(len(cisco_config)):
            vlan = str(cisco_config[num]['vlan'])
            subif = iface + '.' + vlan
            ip_addr = ipaddress.IPv4Address(cisco_config[num]['ip']) + index
            file.write('add interface ' + iface + ' vlan ' + vlan + '\n')
            file.write('set interface ' + subif + ' state on\n')
            file.write('set interface ' + subif + ' ipv4-address ' + str(ip_addr) + ' subnet-mask ' + str(cisco_config[num]['mask']) + '\n')
            file.write('set interface ' + subif + ' comments ' + '"' + cisco_config[num]['desc'] + '"\n')
            if cisco_config[num]['relay']:
                file.write('set bootp interface ' + subif + ' on\n')
                file.write('set bootp interface ' + subif + ' relay-to ' + dhcp_one + ' on\n')
                file.write('set bootp interface ' + subif + ' relay-to ' + dhcp_two + ' on\n')
                file.write('set bootp interface ' + subif + ' primary ' + str(cisco_config[num]['ip']) + '\n')
            file.write('\n')

# Cluster Objekt modifizieren
command = 'set-simple-cluster'
for num in range(len(cisco_config)):
    vlan = str(cisco_config[num]['vlan'])
    subif = iface + '.' + vlan
    cluster_ip = cisco_config[num]['ip']
    member1_ip = str(ipaddress.IPv4Address(cisco_config[num]['ip']) + 1)
    member2_ip = str(ipaddress.IPv4Address(cisco_config[num]['ip']) + 2)
    subnet_mask = cisco_config[num]['mask']
    payload = {
                'name' : cluster_name,
                'interfaces' : {
                    'add' : {
                        'name' : subif,
                        'ip-address' : cluster_ip,
                        'ipv4-network-mask' : subnet_mask,
                        'interface-type' : 'cluster',
                        'topology' : 'internal',
                        'anti-spoofing' : 'true'
                    }
                },
                'members' : {
                    'update' : [ {
                        'name' : member1,
                        'interfaces' : {
                            'name' : subif,
                            'ipv4-address' : member1_ip,
                            'ipv4-network-mask' : subnet_mask
                        }
                    }, {
                        'name' : member2,
                        'interfaces' : {
                            'name' : subif,
                            'ipv4-address' : member2_ip,
                            'ipv4-network-mask' : subnet_mask
                        }
                    } ]
                }
            }
    resp = cpapi.call(cp_mgmt,command,payload,sid)
    if not str(resp[0]) == '200':
        print(json.dumps(resp[1], indent=2))

# Publish changes
resp = cpapi.publish(cp_mgmt,sid)
print(resp)

# API Logout
resp = cpapi.logout(cp_mgmt,sid)
if not resp == 'OK':
    print(resp)
