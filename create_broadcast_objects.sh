#!/bin/bash

# - get broadcast addresses from gateway
# - create broadcast address host object (if there isn't already one)
# - add freshly created host object to broadcast objects group
#
# dj0Nz May 2022

. /opt/CPshared/5.0/tmp/.CPprofile.sh

# Variables. This is an example with single firewall, but works with cluster, too.
# Broadcast addresses are identical on both cluster members, so you only need one.
# Please make sure that the gateway is accessible by hostname (see add_gw_hostnames.sh)
GW="gw"
GROUP="br_addrs_gw"
PORT=18208
LOGFILE=/var/log/objects_create.log

# Clear log
cat /dev/null > $LOGFILE

# API login
echo ""
echo "Please login to management API with your SmartConsole user"
echo -n "Username: "
mgmt_cli login > id.txt
echo ""
echo ""
echo "Adding firewall local broadcast addresses to new group $GROUP. Patience please."

# Check if group exists, add it if not.
BRGROUP=`mgmt_cli -r true show groups filter "$GROUP" --format json | jq -r '.objects[]|."name"'`
if [[ $BRGROUP = "" ]]; then
   echo "create group object $GROUP" >> $LOGFILE 2>&1
   mgmt_cli add group name "$GROUP" -s id.txt >> $LOGFILE 2>&1
else
   echo "group object $GROUP already exists." >> $LOGFILE 2>&1
fi

# Get broadcast addresses from firewall
BRLIST=`$CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd ifconfig -a | grep Bcast | awk '{print $3}' | awk -F ':' '{print $2}'`

# Create host object for every broadcast address
for IPADDR in $BRLIST; do
   ARC=`mgmt_cli show hosts filter "br_$IPADDR" limit 500 --format json -s id.txt | jq -r '.objects[]|."name"'`
   if [[ $ARC = "" ]]; then
      echo "create host object br_$IPADDR" >> $LOGFILE 2>&1
      mgmt_cli add host name "br_$IPADDR" ip-address "$IPADDR" groups "$GROUP" -s id.txt >> $LOGFILE 2>&1
   else
      echo "host object br_$IPADDR already exists." >> $LOGFILE 2>&1
   fi
done

# Logout and leave session
mgmt_cli publish -s id.txt >> $LOGFILE 2>&1
mgmt_cli logout -s id.txt >> $LOGFILE 2>&1
rm id.txt
echo ""
echo "Done."
echo "Please check group $GROUP and br_* objects in SmartConsole."
echo "You may also check $LOGFILE."
echo ""
