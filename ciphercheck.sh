#!/bin/bash

# Check Point Firewall SSL Cipher Check
# Reads cluster members from database and checks SSL ciphers
#
# Fun fact: Check Point has a ... special wording for rotten ciphers:
# https://support.checkpoint.com/results/sk/sk147272
#
# This is enabled by default:
# SSLCipherSuite HIGH:!RC4:!LOW:!EXP:!aNULL:!SSLv2:!MD5
# SSLProtocol -ALL {ifcmp = $httpd:ssl3_enabled 1}+{else}-{endif}SSLv3 +TLSv1.3 +TLSv1.2
#
# :facepalm:
# 
# I would use:
# SSLCipherSuite ECDHE-RSA-AES256-SHA384:AES256-SHA256:!ADH:!EXP:RSA:+HIGH:!MEDIUM:!MD5:!LOW:!NULL:!SSLv2:!eNULL:!aNULL:!RC4:!SHA1
# SSLProtocol +TLSv1.2 +TLSv1.3
#
# BUT: As soon as you enable VPN Blade / Remote Access, you're in rotten cipher hell again...

# dj0Nz jun 2023

# Get a list of all locally available ciphers ($1) with protocol ($2)
OPENSSL_BIN=$(which openssl)
if [[ $OPENSSL_BIN ]]; then
    CIPHERS=($(openssl ciphers -v | awk '{print $1 ":" $2}'))
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

# API key decrypt section. Note: Reading the decryption passphrase using a read call may be considered unsafe, 
# but AFAIK there's no other way if you want to customize the "enter passphrase" prompt...
# The safer default: API_KEY=`gpg --pinentry-mode=loopback --no-symkey-cache -qd $CP_API_KEY_ENC 2>/dev/null`
read -r -s -p 'Enter API key decryption passphrase: ' DECPASS
API_KEY=$(gpg --pinentry-mode=loopback --no-symkey-cache --batch --passphrase "$DECPASS" -qd $CP_API_KEY_ENC 2>/dev/null)
echo ""
DECPASS=""

# API login to Check Point management.
SESSION_ID=$(curl -X POST -H "content-Type: application/json" --silent -k https://$CP_MGMT/web_api/login -d '{ "api-key" : "'$API_KEY'" }' | jq -r .sid)

# Get Check Point cluster object names and extract cluster member names and ip addresses from cluster definition
CLUSTERS=$(curl -X POST -H "Content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT:443/web_api/show-simple-clusters -d ' { }'| jq -r '.objects[].name')
for CLUSTER in $CLUSTERS; do
    MEMBERS=$(curl -X POST -H "Content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT:443/web_api/show-simple-cluster -d '{ "name" : "'$CLUSTER'" }' | jq -r '."cluster-members"[] | [."name", ."ip-address"] | @csv' | tr -d '"')
done 

# Loop through cluster member list and check available ciphers
for MEMBER in $MEMBERS; do
    MEMBER_IP=$(echo $MEMBER | cut -d ',' -f2)
    MEMBER_NAME=$(echo $MEMBER | cut -d ',' -f1)
    # Don't try if port not open
    OPEN=$(timeout 3 bash -c "</dev/tcp/$MEMBER_IP/443" 2>/dev/null && echo "Open")
    if [[ ! "$OPEN" = "Open" ]]; then
        echo "Host $MEMBER_NAME unreachable"
        continue
    else
        # Check if host supports TLSv1.3
        TLS13=$(echo Q | timeout 2 openssl s_client -connect $MEMBER_IP:443 -tls1_3 2>/dev/null | grep New | grep 1.3)
        echo ""
        echo "Gateway: $MEMBER_NAME"
        for INDEX in ${CIPHERS[@]}; do
            # Extract cipher and protocol from current cipher/protocol string
            CIDX=$(echo $INDEX | awk -F ":" '{print $1}')
            PIDX=$(echo $INDEX | awk -F ":" '{print $2}')
            # Different commands needed for TLS 1.3 and lower protocols
            if [[ "$PIDX" == "TLSv1.3" ]]; then
                if [[ $TLS13 ]]; then
	                # Command returns a line containing protocol and cipher. Uppercase "Q" terminates the request.
	                LINE=$(echo Q | timeout 2 openssl s_client -connect $MEMBER_IP:443 -ciphersuites $CIDX 2>/dev/null | grep ^New)
	            fi
            else
	            # The no_tls1_3 switch is needed to prevent fallback to "better" ciphers
                LINE=$(echo Q | timeout 2 openssl s_client -connect $MEMBER_IP:443 -no_tls1_3 -cipher $CIDX 2>/dev/null | grep ^New)
            fi
            # Prettify output (or ease further processing)
            if [[ ! "$LINE" =~ "NONE" ]]; then
	            AR_LINE=(${LINE// / }) 
	            PROTO=$(echo ${AR_LINE[1]} | sed 's/,//')
	            CIPHER=${AR_LINE[4]}
	            if [[ $CIPHER ]]; then
	                printf "%-8s %s\n" "$PROTO" "$CIPHER"
	            fi
            fi
        done
    fi
done
echo ""

# Logout
LOGOUT_MSG=$(curl -X POST -H "content-Type: application/json" -H "X-chkp-sid:$SESSION_ID" --silent -k https://$CP_MGMT/web_api/logout -d '{ }' | jq -r '."message"')
if [[ ! "$LOGOUT_MSG" = "OK" ]]; then
    echo "Logout unsuccessful. Consider doing a manual logout."
fi
