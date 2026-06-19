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
# - PXNODE:           PVE node running the Check Point Management VM. Must be set in config file.
# - MGMT_NAME:        Hostname of the Check Point Management VM. Must be set in config file.
# - VMID:             Proxmox VM ID of the Check Point Management VM. Must be set in config file.
# - BACKUP_USER:      A user that is able to connect to the Check Point Management using SSH pubkey auth (needs bash login shell)
# - CPSTOP_TIMEOUT:   Time needed to complete the cpstop command. All timeouts should be measured and adjusted accordingly.
# - SHUTDOWN_TIMEOUT: Time needed for the Management VM to shut down.
# - BACKUP_TIMEOUT:   Time needed for the backup job to complete.
# - STORAGE:          Storage type for the dump files. Check with "pvesm list" or ask your PVE admin
# - KEEP:             Number of backups to retain
# - LOGFILE:          An optional log file. You may also decide to devnull all messages and rely on your network monitoring. it's up to you.
#
# dj0Nz Nov 2024 / reviewed Jun 2026

# Check if config file there
CONFIG="${1:?Usage: $0 <config-file>}"
[[ -f "$CONFIG" ]] || { echo "Config file $CONFIG not found." >&2; exit 1; }
source "$CONFIG"

# Parameters, that must be set in config file
PXNODE="${PXNODE:?PXNODE must be set in $CONFIG}"
MGMT_NAME="${MGMT_NAME:?MGMT_NAME must be set in $CONFIG}"
VMID="${VMID:?VMID must be set in $CONFIG}"

# Defaults if not set in config file
TOKENFILE="${TOKENFILE:-.token}"
BACKUP_USER="${BACKUP_USER:-admin}"
CPSTOP_TIMEOUT="${CPSTOP_TIMEOUT:-5m}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-300}"
BACKUP_TIMEOUT="${BACKUP_TIMEOUT:-3600}"
STORAGE="${STORAGE:-pbs}"
KEEP="${KEEP:-3}"
LOGFILE="${LOGFILE:-/var/log/backup-$MGMT_NAME.log}"

# Redirect all output to log file, mark job start
exec >> "$LOGFILE" 2>&1
echo "$(date) - Check Point Management Backup Start"

# Prevent overlapping runs from interleaving VM stop/start calls or starting a second vzdump job against the same VMID
LOCKFILE=/var/lock/backup-$MGMT_NAME.lock
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "$(date) - Another instance is already running. Exiting."
    exit 1
fi

# Read API token from file
if [[ -f $TOKENFILE ]]; then
    TOKEN=$(cat "$TOKENFILE")
else
    echo "$(date) - No token file found."
    exit 1
fi

# Check if Proxmox Node reachable
if ! timeout 3 bash -c "</dev/tcp/$PXNODE/8006" 2>/dev/null; then
    echo "$(date) - Server $PXNODE unreachable. Exiting."
    exit 1
fi

# Check if Check Point Management reachable
if ! timeout 3 bash -c "</dev/tcp/$MGMT_NAME/22" 2>/dev/null; then
    echo "$(date) - Server $MGMT_NAME unreachable. Exiting."
    exit 1
fi

# Check if SSH pubkey login possible to Check Point Management
if ! ssh -q -o BatchMode=yes -o PasswordAuthentication=no -o StrictHostKeyChecking=accept-new "$BACKUP_USER@$MGMT_NAME" 'exit 0'; then
    echo "$(date) - No ssh login to $MGMT_NAME possible. Exiting."
    exit 1
fi

# BASE URL for API requests
BASE_URL=https://$PXNODE:8006/api2/json

# curl header and options
# Remove --insecure once PVE presents a certificate this host actually trusts
OPTS="--silent --insecure"
HEADER="Authorization: PVEAPIToken=$TOKEN"

# Get Management VM status
VM_STATE=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/qemu/$VMID/status/current | jq -r '.data.status')

# Defensive check: empty or "null" means the API call itself failed (auth error, network issue, wrong VMID)
if [[ -z "$VM_STATE" || "$VM_STATE" = "null" ]]; then
    echo "$(date) - Could not determine VM state via API. Aborting."
    exit 1
fi

