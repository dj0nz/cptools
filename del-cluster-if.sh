#!/bin/bash

# VRRP CLuster Interface löschen mit Sosse und alles und scharf.
# dj0Nz Mai 2024

# Variablen:
# PROXYARP = Alle NAT-IPs, für die ein Proxy ARP Eintrag auf dem betreffenden Interface erstellt wurde (show arp proxy ...)
# LOCALNET = Der Netzwerk-Teil des betreffenden Interfaces (Nur für /24-Netze!) 
# VLAN und INTERFACE sind ja selbsterklärend...
PROXYARP="192.168.3.113 192.168.3.116"
LOCALNET="192.168.16"
VLAN="16"
INTERFACE="eth5"

# Schritt 1: Konfiguration sichern
if [[ -f proxyarp.cfg ]]; then
    rm proxyarp.cfg
fi
for IP in $PROXYARP; do
    clish -c "show configuration arp proxy" | grep $IP >> proxyarp.cfg
done
clish -c "show configuration static-route" | grep $LOCALNET > staticroute.cfg
clish -c "show configuration interface" | grep $INTERFACE | grep vlan > vlan.cfg
clish -c "show configuration interface" | grep $INTERFACE.$VLAN > interface.cfg
clish -c "show configuration mcvr" | grep $LOCALNET > mcvr.cfg

# Schritt2: Kommandos für das Entfernen "bauen"
cat proxyarp.cfg | cut -d ' ' -f1-5 | sed 's/add/delete/' > proxyarp.del
cat staticroute.cfg | sed 's/on/off/' > staticroute.del
cat mcvr.cfg | sed 's/add/delete/' > mcvr.del
cat interface.cfg | grep ipv4 | cut -d ' ' -f1-4 | sed 's/set/delete/' > interface.del
cat vlan.cfg | sed 's/add/delete/' > vlan.del

# Schritt 3: Konfigurationen entfernen. Ginge auch mit einer For-Schleife.
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
