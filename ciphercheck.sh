#!/bin/bash

# Check Point Firewall SSL Cipher Check
# Runs on a linux client, reads a list of all gateways from Check Point management database and checks SSL ciphers on the gateways
#
# Requirements:
#
# - This script should be run on a Linux box with https access to both firewall management and all managed firewalls
# - Tools needed locally: openssl, curl, gpg, jq
# - An API user with appropriate permissions (read all is enough) at the Check Point management server
# - API key stored in a local file ($CP_API_KEY_ENC), symmetrically encrypted with gpg
#
# Fun fact: Check Point has a ... special wording for rotten ciphers:
# https://support.checkpoint.com/results/sk/sk147272
#
# This is enabled by default:
# SSLCipherSuite HIGH:!RC4:!LOW:!EXP:!aNULL:!SSLv2:!MD5
# SSLProtocol -ALL {ifcmp = $httpd:ssl3_enabled 1}+{else}-{endif}SSLv3 +TLSv1.3 +TLSv1.2
#
# Not a ciphersuite I would expect on a security product.
# 
# I would rather use:
# SSLCipherSuite ECDHE-RSA-AES256-SHA384:AES256-SHA256:!ADH:!EXP:RSA:+HIGH:!MEDIUM:!MD5:!LOW:!NULL:!SSLv2:!eNULL:!aNULL:!RC4:!SHA1
# SSLProtocol +TLSv1.2 +TLSv1.3
#
# See sk cited above how to change or use cipherchange.sh in this repo.
# But be aware: As soon as you enable VPN Blade / Remote Access, you're in rotten cipher hell again...

# dj0Nz jun 2023

# Get a list of all locally available ciphers ($1) with protocol ($2)
OPENSSL_BIN=$(which openssl)
if [[ $OPENSSL_BIN ]]; then
    CIPHERS=($($OPENSSL_BIN ciphers -v | awk '{print $1 ":" $2}'))
    for CIPHER in ${CIPHERS[@]}; do
        CHECK=$(echo $CIPHER | grep -E 'TLS|SSL')
        if [[ ! $CHECK ]]; then
            echo "Unknown cipher format: $CIPHER"
            exit 1
        fi
    done
else
    echo "No openssl binary found. Exiting."
    exit 1
fi

# Check other requirements
CURL_BIN=$(which curl)
if [[ ! $$CURL_BIN ]]; then
    echo "Curl binary not found. Exiting."
    exit 1
fi
GPG_BIN=$(which gpg)
if [[ ! $GPG_BIN ]]; then
    echo "Gpg binary not found. Exiting."
    exit 1
fi
JQ_BIN=$(which jq)
if [[ ! $JQ_BIN ]]; then
    echo "Jq binary not found. Exiting."
    exit 1
fi

# Check Point management server IP address. Must be reachable on port 443/tcp
CP_MGMT="192.168.1.11"
CP_REACH=$(timeout 3 bash -c "</dev/tcp/$CP_MGMT/443" 2>/dev/null &&  echo "Open")
if [[ ! "$CP_REACH" = "Open" ]]; then
    echo "Checkpoint Management unreachable. Exiting."
    exit 1
fi

# Encrypted API key file. Should have been encrypted using something like "gpg -c api-key" beforehand...
CP_API_KEY_ENC=api-key.gpg
if [[ ! -f $CP_API_KEY_ENC ]]; then
    echo "Encrypted Checkpoint API key file ($CP_API_KEY_ENC) not found. Exiting."
    exit 1
fi

echo "Gateway cipher check script"
echo ""
echo "Decrypting API key and logging in to Check Point Management"

# API key decrypt section. Note: Reading the decryption passphrase using a read call may be considered unsafe, 
# but AFAIK there's no other way if you want to customize the "enter passphrase" prompt...
# The safer default: API_KEY=$(gpg --pinentry-mode=loopback --no-symkey-cache -qd $CP_API_KEY_ENC 2>/dev/null)
read -r -s -p 'Enter API key decryption passphrase: ' DECPASS
API_KEY=$($GPG_BIN --pinentry-mode=loopback --no-symkey-cache --batch --passphrase "$DECPASS" -qd $CP_API_KEY_ENC 2>/dev/null)
echo ""
DECPASS=""

# Temporary file to store session information
SESSION_INFO=session-info.txt
# API login to Check Point management.
$CURL_BIN -X POST -H "content-Type: application/json" --silent -k https://$CP_MGMT/web_api/login -d '{ "api-key" : "'$API_KEY'" }' > $SESSION_INFO
# Grab session id from login file
SESSION_ID=$($JQ_BIN -r '.sid | select( . != null )' $SESSION_INFO)
# Proceed only if login successful
if [[ ! $SESSION_ID ]]; then
    echo ""
    echo "Login failed. Check $SESSION_INFO file"
    exit 1
else
    rm $SESSION_INFO
fi

echo ""
echo "Getting gateway objects and checking https access. Please wait..."
echo ""