# Process next block only if VM is on
if [[ $VM_STATE = "running" ]]; then
    echo "$(date) - Issuing cpstop"
    # Issue cpstop and wait for "SVN Foundation stopped" or the configured timeout,whatever comes first
    if timeout $CPSTOP_TIMEOUT ssh -q -o BatchMode=yes $BACKUP_USER@$MGMT_NAME "cpstop" 2>&1 | grep -q "SVN Foundation stopped"; then
        echo "$(date) - Shutting down VM $VMID"
        # Extract the UPID and verify it's actually there.
        VM_SHUTDOWN=$(curl -X POST $OPTS -H "$HEADER" --data timeout=$SHUTDOWN_TIMEOUT $BASE_URL/nodes/$PXNODE/qemu/$VMID/status/shutdown | jq -r .data)
        if [[ -z "$VM_SHUTDOWN" || "$VM_SHUTDOWN" = "null" ]]; then
            echo "$(date) - Shutdown API call did not return a task ID. Aborting."
            exit 1
        fi
        STOP_TIME=$(( $(date +%s) + SHUTDOWN_TIMEOUT ))
        # Wait until shutdown finished or exit if timer expired.
        while [[ "$VM_STATE" = "running" ]]; do
            sleep 3
            VM_STATE=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/qemu/$VMID/status/current | jq -r '.data.status')
            CURR_TIME=$(date +%s)
            # Stop this script completely if shutdown fails.
            if [[ $CURR_TIME -gt $STOP_TIME ]]; then
                echo "$(date) - VM did not stop in time. Exiting."
                exit 1
            fi
        done
        # Needed later to determine if VM has to be restarted
        WAS_ON="Yes"
    else
        # Try to restart Check Point processes if stop command unsuccessful to restore functionality.
        echo "$(date) - cpstop command failed. Restarting Check Point processes."
        ssh -q -o BatchMode=yes $BACKUP_USER@$MGMT_NAME "cpstart"
        exit 1
    fi
else
    echo "$(date) - VM is not running"
    WAS_ON="No"
fi

# If we got here, machine did either shutdown correctly or was already off
# Define parameters for the backup api call
VZDUMP_PARAMS=(
    --data            "vmid=$VMID"
    --data            "storage=$STORAGE"
    --data-urlencode  "notes-template={{guestname}}"
    --data-urlencode  "prune-backups=keep-last=$KEEP"
)

# Start backup request with preconfigured body, returns only the task "UPID"
echo "$(date) - Starting backup job"
DUMP_UPID=$(curl -X POST $OPTS -H "$HEADER" "${VZDUMP_PARAMS[@]}" $BASE_URL/nodes/$PXNODE/vzdump | jq -r .data)

# Use UPID to query task state, should be "running" initially...
DUMP_STATE=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/tasks/$DUMP_UPID/status | jq -r .data.status)
# Define time when backup job should be considered as "timed out"
STOP_TIME=$(( $(date +%s) + BACKUP_TIMEOUT ))

while [[ "$DUMP_STATE" = "running" ]]; do
    CURR_TIME=$(date +%s)
    # Refresh job status
    DUMP_STATE=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/tasks/$DUMP_UPID/status | jq -r .data.status)
    # Delay to prevent this script from asking too often
    sleep 3
    # Just exit with error if backup job does not finish in time
    if [[ $CURR_TIME -gt $STOP_TIME ]]; then
        echo "$(date) - Backup did not finish in time. Exiting."
        exit 1
    fi
done

# Proxmox reports the actual result in "exitstatus" ("OK" on success, an error string otherwise)
DUMP_RESULT=$(curl -X GET $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/tasks/$DUMP_UPID/status | jq -r .data.exitstatus)
if [[ "$DUMP_RESULT" != "OK" ]]; then
    echo "$(date) - Backup job failed: $DUMP_RESULT"
    BACKUP_FAILED="Yes"
fi

# Restart VM if it has been on before
if [[ $WAS_ON = "Yes" ]]; then
    echo "$(date) - Restarting VM $VMID"
    VM_START=$(curl -X POST $OPTS -H "$HEADER" $BASE_URL/nodes/$PXNODE/qemu/$VMID/status/start | jq -r .data)
    if [[ -z "$VM_START" || "$VM_START" = "null" ]]; then
        echo "$(date) - VM restart API call did not return a task ID. Check VM $VMID manually."
        RESTART_FAILED="Yes"
    fi
fi

# Mark backup job end, exit non-zero if the vzdump job did not report "OK" or the VM restart could not be confirmed
if [[ "$BACKUP_FAILED" = "Yes" || "$RESTART_FAILED" = "Yes" ]]; then
    echo "$(date) - Check Point Management Backup End - FAILED"
    exit 1
fi
echo "$(date) - Check Point Management Backup End"
