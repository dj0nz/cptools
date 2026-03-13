#!/bin/bash

# MDPS diagnostics: List processes that runin a given namespace (mplane or dplane)
# See https://www.gilesthomas.com/2021/03/fun-with-network-namespaces for namespace basics and explanations
#
# List namespaces:
# ip netns list
#
# Defaults by Check Point:
# CTX00000 - Data Plane
# CTX00001 - Management Plane
#
# dj0nz mar 2026

NAMESPACE=$1

if [[ $NAMESPACE == "CTX00000" || $NAMESPACE == "CTX00001" ]]; then
    # Get target namespace inode
    TARGET=$(ip netns exec $NAMESPACE readlink /proc/self/ns/net)
    if [[ $TARGET == "" ]]; then
        echo "Namespace inode not found"
        exit 1
    fi
else
    echo "Missing parameter (Namespace). Should be one of the following:"
    echo "CTX00000 - Data Plane"
    echo "CTX00001 - Management Plane"
    exit 1
fi

# List all processes in namespace
for pid in /proc/[0-9]*/ns/net; do
    if [ "$(readlink $pid)" = "$TARGET" ]; then
        p=${pid//\/ns\/net/}
        p=${p//\/proc\//}
        echo "PID $p: $(cat /proc/$p/comm 2>/dev/null)"
    fi
done

