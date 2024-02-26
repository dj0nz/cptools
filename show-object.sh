#!/usr/bin/bash

# Show object from given UID
# Documentation: https://sc1.checkpoint.com/documents/latest/APIs/index.html#web/
# dj0Nz Feb 2024

# File that contains API key
KEYFILE=~/api/.api-key
if [[ -f $KEYFILE ]]; then
    API_KEY=$(cat $KEYFILE)
else
    echo "No keyfile".
    exit 1
fi

# Check Point management server IP
CP_MGMT=192.168.1.11
CP_REACH=`timeout 2 bash -c "</dev/tcp/$CP_MGMT/443" 2>/dev/null &&  echo "Open"`
if [[ ! "$CP_REACH" = "Open" ]]; then
    echo "Management unreachable."
    exit 1
fi

# Input: Object UID
UID_REGEX=^[A-Za-z0-9]{8}\-[A-Za-z0-9]{4}\-[A-Za-z0-9]{4}\-[A-Za-z0-9]{4}\-[A-Za-z0-9]{12}$
if [[ "$1" =~ $UID_REGEX ]]; then
    OBJECT=$1
else
    echo "Input missing or not a valid uid."
    exit 1
fi

# API Command to issue
COMMAND="show-object"

# Request body.
REQ_BODY='"uid" : "'$OBJECT'"'

# API login and get session id
SESSION_ID=$(curl -X POST -H "content-Type: application/json" --silent -k https://$CP_MGMT/web_api/login -d '{ "api-key" : "'$API_KEY'" }' | jq -r .sid)

# Quick and dirty no store no response check. Pipe to jq for better readability.
curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/$COMMAND -d '{ '"$REQ_BODY"' }'

# Logout. Optionally display message
LOGOUT_MSG=$(curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/logout -d '{ }' | jq -r '."message"')
if [[ ! "$LOGOUT_MSG" = "OK" ]]; then
    echo ""
    echo "Logout unsuccessful."
fi