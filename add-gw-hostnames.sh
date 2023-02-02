#!/bin/bash

# Create host name entries for managed gateways
# Run on Check Point management server
# dj0Nz feb 2023

. /etc/profile.d/CP.sh

echo "Querying Check Point database. Patience please..."
GW_LIST=(`mgmt_cli -r true show gateways-and-servers limit 500 offset 0 details-level full --format json | $CPDIR/jq/jq -r '.objects[]|[.["type"], .["name"], .["ipv4-address"]]| @csv' | egrep "cluster-member|simple-gateway" | cut -d "," -f 2,3 | tr -d '"'`)
IPREGEX="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
CHANGED=no

LOCKED=`clish -c "show config-state" | grep owned`
if [[ $LOCKED ]]; then
    echo "Gaia database locked. Exiting."
    exit 1
fi

echo "Creating missing host name entries."
for INDEX in "${GW_LIST[@]}"; do
    # remove nonprintable, does not work otherwise
    GW=`tr -dc '[[:print:]]' <<< "$INDEX"`
    GW_NAME=`echo $GW | awk -F , '{print $1}'`
    GW_IP=`echo $GW | awk -F , '{print $2}'`
    CHECK=`echo $GW_IP | grep -E "$IPREGEX"`
    if [[ "$CHECK" = "" ]]; then
        printf "%-15s %s\n" "$GW_NAME: " "IP address syntax check failed. Address: $GW_IP"
    else
        HOSTS_NAME=`clish -c "show configuration host" | grep $GW_NAME | awk '{print $4}'`
        HOSTS_IP=`clish -c "show configuration host" | grep $GW_NAME | awk '{print $6}'`
        if [[ "$HOSTS_NAME" = "$GW_NAME" ]]; then
            if [[ "$HOSTS_IP" = "$GW_IP" ]]; then
                printf "%-15s %s\n" "$GW_NAME: " "Host name entry exists"
            else
                printf "%-15s %s\n" "$GW_NAME: " "Host name entry exists, but IP is different. Check manually!"
            fi
        else
            printf "%-15s %s\n" "$GW_NAME: " "Creating host name entry"
            clish -c "add host name $GW_NAME ipv4-address $GW_IP"
            CHANGED=yes
        fi
    fi
done

if [[ "$CHANGED" = "yes" ]]; then
    echo "Saving changed configuration."
    clish -c "save config"
else
    echo "Configuration unchanged."
fi
