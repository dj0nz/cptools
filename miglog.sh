#!/bin/bash

# Check Point Firewall Logfile Migration
#
# Script to copy existing logfiles to a new log/management server ($TARGET) after 
# an "advanced migration" (reinstall new one and export/import database)
# Schedule on old management / log server with cron (no at in Gaia!) and delete
# cron job after execution. 
#
# You should configure public key auth between the admin users on the two systems:
# - Login shell for user admin must be set to /bin/bash on both systems. You might use a
#   separate user for this but that would be somewhat pointless because admin-like 
#   users always get uid 0 in Check Point Gaia... :-/
# - To create new key pair on the SOURCE server (if you dont have one already):
#   ssh-keygen -t ed25519 -a 100 -f /home/admin/.ssh/id_ed25519-2 -q -N ""
# - To copy public key to TARGET system (the new one):
#   ssh-copy-id -o StrictHostKeyChecking=accept-new TARGET
# Of course, target must be known by name or you have to use IP here and obviously,
# the user has to be "admin".
#
# Delete public key used here from authorized_keys on TARGET after transfer is finished.
#
# Michael Goessmann Matos, NTT
# Jan 2024

# Get Check Point version from CPsuite rpm (one of a million ways to determine)
CP_VERSION=$(rpm -qa | grep CPsuite | awk -F'-' '{print $2}')

# Variables
TARGET="192.168.1.21"
LOCAL_LOGDIR=/var/log/opt/CPsuite-$CP_VERSION/fw1/log/
# Attention: Local and TARGET versions might be different!
TARGET_LOGDIR=$LOCAL_LOGDIR
# Retention time: How many logs (in days) should be transferred? 
# In this example, log files older than 30 days will be omitted.
RETIME=30

# cd into the "physical" directory
cd $LOCAL_LOGDIR

# create list of all log files in directory
for EXT in logptr log log_stats logaccount_ptr loginitial_ptr; do
    FILE_LIST+=" "
    FILE_LIST+=$(/usr/bin/find . -type f -name "*.$EXT" -mtime -$RETIME -print | cut -d '/' -f2)
done

# copy log files to destination omitting the current ones (fw.log etc.) which might be open
for ENTRY in $FILE_LIST; do
    if [[ ! $ENTRY =~ "fw\..*" ]]; then
        scp -q $ENTRY $TARGET:$TARGET_LOGDIR
    fi
done
