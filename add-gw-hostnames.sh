#!/bin/bash

# create hosts entries for managed gateways
# run on check point management server
# dj0Nz nov 2020

# not sure if this is needed any more...
. /opt/CPshared/5.0/tmp/.CPprofile.sh

echo "querying check point database. patience please."
# get a list of gateway names and ips from cp mgmt database
GW_LIST=(`mgmt_cli -r true show gateways-and-servers limit 500 offset 0 details-level full --format json --root true | $CPDIR/jq/jq -r '.objects[]|[.["type"], .["name"], .["ipv4-address"]]| @csv' | egrep "CpmiClusterMember|simple-gateway" | cut -d "," -f 2,3 | tr -d '"'`)
CHANGED=no

echo "creating missing host name entries."
for INDEX in "${GW_LIST[@]}"; do
   # remove nonprintable, does not work elsewhere
   GW=`tr -dc '[[:print:]]' <<< "$INDEX"`
   GW_NAME=`echo $GW | awk -F , '{print $1}'`
   GW_IP=`echo $GW | awk -F , '{print $2}'`
   HOSTS=`clish -c "show configuration host" | grep $GW_NAME | awk '{print $4}'`
   if [[ "$HOSTS" = "$GW_NAME" ]]; then
      printf "%-17s %s\n" "$GW_NAME: " "hosts entry exists"
   else
      if [[ ! $GW_IP == 0.0.0* ]]; then
         printf "%-17s %s\n" "$GW_NAME: " "creating hosts entry"
         clish -c "add host name $GW_NAME ipv4-address $GW_IP"
         CHANGED=yes
      fi
   fi
done
if [[ "$CHANGED" = "yes" ]]; then
   echo "saving changed configuration."
   clish -c "save config"
else
   echo "configuration unchanged."
fi 
