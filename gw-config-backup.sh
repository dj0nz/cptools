#!/bin/bash

# Check Point Firewall Module Backup
#
# Runs locally on Smartcenter.
# Copy to desired destination (e.g. /home/admin/scripts) and chmod 700
# Schedule to run weekly or monthly. Example: 
# add cron job Modulebackup command "/home/admin/gw-config-backup.sh" recurrence weekly days 0 time 23:30
# Backups got to $BKPDIR
# 
# Michael Goessmann Matos, NTT Data - Feb 2023

. /etc/profile.d/CP.sh

# Get Gateway list (Cluster members only)
GW_LIST=(`mgmt_cli -r true show gateways-and-servers limit 500 --format json | $CPDIR/jq/jq -r '.objects[]| select(.type | contains("cluster-member"))|.name'`)
PORT=18208
BKPDIR=/home/admin/module-config
LOGFILE=/var/log/gw-config-backup.log

# Uncomment to send output to logfile after testing
# exec > $LOGFILE 2>&1

if [ ! -d $BKPDIR ]; then
    mkdir -p $BKPDIR
fi

for INDEX in "${GW_LIST[@]}"; do
    # Remove nonprintables, does not work otherwise.
    GW=`tr -dc '[[:print:]]' <<< "$INDEX"`
    # Only try to backup if there is a host entry for this gateway.
    HOSTS=`clish -c "show configuration host" | grep $GW | awk '{print $4}'`
    if [[ ! "$HOSTS" = "$GW" ]]; then
        GW_UID=`mgmt_cli -r true show cluster-members --format json | $CPDIR/jq/jq -r --arg GW "$GW" '.objects[] | select(.name | contains($GW))|.uid'`
        GW_IP=`mgmt_cli -r true show cluster-member uid "$GW_UID" --format json | $CPDIR/jq/jq -r '."ip-address"'`
        printf "%-17s %s\n" "$GW: " "creating hosts entry"
        clish -s -c "add host name $GW ipv4-address $GW_IP"
    fi
    # Check if CPRID port open.
    OPEN=`timeout 3 bash -c "</dev/tcp/$GW/$PORT" 2>/dev/null && echo "Open" || echo "Closed"`
    if [[ "$OPEN" = "Open" ]]; then
        LOCKED=`$CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show config-state" | grep owned`
	    if [[ $LOCKED ]]; then
            $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "lock database override" > /dev/null 2>&1
        fi
        printf "%-17s %s\n" "$GW: " "Saving configuration backup to $BKPDIR"
        $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show configuration" > $BKPDIR/$GW.cfg
        $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show asset all" > $BKPDIR/$GW.info
        $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show version all" >> $BKPDIR/$GW.info
        # Optionally get LOM IP (next four lines)
        # $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd service ipmi start > /dev/null
        # LOMIP=`$CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd ipmitool lan print 8 | grep 'IP Address' | grep -v Source | awk '{print $4}'`
        # echo "LOM IP Address: $LOMIP" >> $BKPDIR/$GW.info
        # $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd service ipmi stop > /dev/null
        echo "" >> $BKPDIR/$GW.info
        JUMBO=`$CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd cpinfo -y fw1 2>&1 | grep JUMBO | awk '{print $3}'`
        echo "Installed Jumbo Take: $JUMBO" >> $BKPDIR/$GW.info
        echo "" >> $BKPDIR/$GW.info
    else
        printf "%-17s %s\n" "$GW: " "Unreachable"
    fi
done
