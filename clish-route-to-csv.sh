#!/bin/bash

# Quick and dirty: Output of Check Point Gaia static routes in csv format
# Runs in expert shell on any Check Point Gaia Machine
# djonz aug 24

# Create temoprary file
INFILE=$(mktemp)
# Write Gaia static routes to temp file
clish -c "show configuration static-route" > $INFILE
# Get list of destination networks/hosts
ROUTES=$(cat $INFILE | grep nexthop | cut -d ' ' -f3)
# Field separator
SEP=","

for ROUTE in $ROUTES; do
    # Comment is from word 5 till end of line, strip quotes
    COMMENT=$(grep $ROUTE $INFILE | grep comment | cut -d ' ' -f5- | tr -d '"')
    NEXTHOP=$(grep $ROUTE $INFILE | grep nexthop | cut -d ' ' -f7)
    # Looks ugly but works
    echo "$ROUTE$SEP$NEXTHOP$SEP$COMMENT"
done
# remove temp file
rm $INFILE
