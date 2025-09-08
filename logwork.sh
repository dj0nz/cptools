#!/bin/bash

# Purpose:
# Delete firewall log files older than $RETIME days
# Compress them if the're older than $ZIPTIME
# Runs scheduled on a Check Point Management or log server
# Schedule to run daily to avoid long runtimes

# Michael Goessmann Matos, NTT
# Sep 2025

# Vars
RETIME="365"
ZIPTIME="90"
CP_VERSION=$(cat /etc/cp-release | cut -d ' ' -f4)
EXT=log
LOGFILE=/var/log/orange.log

exec > $LOGFILE 2>&1

NUMLOG=$(/usr/bin/find /var/log/opt/CPsuite-$CP_VERSION/fw1/log/ -type f -name "*.$EXT" -mtime +$ZIPTIME -print | wc -l)
CURR=$(date -R | cut -d ' ' -f2,3,4,5)
if [[ $NUMLOG =~ ^[0-9]+$ ]]; then
    if [[ $NUMLOG -gt 0 ]]; then
        echo "$CURR - Compressing log files older than $ZIPTIME days"
        for EXT in logptr log log_stats logaccount_ptr loginitial_ptr; do
            echo ""
            echo "Compressing *.$EXT files..."
            /usr/bin/find /var/log/opt/CPsuite-$CP_VERSION/fw1/log/ -type f -name "*.$EXT" -mtime +$ZIPTIME -print -exec gzip {} \;
        done
    else
        echo "$CURR - Nothing to compress"
    fi
else
    echo "$CURR - Something went wrong: Can't compress $NUMLOG files."
fi
    
NUMZIP=$(/usr/bin/find /var/log/opt/CPsuite-$CP_VERSION/fw1/log/ -type f -name "*.gz" -mtime +$RETIME | wc -l)
if [[ $NUMZIP =~ ^[0-9]+$ ]]; then
    if [[ $NUMZIP -gt 0 ]]; then
        CURR=$(date -R | cut -d ' ' -f2,3,4,5)
        echo "$CURR - Deleting zipped files older than $RETIME days..."
        /usr/bin/find /var/log/opt/CPsuite-$CP_VERSION/fw1/log/ -type f -name "*.gz" -mtime +$RETIME -print -exec rm {} \;
    else
        echo "$CURR - Nothing to delete"
    fi
else
    echo "$CURR - Something went wrong: Can't delete $NUMZIP files."
fi
echo ""
