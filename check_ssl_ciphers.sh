#!/bin/bash

for PROTO in ssl3 tls1 tls1_1 tls1_2; do
   CIPHER=`cpopenssl s_client -connect 127.0.0.1:443 -$PROTO 2>&1 | grep ^New | awk '{print $5}' | tr -d '()'`
   PROTOCOL=`cpopenssl s_client -connect 127.0.0.1:443 -$PROTO 2>&1 | grep Protocol | awk '{print $3}'`
   if [[ "$CIPHER" == "NONE" ]]; then
      printf "%-8s %s\n" "$PROTOCOL:" "Disabled"
   else
      printf "%-8s %s\n" "$PROTOCOL:" "$CIPHER"
   fi
done
