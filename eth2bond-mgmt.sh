#!/bin/bash

# Move existing VLANs from current configuration to new bond interface. IP and netmask are retained.
# This is the management counterpart of the "eth2bond-gw.sh" script. Use this one first, then
# change VLANs locally on firewall machines afterwards. Make sure you use same VLANs and bond names
# in both scripts or face trouble.
#
# Note: Topology will be changed from "specific" antispoofing to "defined by routes". If you dont want that,
# don't use this script or edit cluster object after running it.
#
# Things to provide:
# - $CLUSTER : Name of the cluster object in SmartConsole
# - $BOND    : New bonding group.
# - $VLANS   : VLANs on other interfaces that should be transferred to the bond.
#
# dj0Nz Mar 2023

# Config Section
CLUSTER="gw"
BOND="bond2"
VLANS="16 17 18 27"

# Non-Variables
INFILE=$CLUSTER.json
IFLIST=iflist.txt
LOGFILE=move-if.log

# Logfile contains more or less useful output
if [[ -f $LOGFILE ]]; then
    rm $LOGFILE
fi
touch $LOGFILE

# Function to get/set antispoofing configuration
spoofcheck () {
    SPO_INT=$1
    SPO_FILE=$2
    OUT=`jq --arg SPO_INT "$SPO_INT" -r '."interfaces" | ."objects"[] | select(.name | . and startswith($SPO_INT)) | ."topology-settings"|."ip-address-behind-this-interface"' $SPO_FILE`
    if [[ "$OUT" == "specific" ]]; then
        OUT="network defined by routing"
    fi
    echo $OUT
}

# API login
echo ""
echo "Please login to management API with your SmartConsole user"
echo -n "Username: "
mgmt_cli login > id.txt
echo ""
echo ""
echo "Moving VLANs to bond interface..."
echo ""

# Load cluster definition and save to file
mgmt_cli -s id.txt show simple-cluster name $CLUSTER --format json | jq -r . > $INFILE

# Get member names
MEMBERS=($(jq -r '."cluster-members"[]|.name' $INFILE))

# Extract cluster member config
for MEMBER in "${MEMBERS[@]}"; do
    jq --arg MEMBER "$MEMBER" -r '."cluster-members"[] | select(."name" | . and startswith($MEMBER))' $INFILE > $MEMBER.json
done

# Extract interface List
jq -r '.interfaces | .objects[] | .name' $INFILE > $IFLIST

# Loop through VLANs and change interface names 
for VLAN in $VLANS; do
    INTF=`cat $IFLIST | grep \.$VLAN`
    # Get cluster/member IPs and topology from stored json files
	CLUSTER_IP=`jq --arg INTF "$INTF" -r '.interfaces | .objects[] | select (."name" | . and startswith($INTF)) | ."ipv4-address"' $INFILE`
    MEMBER1_IP=`jq --arg INTF "$INTF" -r '.interfaces[] | select (."name" | . and startswith($INTF)) | ."ipv4-address"' ${MEMBERS[0]}.json`
    MEMBER2_IP=`jq --arg INTF "$INTF" -r '.interfaces[] | select (."name" | . and startswith($INTF)) | ."ipv4-address"' ${MEMBERS[1]}.json`
    MASK=`jq --arg INTF "$INTF" -r '.interfaces | .objects[] | select (."name" | . and startswith($INTF)) | ."ipv4-mask-length"' $INFILE`
    TOPO=`jq --arg INTF "$INTF" -r '."interfaces" | ."objects"[] | select(."name" | . and startswith($INTF)) | ."topology"' $INFILE`
    # Set topology. See spoofcheck function
	if [[ $TOPO == "automatic" ]]; then
        CALC=`jq --arg INTF "$INTF" -r '."interfaces" | ."objects"[] | select(."name" | . and startswith($INTF)) | ."topology-automatic-calculation"' $INFILE`
        if [[ $CALC = "internal" ]]; then
            TOPO="internal"
            SPOOF=`spoofcheck $INTF $INFILE`
        else
            TOPO=$CALC
            SPOOF="external"
        fi
    else
        if [[ $TOPO = "internal" ]]; then
            SPOOF=`spoofcheck $INTF $INFILE`
        fi
    fi
    echo "Deleting interface $INTF"
    mgmt_cli -s id.txt set simple-cluster name $CLUSTER interfaces.remove $INTF -f json >> $LOGFILE 2>/dev/null
    echo "Creating interface $BOND.$VLAN with topology $SPOOF"
    mgmt_cli -s id.txt set simple-cluster name $CLUSTER interfaces.add.name $BOND.$VLAN interfaces.add.ip-address $CLUSTER_IP interfaces.add.ipv4-mask-length $MASK interfaces.add.interface-type "cluster" interfaces.add.topology "internal" interfaces.add.topology-settings.ip-address-behind-this-interface "$SPOOF" interfaces.add.topology-settings.interface-leads-to-dmz "false" interfaces.add.anti-spoofing "true" members.update.1.name ${MEMBERS[0]} members.update.1.interfaces.name $BOND.$VLAN members.update.1.interfaces.ipv4-address $MEMBER1_IP members.update.1.interfaces.ipv4-mask-length $MASK members.update.2.name ${MEMBERS[1]} members.update.2.interfaces.name $BOND.$VLAN members.update.2.interfaces.ipv4-address $MEMBER2_IP members.update.2.interfaces.ipv4-mask-length $MASK  -f json >> $LOGFILE 2>/dev/null
done

# Logout and leave session
echo ""
echo "Publishing..."
mgmt_cli publish -s id.txt -f json > publish.json 2>/dev/null
SUCCESS=`jq -r '."tasks"[]?|."status"' publish.json`
if [[ $SUCCESS == "succeeded" ]]; then
    echo "Successful. Logging out."
    mgmt_cli logout -s id.txt -f json | jq -r . >> $LOGFILE 2>&1
	rm publish.json
	rm id.txt
	# cleanup section. your choice.
	# rm $INFILE
	# rm ${MEMBERS[0]}.json
	# rm ${MEMBERS[1]}.json
	# rm iflist.txt
else
    echo "Publish failed. See $LOGFILE and publish.json for messages."
    echo "Do a manual logout (mgmt_cli logout -s id.txt) and delete id.txt after troubleshooting."
fi
echo ""