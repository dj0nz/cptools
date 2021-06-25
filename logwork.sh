#!/bin/bash

# Firewall Logfile Cleanup
#
# Michael Goessmann Matos, NTT
# Maerz 2021

# Variablen
RETIME="300"
CP_VERSION=R80.40
EXT=log
LOGFILE=/var/log/orange.log

exec > $LOGFILE 2>&1

NUM_FILES=`/usr/bin/find /var/log/opt/CPsuite-$CP_VERSION/fw1/log/ -type f -name "*.$EXT" -mtime +$RETIME -print | wc -l`
DISK_SPACE=`df -h | grep log | awk '{print $4}'`

if [ $NUM_FILES -gt 0 ]; then
   echo "Entferne alte Check Point Logfiles"
   echo ""
   echo "Anzahl Dateien:    $NUM_FILES"
   echo "Version:           $CP_VERSION"
   echo "Retention Time:    $RETIME Tage"
   echo "Plattenplatz Alt:  $DISK_SPACE"
   for EXT in logptr log log_stats logaccount_ptr loginitial_ptr; do
       echo ""
       echo "Entferne *.$EXT Dateien"
       /usr/bin/find /var/log/opt/CPsuite-$CP_VERSION/fw1/log/ -type f -name "*.$EXT" -mtime +$RETIME -print -exec rm {} \;
   done
   DISK_SPACE=`df -h | grep log | awk '{print $4}'`
   echo ""
   echo "Plattenplatz Neu:  $DISK_SPACE"
else
   echo "Nichts zu loeschen..."
fi

echo ""
