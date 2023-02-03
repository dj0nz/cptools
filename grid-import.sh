#!/usr/bin/bash

# Purpose:
# Read networks from Infoblox IPAM ("$GRID_IP") network containers ("$GRID_CONTAINERS"), search for comment fields that start with $PATTERN
# Store filtered networks and comments to a file ("$OUTPUT") and use this file to create the corresponding objects in the Check Point database.
#
# This script can be run from any system with a bash shell that is authorized for API access to both (Check Point / Infoblox) management systems.
# It is NOT intended to be run unattended, because it needs user input (passphrase to decrypt Checkpoint API key and Grid credentials).
# Of course, these files must have been encrypted beforehand. Don't store them unencrypted!
#
# One more thing: You don't need to be root to run this script.
#
# "Work safe, work smart. Your future depends on it."
# -- Black Mesa Announcement System
#
# Software needed locally:
# - gpg to (optionally) store API key and credentials in a safe(er) manner
# - jq to parse Json outputs
# - curl for http access
#
# Requirements:
# - An Infoblox Grid or standalone IPAM system with current software release (> 8.5) and a user with appropriate (read) permissions
# - A Check Point Management System with current software release (R81.x) and an API user there with Read/Write permissions
# - Appropriate access rules (allow https) on the firewalls protecting the management systems
#
# Links to documentation used:
# Infoblox WAPI documentation: https://ipam.illinois.edu/wapidoc/
# Check Point API documentation: https://sc1.checkpoint.com/documents/latest/APIs/
# Curl documentation: https://everything.curl.dev/
# IP address regex: https://www.regextutorial.org/regex-for-ip-address-match.php
#
# More useful links:
# https://community.checkpoint.com/t5/Threat-Prevention/Using-Gaia-OS-curl-cli-for-Management-API-commands-for-Threat/td-p/118461#
# https://sc1.checkpoint.com/documents/latest/APIs/#web/show-networks~v1.8%20
# https://everything.curl.dev/usingcurl/netrc
# https://blog.nem.ec/code-snippets/jq-ignore-nulls/
# https://devconnected.com/how-to-encrypt-file-on-linux/
# https://wiki.ubuntuusers.de/GPG-Agent/
# https://research.kudelskisecurity.com/2022/06/16/gpg-memory-forensics/
#
# MGO/NTT Jan 2023

# The encrypted files that hold Checkpoint API key and Infoblox credentials
CP_API_KEY_ENC=api-key.gpg
GRID_CREDS=grid-creds.gpg
# Temporary file to store session information
SESSION_INFO=session-info.txt
# Write output to file instead of array in order to be able to check it if something goes wrong
OUTPUT=/tmp/netlist.csv
# Search term for the comments field of an Infoblox network container
PATTERN="DE"
# IP address of the Infoblox Grid
GRID_IP="192.168.1.8"
# Look for networks in these containers. Note: This will not search in child containers!
GRID_CONTAINERS="10.1.0.0/16 10.2.0.0/16"
# Check Point Management Server IP
CP_MGMT="192.168.1.11"
# Group name in Check Point database that should contain the networks we create
NET_GROUP="DE_Networks"
# Timediff in seconds, after that a publish to Checkpoint Management is considered "failed"
PUBLISH_TIMEOUT=10
# Regex to check for valid IP-Address (Source link in header)
IPREGEX="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"

# Check for existence of both Infoblox and Checkpoint credential files, check if $GRID_IP and $CP_MGMT are reachable
GRID_REACH=`timeout 3 bash -c "</dev/tcp/$GRID_IP/443" 2>/dev/null &&  echo "Open"`
if [[ ! "$GRID_REACH" = "Open" ]]; then
    echo "Infoblox Grid unreachable. Exiting."
    exit 1
fi
CP_REACH=`timeout 3 bash -c "</dev/tcp/$CP_MGMT/443" 2>/dev/null &&  echo "Open"`
if [[ ! "$CP_REACH" = "Open" ]]; then
    echo "Checkpoint Management unreachable. Exiting."
    exit 1
fi
if [[ ! -f $CP_API_KEY_ENC ]]; then
    echo "Encrypted Checkpoint API key file ($CP_API_KEY_ENC) not found. Exiting."
    exit 1
fi
if [[ ! -f $GRID_CREDS ]]; then
    echo "Encrypted Infoblox credentials ($GRID_CREDS) not found. Exiting."
    exit 1
fi

# Reset output file
touch $OUTPUT
cat /dev/null > $OUTPUT

echo ""
echo "Please enter gpg passphrase(s) when prompted to do so."
read -p "Press any key to continue... " -n1
echo ""

# Read networks from Infoblox Grid containers using WAPI, search for Strings that start with $PATTERN and write networks and comments to $OUTPUT file
# First: decrypt GRID credentials, format of the credentials file see curl documentation (link in header section)
gpg -o grid-creds.txt -qd $GRID_CREDS
echo "Getting networks from Infoblox Grid..."
for i in $GRID_CONTAINERS; do curl -k --silent --netrc-file grid-creds.txt https://$GRID_IP/wapi/v2.10/network?network_container=$i | jq --arg PATTERN "$PATTERN" -r '.[]| select(.comment | . and startswith($PATTERN)) | [.["comment"], .["network"]] | @csv' | tr -d '"'; done >> $OUTPUT
rm grid-creds.txt

