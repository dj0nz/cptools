#!/bin/bash

# Backup a Check Point VM on a Proxmox node 
#
# This is the quick-and-dirty-version of the backup-mgmt-pve.sh script. It runs on the Proxmox node hosting 
# the VM and does not need any API or OS level permissions. It relies on the Gaia OS to correctly terminate all 
# Check Point processes on a shutdown request by the hypervisor, which is the case in current version (R82)
#
# A dedicated "qm stop/start" is not needed here because a vzdump in stop mode already works like that:
# - ACPI-Shutdown the VM (if it's on) 
# - Wait $STOPWAIT minutes for the shutdown to complete
# - Run vzdump and prune if necessary
# - Start the VM, if it was on before
#
# dj0Nz jun 2026 

VMID="404"
STOPWAIT="5"
STORAGE="pbs"
KEEP="3"
LOGFILE="/var/log/backup-vm$VMID.log"

# redirect all output to log file
exec >> "$LOGFILE" 2>&1

# prevent a second instance to run by placing a (more or less) random file descriptor on a lock file
LOCKFILE=/var/lock/backup-vm$VMID.lock
exec 200>"$LOCKFILE"
flock -n 200 || { echo "$(date) - Another instance running. Exiting."; exit 1; }

# do a vzdump backup in stop mode and remove fd on lock file when finished
echo "$(date) - Backup Start"
vzdump "$VMID" --storage "$STORAGE" --mode stop --stopwait "$STOPWAIT" --notes-template '{{guestname}}' --prune-backups "keep-last=$KEEP" 200>&- || BACKUP_FAILED="Yes"

[[ "$BACKUP_FAILED" = "Yes" ]] && { echo "$(date) - Backup End - FAILED"; exit 1; }
echo "$(date) - Backup End"
