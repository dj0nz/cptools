#!/bin/bash

# create hosts entries for managed gateways
# run on check point management server
# dj0Nz may 2026

. /opt/CPshared/5.0/tmp/.CPprofile.sh

echo "Querying check point database. patience please..."
GW_LIST=($(mgmt_cli -r true show gateways-and-servers limit 500 offset 0 details-level full --format json --root true | $CPDIR/jq/jq -r '.objects[] | select( .type == "cluster-member" or .type == "simple-gateway" ) | [.name, .["ipv4-address"]] | @csv' | tr -d '"'))

echo ""
echo "Now creating missing host name entries."
echo ""

for GW in "${GW_LIST[@]}"; do
   IFS=',' read -r GW_NAME GW_IP <<< "$GW"
   HOSTS_NAME=$(clish -c "show configuration host" | grep $GW_NAME | awk '{print $4}')
   HOSTS_IP=$(clish -c "show configuration host" | grep $GW_NAME | awk '{print $6}')
   if [[ "$HOSTS_NAME" = "$GW_NAME" ]]; then
      if [[ "$HOSTS_IP" = "$GW_IP" ]]; then
         printf "%-19s %s\n" "$GW_NAME: " "hosts entry exists."
      else
        printf "%-19s %s\n" "$GW_NAME: " "hosts entry exists, but ip is different."
      fi
   else
      printf "%-19s %s\n" "$GW_NAME: " "no hosts entry."
   fi
done

echo ""
