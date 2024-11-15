#!/bin/bash

# Deploy SSH public key to gateways
# dj0Nz
# Nov 2024

. /opt/CPshared/5.0/tmp/.CPprofile.sh

# Get gateway list from Check Point database
echo "Gateway SSH access check"
echo "----------------------------------"
echo "Getting list of gateways from management server. Patience please..."
GW_LIST+=($(mgmt_cli -r true show gateways-and-servers limit 500 details-level full -f json | jq -r '.objects[] | select ((."type" == "cluster-member") or (."type" == "simple-gateway")) | [.["name"], .["ipv4-address"]] | @csv' | tr -d '"'))

echo "Please enter the admin password at the prompt to distribute public keys if missing"
read -sp "Admin password: " SSHPASS
export SSHPASS
echo ""
echo "Checking gateway SSH access and deploying public key..."

for GW in "${GW_LIST[@]}"; do
   # extract gateway name
   TARGET=$(echo $GW | awk -F , '{print $1}')
   # check if host name entry exists
   RESOLV=$(getent hosts $TARGET | awk '{print $2}')
   if [[ $TARGET == $RESOLV ]]; then
      # check if ssh port open
      OPEN=$(timeout 3 bash -c "</dev/tcp/$TARGET/22" 2>/dev/null &&  echo "Open" || echo "Closed")
      if [[ "$OPEN" = "Open" ]]; then
         # check if pubkey auth possible
         ssh -q -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new $TARGET exit
         if [ "$?" = "0" ]; then
            printf "%-15s %-35s %s\n" "$TARGET:" "OK"
         else
            printf "%-15s %-35s" "$TARGET:" "Public key missing, installing it"
            # Automated install of pubkeys:
            # First, remove old known hosts entry if any
            CHECK_HOST_KEY=$(ssh-keygen -F $TARGET)
            if [[ $CHECK_HOST_KEY ]]; then
                ssh-keygen -R $TARGET > /dev/null 2>&1
            fi
            # Then, create new known_hosts entry
            ssh -q -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new $TARGET exit
            # finally, distribute admin key
            sshpass -e ssh-copy-id admin@$TARGET > /dev/null 2>&1
            ssh -q -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new $TARGET exit
            if [ "$?" = "0" ]; then
                echo "[OK]"
            else
                echo "[Failed]"
            fi
         fi
      else
         # CPRID open?
         CPRID_PORT=$(timeout 3 bash -c "</dev/tcp/$TARGET/18208" 2>/dev/null && echo "Open" || echo "Closed")
         if [[ "$CPRID_PORT" = "Open" ]]; then
            printf "%-15s %-35s %s\n" "$TARGET:" "SSH access rule missing."
         else
            printf "%-15s %-35s %s\n" "$TARGET:" "No connection."
         fi
      fi
   else
      printf "%-15s %-35s %s\n" "$TARGET:" "No hostname."
   fi
done
unset SSHPASS
