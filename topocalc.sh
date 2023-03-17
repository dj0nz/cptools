#!/bin/bash

# Get Check Point cluster topology
# Needs cluster name as input, output is interface list with topology
# dj0Nz Mar 2023

# Input checking
CLUSTER=`mgmt_cli -r true show simple-cluster name "$1" --format json | jq -r '."name" | select( . != null )'` 
if [[ ! $CLUSTER ]]; then
    echo "Usage: $0 [cluster name]"
	exit 1
fi

echo ""
echo "Topology for cluster $CLUSTER:"
echo ""

# Generate date in seconds for unique output file name
RAND=`date +%s`

# Get interfaces and topology from cluster object
mgmt_cli -r true show simple-cluster name $CLUSTER  --format json | jq -r '."interfaces" | ."objects"[]' > interfaces-$RAND.json
# Extract interface list from topology file
IFLIST=`jq -r '."name"' interfaces-$RAND.json`

# Function to check antispoofing configuration
spoofcheck () {
    IF=$1
    OUT=`jq --arg IF "$IF" -r 'select(.name | . and startswith($IF)) | ."topology-settings"|."ip-address-behind-this-interface"' interfaces-$RAND.json`
    if [[ $OUT = "specific" ]]; then
        OUT=`jq --arg IF "$IF" -r 'select(.name | . and startswith($IF)) | ."topology-settings"|."specific-network"' interfaces-$RAND.json`
    fi
	echo $OUT
}

# Loop through interfaces and determine topology and antispoofing configuration
for IF in $IFLIST; do
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
    printf "%-12s %s\n" "$IF: " "Topology: $TOPO, $SPOOF"
done

rm interfaces-$RAND.json
echo ""