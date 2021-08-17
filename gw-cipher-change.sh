#!/bin/bash

# Check Point Firewall SSH und SSL Ciphers ändern
# Michael Goessmann Matos, NTT - Mar 2021

. /opt/CPshared/5.0/tmp/.CPprofile.sh

# Liste von Gateways aus der Check Point Datenbank extrahieren
GW_LIST=(`mgmt_cli -r true show gateways-and-servers limit 500 | egrep -B 1 'ClusterMember|simple-gateway' | grep name | awk '{print $2}' | tr -d '"'`)
PORT=18208

for INDEX in "${GW_LIST[@]}"; do
   # Nonprintable entfernen, sonst klappt das nicht. Warum auch immer.
   GW=`tr -dc '[[:print:]]' <<< "$INDEX"`
   # Gibts fuer das Gateway einen Hosts-Eintrag?
   HOSTS=`clish -c "show configuration host" | grep $GW | awk '{print $4}'`
   if [[ "$HOSTS" = "$GW" ]]; then
      # CPRID Port offen?
      OPEN=`timeout 3 bash -c "</dev/tcp/$GW/$PORT" 2>/dev/null && echo "Open" || echo "Closed"`
      if [[ "$OPEN" = "Open" ]]; then
         echo "$GW: "
         $CPDIR/bin/cprid_util -server $GW putfile -local_file /home/admin/cipherchange.sh -remote_file /home/admin/cipherchange.sh
         $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd chmod 700 /home/admin/cipherchange.sh
         $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd /home/admin/cipherchange.sh
      else
         printf "%-17s %s\n" "$GW: " "Unreachable"
      fi
   fi
done
