#!/bin/bash

# Check Point MDM Backup
#
# Skript auf MDM System kopieren, ausführbar machen und per Clish täglich einplanen:
# Beispiel: add cron job Backup command /home/admin/mdsback.sh recurrence daily time 01:30
# Aufpassen: Die Backup Files in $TMPDIR im Auge behalten, wenn kein Scp Server konfiguriert ist,
# sonst liegen da irgendwann mal ~365 Backup Files rum und die Platte ist voll. Siehe Logwork Orange.
# 
# dj0Nz (djonz@posteo.de)
# April 2021
# Version 0.4
#
# Lizenz siehe https://unlicense.org/ 

# Check Point Umgebungsvariablen laden
. /opt/CPshared/5.0/tmp/.CPprofile.sh

# Server, User und Verzeichnis für SCP Upload. Wenn nicht gesetzt, liegen die Backups in $TMPDIR
SERVER=""
USERNAME=""
DIRECTORY=""

# Liste von Management Domains erstellen
DMLIST=`$MDSVERUTIL AllCMAs`

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
   echo "Checkpoint Version Information" >> ver.txt
   echo "---" >> ver.txt
   fwm ver >> ver.txt
   clish -c "lock database override"
   echo "---" >> ver.txt
   clish -c "show version all" >> ver.txt
   echo "---" >> ver.txt
   cpinfo -y all >> ver.txt
   echo "---" >> ver.txt
   mdsstat >> ver.txt
   clish -c "save configuration $HOSTNAME-config"
   echo "System Information" >> sysinfo.txt
   echo "---" >> sysinfo.txt
   cat /proc/meminfo >> sysinfo.txt
   echo "---" >> sysinfo.txt
   cat /proc/cpuinfo >> sysinfo.txt
   echo "---" >> sysinfo.txt
   fdisk -l >> sysinfo.txt
   echo "---" >> sysinfo.txt
   df -h >> sysinfo.txt
   echo "---" >> sysinfo.txt
   ifconfig -a >> sysinfo.txt
   echo "---" >> sysinfo.txt
   netstat -rn >> sysinfo.txt
   echo "---" >> sysinfo.txt
   uname -a >> sysinfo.txt
   tar cvf system.tar /etc/*
   tar cvf home.tar /home/*
   tar czf $BKPDIR/$HOSTNAME-System-Backup.tgz ver.txt sysinfo.txt $HOSTNAME-config system.tar home.tar
   rm ver.txt
   rm sysinfo.txt
   rm $HOSTNAME-config
   rm system.tar 
   rm home.tar
else
   # Wochentags nur Management Domains sichern
   for DM in $DMLIST; do
      echo "Domain $DM wird gesichert"
      mdsstop_customer $DM
      mdsenv $DM
      $FWDIR/bin/upgrade_tools/migrate export -n $BKPDIR/$DM
      mdsstart_customer $DM
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
