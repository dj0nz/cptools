#!/bin/bash

# This script has to be run on a Check Point firewall management server
# It does:
#
# - query Check Point database for gateways and store their names and ips in an array
# - use CPRID to copy a local script to every gateway
# - use CPRID to execute this script locally on all gateways in the list
# 
# A script file is needed on the management server at $CHANGE_SCRIPT location with following contents:
# 
# <code>
# #!/bin/bash
# cp /web/templates/httpd-ssl.conf.templ /web/templates/httpd-ssl.conf.templ_ORIGINAL
# sed -i 's/^SSLCipherSuite.*/SSLCipherSuite ECDHE-RSA-AES256-SHA384:AES256-SHA256:!ADH:!EXP:RSA:+HIGH:!MEDIUM:!MD5:!LOW:!NULL:!SSLv2:!eNULL:!aNULL:!RC4:!SHA1/' /web/templates/httpd-ssl.conf.templ
# sed -i 's/^SSLProtocol.*/SSLProtocol +TLSv1.2 +TLSv1.3/' /web/templates/httpd-ssl.conf.templ
# /bin/template_xlate : /web/templates/httpd-ssl.conf.templ /web/conf/extra/httpd-ssl.conf < /config/active
# tellpm process:httpd2
# tellpm process:httpd2 t
# </code>
# 
# See https://support.checkpoint.com/results/sk/sk147272 for explanation
#
# To check ciphers afterwards, use the ciphercheck script.
# dj0Nz jun 2023

# Load Check Point environment vars
. /etc/profile.d/CP.sh

# The Check Point Remote Installation Daemon. Nice tool. Listens on 18208/tcp, authenticates with SIC certificate.
PORT=18208

# Script with content shown above. Should exist in the named directory.
CHANGE_SCRIPT=/home/admin/gw-cipher-mod.sh
if [[ ! -f $CHANGE_SCRIPT ]]; then
    echo "Change script not found. Exiting."
    exit 1
fi

# Get list of gateways, add name and ip address to list (in csv format)
GW_LIST+=($(mgmt_cli -r true show gateways-and-servers details-level full -f json | jq -r '.objects[] | select ((."type" == "cluster-member") or (."type" == "simple-gateway")) | [.["name"], .["ipv4-address"]] | @csv' | tr -d '"'))

# Loop through gateway list and do the cipher-change-stuff...
for GW in "${GW_LIST[@]}"; do
    # Split gateway name / ip
    GW_IP=$(echo $GW | cut -d ',' -f2)
    GW_NAME=$(echo $GW | cut -d ',' -f1)
    # Check if CPRID port open
    OPEN=`timeout 3 bash -c "</dev/tcp/$GW_IP/$PORT" 2>/dev/null && echo "Open" || echo "Closed"`
    if [[ "$OPEN" = "Open" ]]; then
        printf "%-10s %s\n" "$GW_NAME: " "Changing SSL/TLS ciphers"
        # copy local script to remote machine and execute. Check ciphers afterwards and smile.
        $CPDIR/bin/cprid_util -server $GW_IP putfile -local_file $CHANGE_SCRIPT -remote_file $CHANGE_SCRIPT -perms 700 > /dev/null
        $CPDIR/bin/cprid_util -server $GW_IP -verbose rexec -rcmd $CHANGE_SCRIPT > /dev/null   
    else
        printf "%-10s %s\n" "$GW_NAME: " "Unreachable"
    fi
done
