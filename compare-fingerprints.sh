#!/usr/bin/bash
#
# Purpose:
# Compare LDAPS fingerprint in Check Point Management DB with "real" fingerprint of LDAP Account Unit / Domain Controller
# Just a POC to demonstrate functionality, works if you have ONE server in Account Unit, but you may loop through servers array you get with "show-generic-objects" request
#
# Requirements:
# - A current linux box with curl, openssl and jq installed
# - Firewall rules that allow https access to the Check Point management server and ldaps access the the domain controllers
# - An API key on the Check Point management and Gui client access allowed for the linux box
#
# dj0Nz Feb 2024

# Check Point management server IP
CP_MGMT=<Management IP>
# Name of LDAP Account Unit.
ACCOUNT_UNIT=<Account Unit Objects Name>

# Temporary file to store session ID used to login after authenticating
SESSION_INFO=session-info.txt
# Never hardcode API Keys. You may also consider to use encryption (see https://github.com/dj0nz/cptools/blob/main/grid-import.sh for an example)
API_KEY=$(cat .api-key)
# The file to store json output of the main request
OUTFILE=output.txt

# API login and get session id. Exit if unsuccessful.
RESPONSE=$(curl -X POST -H "content-Type: application/json" --silent -w "%{http_code}" -k https://$CP_MGMT/web_api/login -d '{ "api-key" : "'$API_KEY'" }' -o $SESSION_INFO)
if [[ "$RESPONSE" = "200" ]]; then
    SESSION_ID=$(cat $SESSION_INFO | jq -r .sid)
else
    echo "API login error. Check credentials and permissions"
    exit 1
fi

# Get account unit object information using show-generic-objects request and store to $OUTFILE
curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-generic-objects -d '{ "name" : "'$ACCOUNT_UNIT'",  "details-level" : "full" }' -o $OUTFILE

# Get LDAPS fingerprint. Attention: If you have multiple ldap servers configured, you will have to loop through the ldapServers array.
CP_FPRINT=$(jq -r '.objects[]|.ldapServers[]|."ldapSslSettings"|."ldapSslFingerprints"' $OUTFILE)
# Get Server UID
SERVER_UID=$(jq -r '.objects[]|.ldapServers[]|.server' $OUTFILE)
# Get server ip from management database...
SERVER_IP=$(curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/show-host -d '{ "uid" : "'$SERVER_UID'", "details-level" : "full" }' | jq -r '."ipv4-address"')
# ...and check LDAPS server certificate fingerprint
SERVER_FPRINT=$(echo -n | openssl s_client -connect $SERVER_IP:636 2>/dev/null | openssl x509 -noout -fingerprint -md5 | cut -f2 -d'=')

# Output: Warn if fingerprints dont match which normally means that certificate has been renewed
if [[ "$CP_FPRINT" = "$SERVER_FPRINT" ]]; then
    echo "Ok"
else
    echo "Fingerprint don't match. Refetch!"
fi

# Logout and delete session info file. Keep it for troubleshooting purposes, if unsuccessful
LOGOUT_MSG=$(curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/logout -d '{ }' | jq -r '."message"')
if [[ "$LOGOUT_MSG" = "OK" ]]; then
    rm $SESSION_INFO
else
    echo "Logout unsuccessful. Consider doing a manual logout (Session ID is in $SESSION_INFO)"
fi