# Syntax checking. Error and exit if network not /24 or no valid IP or comma in comment, which would break csv structure
NUM=`cat $OUTPUT | wc -l`
if [[ ! $NUM -lt 1 ]]; then
    while read line; do
        CHECK=`echo $line | grep -E ".*,$IPREGEX\/24"`
	if [[ "$CHECK" = "" ]]; then
	    echo "IP address syntax wrong in line $line."
	    exit 1
	fi
        COMMA=`echo $line | tr -d -c ',' | wc -m`
        if [[ ! "$COMMA" = "1" ]]; then
            echo "More than one comma in line $line."
            exit 1
        fi
    done < $OUTPUT
else
    echo "Empty output file!"
    exit 1
fi

# API login to Check Point management.
API_KEY=`gpg -qd $CP_API_KEY_ENC`
curl -X POST -H "content-Type: application/json" --silent -k https://$CP_MGMT/web_api/login -d '{ "api-key" : "'$API_KEY'" }' > $SESSION_INFO
SESSION_ID=`cat $SESSION_INFO | jq -r .sid`

# Check if destination group exists
CHECK_GROUP=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-group -d '{ "name" : "'$NET_GROUP'" }'| jq -r .name`
if [[ ! "$CHECK_GROUP" = "$NET_GROUP" ]]; then
    echo "Required group $NET_GROUP does not exist in Checkpoint database."
    exit 1
fi

# Loop through networks and create missing
echo ""
echo "Creating networks in Checkpoint database..."
echo ""
while read line; do
    COMMENT=`echo $line | awk -F , '{print $1}'`
    # Networks are always /24
    NETWORK=`echo $line | awk -F , '{print $2}' | awk -F '/' '{print $1}'`
    # Check if object is already in database
    CHECK_NETWORK=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-networks -d '{ "filter" : "'$NETWORK'" }'| jq -r '.objects[]|."subnet4"'`
    if [[ $CHECK_NETWORK = "" ]]; then
        # Output checking and error handling
        CREATE_NETWORK=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/add-network -d '{ "name" : "'net_${NETWORK}_24'", "subnet" : "'$NETWORK'", "mask-length" : "24", "groups" : "'$NET_GROUP'", "comments" : "'"$COMMENT"'" }' | jq -r '."meta-info"|."validation-state"'`
        if [[ ! "$CREATE_NETWORK" = "ok" ]]; then
            echo "Something went wrong during object creation"
        else
            # Curly brackets around variable are essential, because "_$" has a meaning.
            echo "Network object net_${NETWORK}_24 created"
        fi
    else
        echo "Network object net_${NETWORK}_24 already in database."
    fi
done < $OUTPUT

echo ""
# Ask before publishing
while true; do
    read -p "Publish changes [Y/N]? " yn
    case $yn in
        [Yy]* ) TASK_ID=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/publish -d '{ }' | jq -r '."task-id"'`
                if [[ "$TASK_ID" = "" ]]; then
                    echo "Something unexpected happened during publish. Check logs."
                else
                    echo "Publishing..."
                    START_TIME=`date +%s`
                    TIME_DIFF=0
                    TASK_STATE="init"
                    while [[ $TIME_DIFF -lt $PUBLISH_TIMEOUT && ! "$TASK_STATE" = "succeeded" ]]; do
                        TASK_STATE=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-task -d '{ "task-id" : "'$TASK_ID'" }' | jq -r '.tasks[]|.status'`
                        sleep 1
                        CURR_TIME=`date +%s`
                        TIME_DIFF=$[$CURR_TIME - $START_TIME]
                    done
                    if [[ ! "$TASK_STATE" = "succeeded" ]]; then
                        echo "Something unexpected happened during publish. Publish state: $TASK_STATE - Check logs."
                    else
                        echo "Publish $TASK_STATE"
                    fi
                fi
                break
                ;;
        [Nn]* ) DISCARD=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/discard -d '{ }'| jq -r .message`
                if [[ "$DISCARD" = "" ]]; then
                    echo "Discard: Something went wrong. Check Database."
                else
                    echo "Discard: Successful ($DISCARD)"
                fi
                break
                ;;
        * ) echo "Please answer [y]es or [n]o.";;
    esac
done

# Cleanup section. Keep the output file for manual checking if logout unsuccessful
echo ""
LOGOUT_MSG=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/logout -d '{ }' | jq -r '."message"'`
if [[ "$LOGOUT_MSG" = "OK" ]]; then
    echo "Logout successful"
    rm $SESSION_INFO
else
    echo "Logout unsuccessful. Consider doing a manual logout (Session ID is in $SESSION_INFO)"
fi
