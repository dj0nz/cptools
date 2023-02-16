#!/bin/bash

# Check Point management server backup script
# 
# Requirements: 
# - Check Point Management Server R81.x (-> migrate server)
# - a host to copy the backup to using scp
# - a user with public key auth on the destination host (ssh-copy-id is your friend)
#
# Installation:
# - copy script to /home/admin and chmod 700
# - modify backup destination server section
# - schedule to run daily at night
# 
# Notes:
# - check log and backup files on a regular basis
# - do a restore test at least once a year to make sure you are able to restore anything needed
# - make sure you don't have important files in $TMPDIRECTORY before installing and running this script
# - backup files get rotated automatically (naming scheme: $HOSTNAME-<Day-Of-Month>.tar)
# 
# Michael Goessmann Matos / NTT
# Feb 2023

# backup destination server
SERVER=<backup server ip or hostname>
USERNAME=<user with pubkey auth>
DIRECTORY=<remote directory>

# local directories and other stuff
CP_BACKUP_DIR=/var/log/CPbackup/backups/
TMPDIRECTORY=/var/log/tmp/backup
BKP_LOG=/var/log/sysbackup.log
BKP_DAY=`date +%d`

# determine checkpoint version
CPVER=`rpm -qa | grep CPsuite | awk -F'-' '{print $2}'`

# load checkpoint environment
. /etc/profile.d/CP.sh

# create a clean log file
if [ -f $BKP_LOG ]; then
    cat /dev/null > $BKP_LOG
else
    touch $BKP_LOG
fi

# redirect all non-devnulled output to logfile 
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

# unlock if config locked
LOCKED=`clish -c "show config-state" | grep owned`
if [[ $LOCKED ]]; then
    clish -c "lock database override"
fi

# version and system info
echo "Version information:" >> ver.txt
clish -c "show version all" >> ver.txt
echo "" >> ver.txt
JUMBO=`cpinfo -y fw1 2>&1 | grep JUMBO | awk '{print $3}'`
echo "Installed Jumbo Take: $JUMBO" >> ver.txt
echo "" >> ver.txt
echo "System information:" >> ver.txt
clish -c "show asset all" >> ver.txt
df -h >> ver.txt

# system conf. can be useful to recover a system.
tar cvPf etc.tar /etc

# backup user homes
tar rvfP home.tar /home

# gaia config backup
clish -c "save configuration $HOSTNAME-config"

# checkpoint system and product backup
printf "y \n" | /bin/backup -f $HOSTNAME-cpbackup > /dev/null 2>&1
mv $CP_BACKUP_DIR/$HOSTNAME-cpbackup.tgz $TMPDIRECTORY/

# create export file
$FWDIR/scripts/migrate_server export -v $CPVER -n -skip_upgrade_tools_check --ignore_warnings -npb $TMPDIRECTORY/$HOSTNAME-export.tgz > /dev/null 2>&1

# packaging...
tar cvf $HOSTNAME-$BKP_DAY.tar ver.txt etc.tar home.tar $HOSTNAME-config $HOSTNAME-cpbackup.tgz
if [ -f $HOSTNAME-export.tgz ]; then
   tar rvf $HOSTNAME-$BKP_DAY.tar $HOSTNAME-export.tgz
fi
md5sum $HOSTNAME-$BKP_DAY.tar > $HOSTNAME-$BKP_DAY.md5

# ...and upload
scp -q $TMPDIRECTORY/$HOSTNAME-$BKP_DAY.tar $USERNAME@$SERVER:$DIRECTORY/$HOSTNAME-$BKP_DAY.tar
scp -q $TMPDIRECTORY/$HOSTNAME-$BKP_DAY.md5 $USERNAME@$SERVER:$DIRECTORY/$HOSTNAME-$BKP_DAY.md5

echo "---------------------------------------------------------"
echo "Backup END `\date`"
