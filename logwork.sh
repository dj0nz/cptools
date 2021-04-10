#!/bin/bash

# LOGWORK ORANGE - disk space desaster prevention
# Delete Checkpoint firewall logfiles older than $RETIME days on SmartCenter
#
# dj0Nz
# June 2017

# variables
ORANGE=/var/log/logwork.log
RETIME="365"
TMPDIR=/var/log/tmp/logwork

# load Checkpoint enviroment
. /opt/CPshared/5.0/tmp/.CPprofile.sh

exec > $ORANGE 2>&1

echo "---------------------------------------------------------" 
echo "[`\date`] Logwork Orange START" 

if [ -d $TMPDIR ]; then
   rm -r $TMPDIR
fi
mkdir $TMPDIR
cd $TMPDIR

NUM_FILES=`/usr/bin/find $FWDIR/log/ -type f -iname *\.log -mtime +$RETIME -print | wc -l` 

if [ $NUM_FILES -gt 0 ]; then
   echo "[`\date`] Removing files older than $RETIME days..." 
   for EXT in logptr log log_stats logaccount_ptr loginitial_ptr; do
       echo ""
       echo "Removing *.$EXT files"
       /usr/bin/find $FWDIR/log/ -type f -iname *\.$EXT -mtime +$RETIME -print | xargs rm 
   done
else
   echo "Nothing to remove yet..." 
fi

echo ""
echo "[`\date`] Logwork Orange END"
