#!/bin/bash

# VRRP Cluster Interface wiederherstellen, das mit del-cluster-if gelöscht wurde.
# dj0Nz Mai 2024

ITEMS="vlan interface proxyarp staticroute mcvr"
for ITEM in $ITEMS; do
    echo "Wiederherstellen ($ITEM)... "
    clish -f $ITEM.cfg
    rm $ITEM.del
done
echo "Konfiguration speichern"
clish -c "save config"
