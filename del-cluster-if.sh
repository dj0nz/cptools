#!/bin/bash

# VRRP CLuster Interface löschen mit Sosse und alles und scharf.
# dj0Nz Mai 2024

# Variablen:
# LOCALNET = Der Netzwerk-Teil des betreffenden Interfaces
# VLAN und INTERFACE sind eh klar
LOCALNET="192.168.101"
VLAN="101"
INTERFACE="bond0"
IPADDR=$(clish -c "show interface $INTERFACE.$VLAN ipv4-address" | awk '{ print $2 }')

# Schritt 1: Konfiguration sichern
echo "Sichere Konfigurationen..."
clish -c "show configuration arp proxy" | grep $LOCALNET > proxyarp.cfg
clish -c "show configuration static-route" | grep $LOCALNET > staticroute.cfg
clish -c "show configuration interface" | grep $INTERFACE | grep vlan | grep $VLAN > vlan.cfg
clish -c "show configuration interface" | grep $INTERFACE.$VLAN > interface.cfg
clish -c "show configuration mcvr" | grep $LOCALNET > mcvr.cfg

# Schritt2: Kommandos für das Entfernen "bauen"
cat proxyarp.cfg | cut -d ' ' -f1-5 | sed 's/add/delete/' > proxyarp.del
cat staticroute.cfg | sed 's/on/off/' > staticroute.del
cat mcvr.cfg | sed 's/add/delete/' | sed "s/$IPADDR.*$/$IPADDR/g" > mcvr.del
cat interface.cfg | grep ipv4 | cut -d ' ' -f1-4 | sed 's/set/delete/' > interface.del
cat vlan.cfg | sed 's/add/delete/' > vlan.del

# Schritt 3: Konfigurationen entfernen.
read -p "Interface $INTERFACE.$VLAN entfernen? " YESNO
if [[ $YESNO =~ ^(y|Y|yes|Yes|j|J|ja|Ja)$ ]]; then
    echo "Entferne Proxy ARP Eintraege..."
    clish -f proxyarp.del
    echo "Entferne statische Routen..."
    clish -f staticroute.del
    echo "Entferne Cluster-VIP..."
    clish -f mcvr.del
    echo "Entferne IP-Adresse von Interface $INTERFACE..."
    clish -f interface.del
    echo "Entferne VLAN $VLAN..."
    clish -f vlan.del
    echo "Konfiguration speichern"
    clish -c "save config"
else
    echo "Abbruch"
fi
