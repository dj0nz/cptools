#!/bin/bash

# Get Check Point cluster topology
# Needs cluster name as input, output is interface list with topology check
# Must be run on Check Point management server

# !!! If a "specific" antispoofing configuration is used, this scripts expects a group object
# !!! containing one or more network objects. It will raise a warning otherwise.

# dj0Nz Mar 2023

# Input checking
if [[ ! $1 ]]; then
    echo "Usage: $0 [cluster name]"
    exit 1
fi
CLUSTER=`mgmt_cli -r true show simple-cluster name "$1" --format json | jq -r '."name" | select( . != null )'`
if [[ ! $CLUSTER ]]; then
    echo "No cluster object with name $1 found."
    exit 1
fi

echo ""
echo "Topology for cluster $CLUSTER:"
echo ""

# Generate date in seconds for unique output file name
RAND=`date +%s`
INFILE=$CLUSTER.json

# Get interfaces and topology from cluster object
mgmt_cli -r true show simple-cluster name $CLUSTER -f json | jq -r . > $INFILE
jq -r '."interfaces" | ."objects"[]' $INFILE > interfaces-$RAND.json
# Extract interface list from topology file
IFLIST=`jq -r '."name"' interfaces-$RAND.json`
# Get member names
MEMBERS=($(jq -r '."cluster-members"[]|.name' $INFILE))

# Function to check antispoofing configuration
spoofcheck () {
    RESULT="Ok"
    IFL=$1
    OUT=`jq --arg IFL "$IFL" -r 'select(.name | . and startswith($IFL)) | ."topology-settings"|."ip-address-behind-this-interface"' interfaces-$RAND.json`
    if [[ "$OUT" == "specific" ]]; then
        # Get spoofing group object
        GROUP=`jq --arg IFL "$IFL" -r 'select(.name | . and startswith($IFL)) | ."topology-settings"|."specific-network"' interfaces-$RAND.json`
        NO_GROUP=`mgmt_cli -r true show group name "$GROUP" | grep 'not found'`
        if [[ ! $NO_GROUP ]]; then
            # Create list of spoofing group members with type in "CSV" format
            GRP_MEMBERS=`mgmt_cli -r true show group name $GROUP -f json | jq -r '.members[] | {name, type} | join(",")'`
            # if members.type == network then check routing table on cluster member
            for LINE in $GRP_MEMBERS; do
                TYPE=`echo $LINE | cut -d "," -f2`
                if [[ "$TYPE" == "network" ]]; then
                    VAL=`echo $LINE | cut -d "," -f1`
                    # get object from db
                    NET_IN_DB=`mgmt_cli -r true show network name "$VAL"  --format json | jq -r .subnet4`
                    # get outgoing interface for route on firewall
                    IF_COMP=`$CPDIR/bin/cprid_util -server ${MEMBERS[0]} -verbose rexec -rcmd ip route get $NET_IN_DB | grep -oP '(?<=dev )[^ ]*'`
                    # if interface in topology and gateway are the same, do nothing. Else: Raise "ICONSISTENT" flag
                    if [[ ! "$IFL" == "$IF_COMP" ]]; then
                        RESULT="Inconsistent - Please check antispoofing!"
                    fi
                else
                    # If spoofing group contains hosts or other group objects, it must be checked manually
                    RESULT="Could not determine antispoofing configuration."
                fi
            done
            OUT=$GROUP
        else
            OUT=$GROUP
            RESULT="No antispoofing group configured."
        fi
    fi
    echo "$OUT, $RESULT"
}

# Loop through interfaces and determine topology and antispoofing configuration
for IF in $IFLIST; do
    IF_IP=`jq --arg IF "$IF" -r 'select(."name" | . and startswith($IF)) | ."ipv4-address"' interfaces-$RAND.json`
    IF_MASK=`jq --arg IF "$IF" -r 'select(."name" | . and startswith($IF)) | ."ipv4-mask-length"' interfaces-$RAND.json`
    TOPO=`jq --arg IF "$IF" -r 'select(."name" | . and startswith($IF)) | ."topology"' interfaces-$RAND.json`
    if [[ $TOPO == "automatic" ]]; then
        CALC=`jq --arg IF "$IF" -r 'select(."name" | . and startswith($IF)) | ."topology-automatic-calculation"' interfaces-$RAND.json`
        if [[ $CALC = "internal" ]]; then
            TOPO="internal"
            SPOOF=`spoofcheck $IF`
        else
            TOPO=$CALC
            SPOOF="external"
        fi
    else
        if [[ $TOPO = "internal" ]]; then
            SPOOF=`spoofcheck $IF`
        fi
    fi
    if [[ ! $IF_IP = "" ]]; then
        printf "%-12s %-20s %s\n" "$IF:" "$IF_IP/$IF_MASK" "$SPOOF"
    else
        printf "%-12s %-20s %s\n" "$IF:" "-" "$SPOOF"
    fi
done

rm interfaces-$RAND.json
echo ""
