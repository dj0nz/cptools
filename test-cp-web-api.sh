#!/usr/bin/bash

CP_MGMT=192.168.1.11
CP_API_KEY_ENC=api-key.gpg
SESSION_INFO=session-info.txt

API_KEY=`gpg -qd $CP_API_KEY_ENC`

curl -X POST -H "content-Type: application/json" --silent -k https://$CP_MGMT/web_api/login -d '{ "api-key" : "'$API_KEY'" }' > $SESSION_INFO
SESSION_ID=`cat $SESSION_INFO | jq -r .sid`

NETWORK="10.3.0.0"
NET_GROUP="Test-Network"
COMMENT="Just a test network"

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
            TASK_STATE=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-task -d '{ "task-id" : "'$TASK_ID'" }' | jq -r '.tasks[]|.status'`
            if [[ ! "$TASK_STATE" = "succeeded" ]]; then
                sleep 2
                TASK_STATE=`curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-task -d '{ "task-id" : "'$TASK_ID'" }' | jq -r '.tasks[]|.status'`
                if [[ ! "$TASK_STATE" = "succeeded" ]]; then
                    echo "Something unexpected happened during publish. Check logs."
                else
                    echo "Publish $TASK_STATE"
                fi
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
