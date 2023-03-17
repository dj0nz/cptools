#!/bin/bash

# Move existing VLANs from current configuration to new bond interface. IP and netmask are retained.
#
# Things to check / change:
# - $BOND  : New bonding group that will get created. Make sure it doesn't exist.
# - SLAVES : Slave interface in the new bonding group. Make sure they are really unused.
# - VLANS  : VLANs on other interfaces that should be transferred to the bond. No questions asked.
#
# Final notice: 
# Only run the deployment command (clish -f ...) if you checked all requirements AND if you know what you're doing...
#
# dj0Nz Mar 2023 

# Variables
CFG=move-interfaces.cfg
BOND="bond2"
SLAVES="eth6 eth7"
VLANS="16 17 18 27"

if [[ -f $CFG ]]; then
    cat /dev/null > $CFG
else
    touch $CFG
fi

echo "Writing config file $CFG"

# Add bonding group - Adjust settings as needed
BG=${BOND//[bond]/}
echo "add bonding group $BG" >> $CFG
for SLAVE in $SLAVES; do
    echo "add bonding group $BG interface $SLAVE" >> $CFG
done
echo "set bonding group $BG mode 8023AD"  >> $CFG
echo "set bonding group $BG lacp-rate slow"  >> $CFG
echo "set bonding group $BG xmit-hash-policy layer3+4" >> $CFG

# Moving VLANs to bond interface. Dont touch. Might explode.
for VLAN in $VLANS; do
    CSV=`clish -c "show configuration interface" | grep set.interface.*\.$VLAN.ipv4-address | awk '{print $3 "," $5 "," $7}'`
    ARRAY=(${CSV//,/ })
    IF=`echo "${ARRAY[0]}" | cut -d "." -f1`
    IP=${ARRAY[1]}
    MASK=${ARRAY[2]}
    echo "delete interface $IF.$VLAN ipv4-address" >> $CFG
    echo "set interface $IF.$VLAN state off" >> $CFG
    echo "delete interface $IF vlan $VLAN" >> $CFG
    echo "add interface $BOND vlan $VLAN" >> $CFG
    echo "set interface $BOND.$VLAN state on" >> $CFG
    echo "set interface $BOND.$VLAN ipv4-address $IP mask-length $MASK" >> $CFG
done

if [[ -f $HOSTNAME.cfg ]]; then
    mv $HOSTNAME.cfg $HOSTNAME.cfg.backup
fi
clish -c "save configuration $HOSTNAME.cfg"

echo "Done. Configuration backup saved in $HOSTNAME.cfg."
echo "Please double-check new configuration in $CFG and issue clish -f $CFG -s afterwards"