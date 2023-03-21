## My private Check Point knowledge base ##

Scripts I used at work.

### [add-gw-hostnames.sh](add-gw-hostnames.sh)
Uses mgmt_cli to fetch names and IPs of gateways or cluster members from Check Point database and creates host name entries. 

### [backup-gaia-mgmt.sh](backup-gaia-mgmt.sh)
Enhanced management server backup. Does backup AND export, adds version info, gaia config and some directories to a tgz and copies the bundle using scp to a given backup server.

### [check_ssl_ciphers.sh](check_ssl_ciphers.sh)
Uses cpopenssl to quick-check ciphers on a given IP address

### [create_broadcast_objects.sh](create_broadcast_objects.sh)
Ever had to create a network group containing broadcast objects on a gateway with 100+ VLAN interfaces? This is for you. ;)

### [grid-import.sh](grid-import.sh)
Get networks from Infoblox Grid Containers and create corresponding network objects in Check Point database. Uses REST API calls. Sort of POC.

### [gw-config-backup.sh](gw-config-backup.sh)
Small script that runs on Check Point management server. Uses cprid_util to get Gaia config from all managed gateways and store the locally. Use together with the backup-gaia-mgmt script to have an almost complete backup of your Check Point environment.

### [logwork.sh](logwork.sh)
The Logwork Orange (“Welly, welly, welly, welly, welly, welly, well. To what do I owe the extreme pleasure of this surprising visit?” - Anthony Burgess, A Clockwork Orange) script deletes old log files. Check Point version and retention time adjustable.

### [topocalc.sh](topocalc.sh)
Quick-Check cluster topology.

### [move-to-bond.sh](move-to-bond.sh)
Move existing VLAN interface from any eth (bond, tun, whatever) to a newly created bond interface. Avoids copy-paste-issues. Runs on gateway(s)

### [move-to-bond-mgmt.sh](move-to-bond-mgmt.sh)
Modify cluster topology before moving VLANs to bond interface. Runs on management server.
