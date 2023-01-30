#!/usr/bin/bash

CP_MGMT=192.168.1.11
CP_API_KEY_ENC=api-key.gpg
SESSION_INFO=session-info.txt
PUBLISH_TIMEOUT=10

API_KEY=`gpg -qd $CP_API_KEY_ENC`

curl -X POST -H "content-Type: application/json" --silent -k https://$CP_MGMT/web_api/login -d '{ "api-key" : "'$API_KEY'" }' > $SESSION_INFO
SESSION_ID=`cat $SESSION_INFO | jq -r .sid`

NETWORK="10.8.0.0"
NET_GROUP="Test-Network"
COMMENT="Just a test network"

echo "Checking network group"
CHECK_GROUP=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-group -d '{ "name" : "'$NET_GROUP'" }'| jq -r .name`
if [[ ! "$CHECK_GROUP" = "$NET_GROUP" ]]; then
    echo "Required group $NET_GROUP does not exist in Checkpoint database."
    exit 1
fi

echo "Creating object $NETWORK"
echo ""

echo "Checking, if object exists"
CHECK_NETWORK=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-networks -d '{ "filter" : "'$NETWORK'" }'| jq -r '.objects[]|."subnet4"'`
if [[ "$CHECK_NETWORK" = "" ]]; then
    echo "Creating object"
    CREATE_NETWORK=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/add-network -d '{ "name" : "'net_${NETWORK}_24'", "subnet" : "'$NETWORK'", "mask-length" : "24", "groups" : "'$NET_GROUP'", "comments" : "'"$COMMENT"'" }' | jq -r '."meta-info"|."validation-state"'`
    if [[ ! "$CREATE_NETWORK" = "ok" ]]; then
        echo "Something went wrong during object creation"
    else
        TASK_ID=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/publish -d '{ }' | jq -r '."task-id"'`
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
    fi
else
    echo "Network $NETWORK already exists in database."
fi

echo ""
LOGOUT_MSG=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/logout -d '{ }' | jq -r '."message"'`
if [[ "$LOGOUT_MSG" = "OK" ]]; then
    echo "Logout successful"
    rm $SESSION_INFO
else
    echo "Logout unsuccessful. Consider doing a manual logout (Session ID is in $SESSION_INFO)"
fi
