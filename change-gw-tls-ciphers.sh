#!/bin/bash

# This script has to be run on a Check Point firewall management server
# It does:
# - query Check Point database for gateway clusters 
# - query cluster objects for members and store their names and ips in an array
# - use CPRID to copy a local script to every gateway
# - use CPRID to execute this script locally on the gateway
# 
# The script file is needed on the management server at $CHANGE_SCRIPT location with following contents:
# <code>
# #!/bin/bash
# sed -i 's/^SSLCipherSuite.*/SSLCipherSuite ECDHE-RSA-AES256-SHA384:AES256-SHA256:!ADH:!EXP:RSA:+HIGH:!MEDIUM:!MD5:!LOW:!NULL:!SSLv2:!eNULL:!aNULL:!RC4:!SHA1/' /web/templates/httpd-ssl.conf.templ
# sed -i 's/^SSLProtocol.*/SSLProtocol +TLSv1.2 +TLSv1.3/' /web/templates/httpd-ssl.conf.templ
# /bin/template_xlate : /web/templates/httpd-ssl.conf.templ /web/conf/extra/httpd-ssl.conf < /config/active
# tellpm process:httpd2
# tellpm process:httpd2 t
# </code>
# 
# See https://support.checkpoint.com/results/sk/sk147272 for explanation
# dj0Nz jun 2023

# Load Check Point environment
. /etc/profile.d/CP.sh

# The Check Point Remote Installation Daemon. Nice tool. Listens on 18208/tcp. Authentication with SIC certificate.
PORT=18208
# Script with content shown above. Should exist in the named directory.
CHANGE_SCRIPT=/home/admin/change-ssl-ciphers.sh
if [[ ! -f $CHANGE_SCRIPT ]]; then
    echo "Change script not found. Exiting."
    exit 1
fi

# Get list of clusters
CLUSTERS=($(mgmt_cli -r true show simple-clusters --format json | jq -r '.objects[].name'))
for CLUSTER in "${CLUSTERS[@]}"; do
    # Add every cluster members name and ip address to list (in csv format)
    GW_LIST+=($(mgmt_cli -r true show simple-cluster name "$CLUSTER" --format json | jq -r '."cluster-members"[] | [."name", ."ip-address"] | @csv' | tr -d '"'))
done

for GW in "${GW_LIST[@]}"; do
    # split gateway name / ip
    GW_IP=$(echo $GW | cut -d ',' -f2)
    GW_NAME=$(echo $GW | cut -d ',' -f1)
    # Check if CPRID port open
    OPEN=`timeout 3 bash -c "</dev/tcp/$GW_IP/$PORT" 2>/dev/null && echo "Open" || echo "Closed"`
    if [[ "$OPEN" = "Open" ]]; then
        printf "%-17s %s\n" "$GW_NAME: " "Changing SSL/TLS ciphers"
        # copy local script to remote machine and execute. Check ciphers afterwards and smile.
        $CPDIR/bin/cprid_util -server $GW_IP putfile -local_file $CHANGE_SCRIPT -remote_file $CHANGE_SCRIPT -perms 700 > /dev/null
        $CPDIR/bin/cprid_util -server $GW_IP -verbose rexec -rcmd $CHANGE_SCRIPT > /dev/null   
    else
        printf "%-17s %s\n" "$GW_NAME: " "Unreachable"
    fi
done
