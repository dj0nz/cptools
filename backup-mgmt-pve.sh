#!/bin/bash

# Backup Check Point Management VM
#
# This script stops a Check Point Management VM running on a given Proxmox VE node, creates a full backup using vzdump and restarts the VM afterwards.
# Configure it to run at your preferred backup schedule on a Linux machine that has both ssh access to the Check Point Management and https (Port 8006/tcp) 
# access the the Proxmox cluster member running the machine.
#
# Requirements:
# - A linux machine that is able to reach the Check Point Management via ssh and the
#   Proxmox VE cluster nodes via https using 8006/tcp
# - curl and jq installed on that machine
# - A working SSH pubkey login to the Check Point Management VM (implies admin rights)
# - A working PVE API Token with appropriate rights to start/stop the Check Point
#   Management Server VM and do backups using vzdump
# - Names must be resolvable by host name (non-fqdn, adjust search in resolv.conf)
#
# Parameters:
# - TOKENFILE:        File containing PVE API Token
# - PXNODE:           PVE node running the Check Point Management VM
# - MGMT_NAME:        Hostname of the Check Point Management VM
# - VMID:             Proxmox VM ID of the Check Point Management VM
# - CPSTOP_TIMEOUT:   Time needed to complete the cpstop command. All timeouts should be measured and adjust accordingly.
# - SHUTDOWN_TIMEOUT: Time needed for the Management VM to shut down.
# - BACKUP_TIMEOUT:   Time needed for the backup job to complete. 
# - STORAGE:          Storage type for the dump files. Check with "pvesm list" or ask your PVE admin
# - KEEP:             Number of backups to retain
# - LOGFILE:          An optional log file. You may also decide to devnull all messages and rely on your network monitoring. it's up to you. 
#
# dj0Nz Nov 2024

TOKENFILE=.token
PXNODE="pxnode"
MGMT_NAME="mgmt"
VMID="404"
CPSTOP_TIMEOUT="5m"
SHUTDOWN_TIMEOUT=300
BACKUP_TIMEOUT=3600
STORAGE="pbs"
KEEP="3"
LOGFILE=/var/log/backup-$MGMT_NAME.log

# Redirect all output to log file, mark job start
exec >> $LOGFILE 2>&1
echo "$(date) - Check Point Management Backup Start"

# Read API token from file
if [[ -f $TOKENFILE ]]; then
    TOKEN=$(cat $TOKENFILE)
else
    echo "No token file found."
    exit 1
fi

# BASE URL for API requests
BASE_URL=https://$PXNODE:8006/api2/json

# curl header and options - add "--insecure" in opts if using selfsigned certs
OPTS="--silent --insecure"
HEADER="Authorization: PVEAPIToken=$TOKEN"

# Get Management VM status
VM_STATE=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/qemu/$VMID/status/current|jq -r '.data.status')

# Process next block only if VM is on
if [[ $VM_STATE = "running" ]]; then
    echo "$(date) - Issuing cpstop"
    # issue cpstop and wait for "SVN Foundation stopped" or (preconfigured) 5 minutes timeout whatever comes first
    STOP_RESULT=$(timeout $CPSTOP_TIMEOUT ssh -q admin@$MGMT_NAME "cpstop" 2>&1 | grep "SVN Foundation stopped")
    # Shutdown VM if cpstop successful
    if [[ $STOP_RESULT = "SVN Foundation stopped" ]]; then
        echo "$(date) - Shutting down VM $VMID"
        VM_SHUTDOWN=$(curl -X POST $OPTS -H "$HEADER" --data timeout=$SHUTDOWN_TIMEOUT $BASE_URL/nodes/$PXNODE/qemu/$VMID/status/shutdown)
        STOP_TIME=$(expr $(date +%s) + $SHUTDOWN_TIMEOUT)
        # Wait until shutdown finished or exit if timer expired
        while [ $VM_STATE = "running" ]; do
            VM_STATE=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/qemu/$VMID/status/current|jq -r '.data.status')
            CURR_TIME=$(date +%s)
            # Stop this script completely if shutdown fails.
	    if [[ $CURR_TIME -gt $STOP_TIME ]]; then
                echo "VM did not stop in time. Exiting."
                exit 1
            fi
        done
        # Needed later to determine if VM has to be restarted
	WAS_ON="Yes"
    else
        # Try to restart Check Point processes if stop command unsuccessful to restore functionality.
        # Rebooting the machine would be another option in this case...
        echo "cpstop command failed. Restarting Check Point processes."
        ssh -q admin@$MGMT_NAME "cpstart"
        exit 1
    fi
else
    echo "VM ist not running"
    WAS_ON="No"
fi

# If we got here, machine did either shutdown correctly or was already off
# Define backup request data
URL_DATA="--data vmid=$VMID --data storage=$STORAGE --data-urlencode notes-template="{{guestname}}" --data-urlencode prune-backups="keep-last=$KEEP""

# Start backup request with preconfigured body, returns only the task "UPID"
echo "$(date) - Starting backup job"
DUMP_UPID=$(curl -X POST $OPTS -H "$HEADER" $URL_DATA $BASE_URL/nodes/$PXNODE/vzdump|jq -r .data)

# Use UPID to query task state, should be "running" initially...
DUMP_STATE=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/tasks/$DUMP_UPID/status|jq -r .data.status)
# Define time when backup job should be considered as "timed out"
STOP_TIME=$(expr $(date +%s) + $BACKUP_TIMEOUT)

while [ $DUMP_STATE = "running" ]; do
    CURR_TIME=$(date +%s)
    # Refresh job status
    DUMP_STATE=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/tasks/$DUMP_UPID/status|jq -r .data.status)
    # Delay to prevent this script from asking too often
    sleep 3
    # Just exit with error if backup job does not finish in time
    if [[ $CURR_TIME -gt $STOP_TIME ]]; then
        echo "Backup did not finish in time. Exiting."
        exit 1
    fi
done

# Restart VM if it has been on before
if [[ $WAS_ON = "Yes" ]]; then
    echo "$(date) - Restating VM $VMID"
    VM_START=$(curl -X POST $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/qemu/$VMID/status/start)
fi
# Mark backup job end
echo "$(date) - Check Point Management Backup End"
