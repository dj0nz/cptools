#!/bin/bash

# Check Point Firewall Module Backup
#
# Skript nach /home/admin kopieren & chmod 700
# Die Backups landen dann in dem in $CFG_PATH definierten Verzeichnis
# Einplanen mit add cron job Modulebackup command "/home/admin/gw-config-backup.sh" recurrence weekly days 0 time 23:30
# Voraussetzung: Für das zu sichernde Gateway muss bereits ein Hosts-Eintrag existieren.
# Siehe dazu auch add-gw-hostnames.sh
# 
# Michael Goessmann Matos, NTT - Mar 2021

. /opt/CPshared/5.0/tmp/.CPprofile.sh

# Liste von Gateways aus der Check Point Datenbank extrahieren
GW_LIST=(`mgmt_cli -r true show gateways-and-servers limit 500 | egrep -B 1 'cluster-member|simple-gateway' | grep name | awk '{print $2}' | tr -d '"'`)
PORT=18208
CFG_PATH=/home/admin/module-config

if [ ! -d $CFG_PATH ]; then
   mkdir -p $CFG_PATH
fi

for INDEX in "${GW_LIST[@]}"; do
   # Nonprintable entfernen, sonst klappt das nicht. Warum auch immer.
   GW=`tr -dc '[[:print:]]' <<< "$INDEX"`
   # Gibts fuer das Gateway einen Hosts-Eintrag? Backup nur dann versuchen.
   HOSTS=`clish -c "show configuration host" | grep $GW | awk '{print $4}'`
   if [[ "$HOSTS" = "$GW" ]]; then
      # Config Backup via cprid_util versuchen, wenn der CPRID Port offen ist.
      OPEN=`timeout 3 bash -c "</dev/tcp/$GW/$PORT" 2>/dev/null && echo "Open" || echo "Closed"`
      if [[ "$OPEN" = "Open" ]]; then
         $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show configuration" > $CFG_PATH/$GW.cfg
      else
         printf "%-17s %s\n" "$GW: " "Unreachable"
      fi
   fi
done