# Get Check Point gateway names and ip addresses from management database
# store api request output to temporary file
OBJECTS=gwlist.json
$CURL_BIN -X POST -H "Content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT:443/web_api/show-gateways-and-servers -d '{ "details-level" : "full", "limit" : "500" }' -o $OBJECTS
# Check number of gateways in output...
NUMGWS=$($JQ_BIN -r '."objects"[] | select ((."type" == "cluster-member") or (."type" == "simple-gateway")) | ."name"' gwlist.json 2>/dev/null | wc -l)
# ...and proceed only if gateways found
if [[ $NUMGWS -gt 0 ]]; then
    GW_LIST+=($($JQ_BIN -r '."objects"[] | select ((."type" == "cluster-member") or (."type" == "simple-gateway")) | [.["name"], .["ipv4-address"]] | @csv' $OBJECTS | tr -d '"'))
    rm $OBJECTS
else
    echo ""
    echo "No gateways found in Check Point database. Check $OBJECTS file for API request output."
    exit 1
    LOGOUT_MSG=$($CURL_BIN -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/logout -d '{ }' | $JQ_BIN -r '."message"')
    if [[ ! "$LOGOUT_MSG" = "OK" ]]; then
        echo "Logout unsuccessful. Consider doing a manual logout."
    fi
fi

# Log ciphers found on gateway to file
LOGFILE=gatewayciphers.txt
if [[ -f $LOGFILE ]]; then
    rm $LOGFILE
fi
touch $LOGFILE
echo "SSL Cipher scan `date`" > $LOGFILE

echo "Checking ciphers on gateways:"
echo ""

# Sort of counter: there's at least one gateway with non-compliant ciphers if > 0
UNSAFE_GWS=0

# Loop through gateway list and check available ciphers
for GW in "${GW_LIST[@]}"; do
    GW_IP=$(echo $GW | cut -d ',' -f2)
    GW_NAME=$(echo $GW | cut -d ',' -f1)
    # Don't try if port not open
    OPEN=$(timeout 3 bash -c "</dev/tcp/$GW_IP/443" 2>/dev/null && echo "Open")
    if [[ ! "$OPEN" = "Open" ]]; then
        echo ""
        echo "Host $GW_NAME unreachable"
        continue
    else
        # Check if host supports TLSv1.3
        TLS13=$(echo Q | timeout 2 $OPENSSL_BIN s_client -connect $GW_IP:443 -tls1_3 2>/dev/null | grep New | grep 1.3)
        echo "$GW_NAME:" >> $LOGFILE
        UNSAFE=0
        for INDEX in ${CIPHERS[@]}; do
            # Extract cipher and protocol from current cipher/protocol string
            CIDX=$(echo $INDEX | awk -F ":" '{print $1}')
            PIDX=$(echo $INDEX | awk -F ":" '{print $2}')
            # Different commands needed for TLS 1.3 and lower protocols
            if [[ "$PIDX" == "TLSv1.3" ]]; then
                if [[ $TLS13 ]]; then
	                # Command returns a line containing protocol and cipher. Uppercase "Q" terminates the request.
	                LINE=$(echo Q | timeout 2 $OPENSSL_BIN s_client -connect $GW_IP:443 -ciphersuites $CIDX 2>/dev/null | grep ^New)
	            fi
            else
	            # The no_tls1_3 switch is needed to prevent fallback to "better" ciphers
                LINE=$(echo Q | timeout 2 $OPENSSL_BIN s_client -connect $GW_IP:443 -no_tls1_3 -cipher $CIDX 2>/dev/null | grep ^New)
            fi
            # Prettify output 
            if [[ ! "$LINE" =~ "NONE" ]]; then
	            AR_LINE=(${LINE// / }) 
	            PROTO=$(echo ${AR_LINE[1]} | sed 's/,//')
	            CIPHER=${AR_LINE[4]}
	            if [[ $CIPHER ]]; then
	                printf "%-8s %s\n" "$PROTO" "$CIPHER" >> $LOGFILE
                    if [[ ! "$PROTO" = "TLSv1.2" ]]; then
                        let "UNSAFE+=1"
                    fi
	            fi
            fi
        done
        echo "" >> $LOGFILE
        if [[ $UNSAFE -gt 0 ]]; then
            printf "%-15s %s\n" "$GW_NAME:" "Non-compliant ciphers."
	    let "UNSAFE_GWS+=1"
        else
            printf "%-15s %s\n" "$GW_NAME:" "OK"
        fi
    fi
done
echo ""

if [[ $UNSAFE_GWS -gt 0 ]]; then
    echo "Gateway with non-compliant ciphers found. See $LOGFILE file for details."
    echo ""
fi
 
# Logout
LOGOUT_MSG=$($CURL_BIN -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/logout -d '{ }' | $JQ_BIN -r '."message"')
if [[ ! "$LOGOUT_MSG" = "OK" ]]; then
    echo "Logout unsuccessful. Consider doing a manual logout."
fi
