## My private Check Point knowledge base ##

Scripts I used at work. I ask for your indulgence with the Python scripts, I'm not a programmer and still a first grade student with Python...

### [add-gw-hostnames.sh](add-gw-hostnames.sh)
Uses mgmt_cli to fetch names and IPs of gateways or cluster members from Check Point database and creates host name entries. 

### [backup-gaia-mgmt.sh](backup-gaia-mgmt.sh)
Enhanced management server backup. Does backup AND export, adds version info, gaia config and some directories to a tgz and copies the bundle using scp to a given backup server.

### [ciphercheck.sh](ciphercheck.sh)
Runs on a admin workstation and uses web api to query all gateway cluster members from management server, then openssl to check tls ciphers on all of them

### [cipherchange.sh](cipherchange.sh)
Runs on Check Point management server and uses mgmt API and CPRID to change tls ciphers on all mamaged firewall cluster members. Sorry for ignoring single gateways. xD

### [create_broadcast_objects.sh](create_broadcast_objects.sh)
Ever had to create a network group containing broadcast objects on a gateway with 100+ VLAN interfaces? This is for you. ;)

### [grid-import.sh](grid-import.sh)
Get networks from Infoblox Grid Containers and create corresponding network objects in Check Point database. Uses REST API calls. Early version of a bigger framework I wrote for a customer.

### [gw-config-backup.sh](gw-config-backup.sh)
Small script that runs on Check Point management server. Uses cprid_util to get Gaia config from all managed gateways and store the locally. Use together with the backup-gaia-mgmt script to have an almost complete backup of your Check Point environment.

### [logwork.sh](logwork.sh)
“Welly, welly, welly, welly, welly, welly, well. To what do I owe the extreme pleasure of this surprising visit?”    
-- Anthony Burgess, A Clockwork Orange
The Logwork Orange script deletes old log files. Check Point version and retention time adjustable.

### [miglog.sh](miglog.sh)
Bash script to migrate x days of log files to migrated log/management server. Cron-Run at night or other "non-busy" hours.

### [topocalc.sh](topocalc.sh)
Runs on management and checks whether cluster topology matches the routing table on the gateway.

### [compare-fingerprints.sh](compare-fingerprints.sh)
Compare LDAPS fingerprints in Check Point Account Unit with "real" LDAPS fingerprints from Domain Controllers

### [eth2bond-gw.sh](eth2bond-gw.sh)
Move existing VLAN interface from any eth (bond, tun, whatever) to a newly created bond interface. Avoids copy-paste-issues. Runs on gateway(s)

### [eth2bond-mgmt.sh](eth2bond-mgmt.sh)
Modify cluster topology before moving VLANs to bond interface. Runs on management server.

### [gaia_api_poc.py](gaia_api_poc.py)
Enhanced version of the web service example at the official Gaia API documentation page.

### [export-rulebase.py](export-rulebase.py)
Export given rulebase to json file. Part of bigger project.

### [parse-acl.py](parse-acl.py)
Parse Cisco IOS named ACL and store satinized objects and rules files. Part one of an "Build Check Point ruleset from Cisco ACLs" project.

### [import-acl.py](import-acl.py)
Part two: Read exported objects and rules and import them to a Check Port management as new shared layer (for easier integration in existing policies).

### [show-objects.py](show-objects.py)
Takes search pattern as command line argument and displays matching objects from management.
