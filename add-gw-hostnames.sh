#!/bin/bash

# create hosts entries for managed gateways
# run on check point management server
# dj0Nz nov 2020

. /etc/profile.d/CP.sh

echo "querying check point database. patience please."
GW_LIST=(`mgmt_cli -r true show gateways-and-servers limit 500 offset 0 details-level full --format json | $CPDIR/jq/jq -r '.objects[]|[.["type"], .["name"], .["ipv4-address"]]| @csv' | egrep "cluster-member|simple-gateway" | cut -d "," -f 2,3 | tr -d '"'`)
CHANGED=no

LOCKED=`clish -c "show config-state" | grep owned`
if [[ $LOCKED ]]; then
    echo "gaia database locked. exiting."
    exit 1
fi

echo "creating missing host name entries."
for INDEX in "${GW_LIST[@]}"; do
    # remove nonprintable, does not work otherwise
    GW=`tr -dc '[[:print:]]' <<< "$INDEX"`
    GW_NAME=`echo $GW | awk -F , '{print $1}'`
    GW_IP=`echo $GW | awk -F , '{print $2}'`
    HOSTS_NAME=`clish -c "show configuration host" | grep $GW_NAME | awk '{print $4}'`
    HOSTS_IP=`clish -c "show configuration host" | grep $GW_NAME | awk '{print $6}'`
    if [[ "$HOSTS_NAME" = "$GW_NAME" ]]; then
        if [[ "$HOSTS_IP" = "$GW_IP" ]]; then
            printf "%-17s %s\n" "$GW_NAME: " "hosts entry exists"
        else
            printf "%-17s %s\n" "$GW_NAME: " "hosts entry exists, but ip is different. check manually!"
        fi
    else
        printf "%-17s %s\n" "$GW_NAME: " "creating hosts entry"
        clish -c "add host name $GW_NAME ipv4-address $GW_IP"
        CHANGED=yes
    fi
done
if [[ "$CHANGED" = "yes" ]]; then
    echo "saving changed configuration."
    clish -c "save config"
else
    echo "configuration unchanged."
fi
