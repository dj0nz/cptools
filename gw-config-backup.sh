#!/bin/bash

# Gateway module backup
# - Should run locally on Smartcenter
# - Queries all gateway cluster members from database using API
# - Collects gateway Gaia configs and version info using CPRID
# - Files go to $BKPDIR
# - Gateway host names get added if missing
#
# Install
# - Copy script to desired destination (e.g. /home/admin/scripts) and chmod 700
# - Schedule to run weekly or monthly. Example: add cron job Modulebackup command "/home/admin/gw-config-backup.sh" recurrence weekly days 0 time 23:30
# - Include $BKPDIR in management server backup
#
# Note 
# This is an additional quick-and-dirty-backup for all firewall modules. In most cases, the data collected by this script 
# is enough to restore a gateway completely in case of hardware failure or misconfiguration. BUT: If you modified files 
# directly on the gateway (e.g. fwkern.conf, local.arp, trac_client1) you should have these changes documented AND I would 
# strongly recommend doing gateway full backups at least monthly. See sk108902 for additional information.
# 
# Michael Goessmann Matos, NTT Data - Feb 2023

. /etc/profile.d/CP.sh

# Get Gateway list (Cluster members only) from database
# In the unlikely event you have un-clustered firewalls, you can get all gateways with "(contains("cluster-member") or contains("simple-gateway")))"
# But: You will have to change the "add host name" logic then, too
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
    # Remove nonprintables, does not work otherwise
    GW=`tr -dc '[[:print:]]' <<< "$INDEX"`
    # Add host name entry for this gateway if missing
    HOSTS=`clish -c "show configuration host" | grep $GW | awk '{print $4}'`
    if [[ ! "$HOSTS" = "$GW" ]]; then
        GW_UID=`mgmt_cli -r true show cluster-members --format json | $CPDIR/jq/jq -r --arg GW "$GW" '.objects[] | select(.name | contains($GW))|.uid'`
        GW_IP=`mgmt_cli -r true show cluster-member uid "$GW_UID" --format json | $CPDIR/jq/jq -r '."ip-address"'`
        printf "%-17s %s\n" "$GW: " "creating hosts entry"
        clish -s -c "add host name $GW ipv4-address $GW_IP"
    fi
    # Check if CPRID port open
    OPEN=`timeout 3 bash -c "</dev/tcp/$GW/$PORT" 2>/dev/null && echo "Open" || echo "Closed"`
    if [[ "$OPEN" = "Open" ]]; then
        # Remove configuration lock. You may also just skip current $GW with error if configuration is locked.
        LOCKED=`$CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show config-state" | grep owned`
	    if [[ $LOCKED ]]; then
            $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "lock database override" > /dev/null 2>&1
        fi
        printf "%-17s %s\n" "$GW: " "Saving configuration backup to $BKPDIR"
        $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show configuration" > $BKPDIR/$GW.cfg
        $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show asset all" > $BKPDIR/$GW.info
        $CPDIR/bin/cprid_util -server $GW -verbose rexec -rcmd clish -c "show version all" >> $BKPDIR/$GW.info
        # Optionally get LOM IP (next four lines). Deactivated because this works only with gateways containing LOM hardware
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
