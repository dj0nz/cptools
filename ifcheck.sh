#!/bin/bash

# Dieses Skript prüft, ob alle Cluster Interfaces korrekt verkabelt sind
#
# Das funktioniert NUR, wenn zwei Voraussetzungen gegeben sind:
# - Der Hostname des primären Cluster Members endet mit der Zahl Eins
# - Die IP-Adressen der Cluster Interfaces sind so konfiguriert, dass die des sekundären
#   Cluster Members im vierten Oktett genau um Eins erhöht ist
# Bitte nicht "Primär"/"Sekundär" mit "Active"/"Standby" verwechseln. Das ist was völlig anderes. ;)
#
# dj0Nz Mar 2026

# Primärer Member (Hostname endet mit "1")?
if [[ "$(hostname)" == *1 ]]; then
    MEMBER_STATE="Pri"
else
    MEMBER_STATE="Sec"
fi

# Liste von Cluster Interfaces generieren
IFLIST=$(cphaprob -a if | sed -n '/Virtual/,$p' | grep -E 'bond|eth' | awk '{print $1}')

echo "Checking Cluster Interface Connectivity"
for IF in $IFLIST; do
    # Lokale Interface IP ermitteln
    LOC_IP=$(ifconfig $IF | grep 'inet addr:' | awk '{print $2}' | cut -d ':' -f2)
    # Interface IP des anderen Cluster Members ermitteln
    if [[ $MEMBER_STATE == "Pri" ]]; then
        REM_IP=$(awk -F\. '{ print $1"."$2"."$3"."$4+1 }' <<< $LOC_IP )
    else
        REM_IP=$(awk -F\. '{ print $1"."$2"."$3"."$4-1 }' <<< $LOC_IP )
    fi
    # Wir versuchen einfach mal, ob der Legacy Auth Port offen ist. Ob die Verbindung
    # erfolgreich ist, ist egal: Der Verbindungsversuch erzeugt einen ARP-Eintrag...
    timeout 3 bash -c "</dev/tcp/$REM_IP/900" 2>/dev/null
    # ...den wir dann prüfen. Wenn "incomplete" dann nix Layer Zwo
    RESULT=$(arp -an -i $IF $REM_IP | grep incomplete)
    if [[ ! $RESULT == "" ]]; then
        printf "%-12s %s\n" "$IF:" "Partner not reached. Check interface!"
    else
        printf "%-12s %s\n" "$IF:" "Ok"
    fi
done
