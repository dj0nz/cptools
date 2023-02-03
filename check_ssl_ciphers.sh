#!/bin/bash

# check ssl protocol and ciphers on a given target
# to use on non-checkpoint, remove ssl3 (current openssl doesn't
# support it any more) and replace "cpopenssl" with "openssl"
# dj0nz feb 2023 

if [[ ! $1 = "" ]]; then
    TARGET=$1
else
    echo "No target"
    exit 1
fi
REACH=`timeout 3 bash -c "</dev/tcp/$TARGET/443" 2>/dev/null &&  echo "Open"`
if [[ ! "$REACH" = "Open" ]]; then
    echo "Target unreachable. Exiting."
    exit 1
fi

for PROTO in ssl3 tls1 tls1_1 tls1_2 tls1_3; do
    CIPHER=`echo -n | cpopenssl s_client -connect $TARGET:443 -$PROTO 2>&1 | grep ^New | awk '{print $5}' | tr -d '()'`
    PROTOCOL=`echo -n | cpopenssl s_client -connect $TARGET:443 -$PROTO 2>&1 | grep Protocol | awk '{print $3}'`
    if [[ $PROTOCOL = "" ]]; then
        PROTOCOL=`echo $PROTO | tr '[:lower:]' '[:upper:]' | tr '_' '.' | sed 's/.../&v/'`
    fi
    if [[ "$CIPHER" == "NONE" ]]; then
        printf "%-10s %s\n" "$PROTOCOL" "Disabled"
    else
        printf "%-10s %s\n" "$PROTOCOL" "$CIPHER"
    fi
done
