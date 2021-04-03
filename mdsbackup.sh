#!/bin/bash

# Check Point MDM Backup
# 
# Version 0.1
# 
# dj0Nz (djonz@posteo.de)
# April 2021
#
# Lizenz siehe https://unlicense.org/ 

# Check Point Umgebungsvariablen. Weiss nicht, ob man die noch braucht, schaden aber nicht...
. /opt/CPshared/5.0/tmp/.CPprofile.sh

# Server, User und Verzeichnis für SCP Upload. Wenn nicht gesetzt, liegen die Backups in $BKPDIR
SERVER=""
USERNAME=""
DIRECTORY=""

# Liste von Management Domains erstellen. Achtung: Das gute alte "MDSVERUTIL AllCMAs" funktioniert an
# der Stelle nicht, da das Backup via API die Domain als Argument braucht. Alles neu macht der Mai.
DMLIST=`mgmt_cli -r true show domains | grep -B 1 'type: "domain"' | grep name | awk '{print $2}' | tr -d '"'`

TMPDIR=/var/log/tmp
BKPDIR=/var/log/tmp/backup
BKPLOG=/var/log/mdsbackup.log
BKPDAY=`date +%a`
BKPDOM=`date +%d`
BKPMON=`date +%b`

exec > $BKPLOG 2>&1

echo "START MDS Backup `\date`"

if [ -d $BKPDIR ]; then
   rm -rf $BKPDIR
fi
mkdir $BKPDIR

cd $TMPDIR

# Ist heute Sonntag? Dann hab ich Zeit...
if [[ "$BKPDAY" = "Sun" ]]; then
   mds_backup -b -l -d $BKPDIR
   # Systenmzeugs sichern: Versionsinformationen, Gaia Config (Interfaces, Routen etc.), Skripte in /home/admin
   fwm ver -f ver.txt
   clish -c "lock database override"
   clish -c "show version all" >> ver.txt
   cpinfo -y all >> ver.txt
   clish -c "save configuration $HOSTNAME-config"
   tar cvf system.tar /etc/*
   tar cvf home.tar /home/*
   tar czf $BKPDIR/$HOSTNAME-System-Backup.tgz ver.txt $HOSTNAME-config system.tar home.tar
   rm ver.txt
   rm $HOSTNAME-config
   rm system.tar 
   rm home.tar
else
   # Wochentags nur Managemennt Domains sichern (sk156072) 
   for i in $DMLIST; do
       # Nonprintables entfernen, sonst nix gut
       # Weiss der Henker was für kranke Sonderzeichen ein mgmt_cli zurück gibt und vor allem warum... :-/
       DOM=`tr -dc '[[:print:]]' <<< "$i"`
       mgmt_cli -r true backup-domain domain $DOM file-path $BKPDIR/$DOM-backup.tgz
   done
fi

echo "Sicherung speichern in $TMPDIR/$HOSTNAME-Backup-$BKPMON-$BKPDOM.tgz"
tar cfz $HOSTNAME-Backup-$BKPMON-$BKPDOM.tgz $BKPDIR/*

# Sicherung auf dem Backup Server kopieren, wenn dieser konfiguriert ist.
if [[ "$SERVER" = "" ]]; then
   echo "Kein Backup Server angegeben."
else
   echo "Sichere auf Backup Server $SERVER."
   scp -q $HOSTNAME-Backup-$BKPMON-$BKPDOM.tgz $USERNAME@$SERVER:$DIRECTORY
   rm $HOSTNAME-Backup-$BKPMON-$BKPDOM.tgz
fi

echo "MDS Backup ENDE `\date`"
