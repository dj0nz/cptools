#!/bin/bash

# Check Point Management Server Backup
# Michael Goessmann Matos / NTT
# Feb 2023

# determine checkpoint version
CPVER=`rpm -qa | grep CPsuite | awk -F'-' '{print $2}'`

# load checkpoint environment
. /etc/profile.d/CP.sh

# variables
#SERVER=<BACKUP-SERVER>
#USERNAME=<USER>
DIRECTORY=/backup
CP_BACKUP_DIR=/var/log/CPbackup/backups/
TMPDIRECTORY=/var/log/tmp/backup
BKP_LOG=/var/log/sysbackup.log
BKP_DAY=`date +%d`

# create a clean log file
if [ -f $BKP_LOG ]; then
    if [ -f $BKP_LOG.2 ]; then
       mv $BKP_LOG.2 $BKP_LOG.3
    fi
    if [ -f $BKP_LOG.1 ]; then
        mv $BKP_LOG.1 $BKP_LOG.2
    fi
    if [ -f $BKP_LOG.0 ]; then
       mv $BKP_LOG.0 $BKP_LOG.1
    fi
    mv $BKP_LOG $BKP_LOG.0
    cat /dev/null > $BKP_LOG
    chmod 644 $BKP_LOG
else
    touch $BKP_LOG
fi

exec > $BKP_LOG 2>&1

# timestamp: backup begin
echo "---------------------------------------------------------"
echo "Backup START `\date`"

# create clean temporary directory
if [ -d $TMPDIRECTORY ]; then
    rm -r $TMPDIRECTORY
fi
mkdir $TMPDIRECTORY
cd $TMPDIRECTORY

LOCKED=`clish -c "show config-state" | grep owned`
if [[ $LOCKED ]]; then
    clish -c "lock database override"
fi

# Version and disk space info
clish -c "show version all" >> ver.txt
cpinfo -y fw1 2>&1 >> ver.txt
df -h >> ver.txt

# system specific. maybe useful...
tar cvPf sys.tar /etc
tar rvfP sys.tar /home/admin
tar rvfP sys.tar /root

# gaia config backup
clish -c "save configuration $HOSTNAME-config"

# checkpoint system and product backup
printf "y \n" | /bin/backup -f $HOSTNAME-cpbackup 2>/dev/null
mv $CP_BACKUP_DIR/$HOSTNAME-cpbackup.tgz $TMPDIRECTORY/

# create export file
$FWDIR/bin/upgrade_tools/migrate export -n $TMPDIRECTORY/$HOSTNAME-export.tgz

# packaging...
tar cvf $HOSTNAME-$BKP_DAY.tar ver.txt sys.tar $HOSTNAME-config $HOSTNAME-cpbackup.tgz
if [ -f $HOSTNAME-export.tgz ]; then
   tar rvf $HOSTNAME-$BKP_DAY.tar $HOSTNAME-export.tgz
fi
md5sum $HOSTNAME-$BKP_DAY.tar > $HOSTNAME-$BKP_DAY.md5

# ...and upload
#scp -q $TMPDIRECTORY/$HOSTNAME-$BKP_DAY.tar $USERNAME@$SERVER:$DIRECTORY/$HOSTNAME-$BKP_DAY.tar
#scp -q $TMPDIRECTORY/$HOSTNAME-$BKP_DAY.md5 $USERNAME@$SERVER:$DIRECTORY/$HOSTNAME-$BKP_DAY.md5

echo "---------------------------------------------------------"
echo "Backup END `\date`"
