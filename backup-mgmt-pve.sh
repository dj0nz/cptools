#!/bin/bash

# Backup a Check Point Management Server running on a Proxmox VE host
#
# Check Point currently doesn't have QEMU/KVM guest utilities activated. Doing backups while the
# system is running may wreak havoc to filesystems and/or backups. This script does a manual shutdown
# of the management server processes (cpstop), stops the vm and creates a backup if all this shutdown stuff completed successfully.
#
# Parameters:
# MGMT_VMID: The VM ID of the Management Server VM
# MGMT_NAME: Hostname of the Mangement Server
# CPSTOP_TIMEOUT: Time limit for the cpstop command. Maybe more time needed for larger deployments
# SHUTDOWN_TIMEOUT: Time limit for the shutdown command (seconds). Maybe more time needed for larger deployments
# STORAGE: The storage location for backups (pbs, cifs, cephfs etc.). List with "pvesm status"
# KEEP: The number of backups to retain
# LOGFILE: Guess what this is (output goes there)
#
# Requirements:
# - Check Point Management VM ssh port must be reachable from the Proxmox Host itself
# - Configure pubkey auth between PVE host and Check Point Management VM
# - Backup storage must already be set up and usable
#
# Usage:
# copy shell script to the PVE node the VM is running on and schedule with cron. Make sure, ssh is working.
#
# dj0Nz Nov 2024

MGMT_VMID="501"
MGMT_NAME="mgmt"
CPSTOP_TIMEOUT="5m"
SHUTDOWN_TIMEOUT=300
STORAGE="pbs"
KEEP="3"
LOGFILE=/var/log/backup-$MGMT_VMID.log

# Reset log
cat /dev/null > $LOGFILE
echo "$(date) - Starting Backup of VM $MGMT_VMID" >> $LOGFILE 2>&1

# Check if VM is running
RUNNING=$(qm status $MGMT_VMID | cut -d ' ' -f2)
if [[ $RUNNING = "running" ]]; then
    # issue cpstop and wait for "SVN Foundation stopped" or 5 minutes timeout whatever comes first
    STOP_RESULT=$(timeout $CPSTOP_TIMEOUT ssh -q admin@$MGMT_NAME "cpstop" 2>&1 | grep "SVN Foundation stopped")
    # Shutdown VM if cpstop successful
    if [[ $STOP_RESULT = "SVN Foundation stopped" ]]; then
        qm shutdown $MGMT_VMID >> $LOGFILE 2>&1
        STOP_TIME=$(expr $(date +%s) + $SHUTDOWN_TIMEOUT)
        # Wait until shutdown finished or exit if timer expired
        while [ $RUNNING = "running" ]; do
            RUNNING=$(qm status $MGMT_VMID | cut -d ' ' -f2)
            CURR_TIME=$(date +%s)
            if [[ $CURR_TIME -gt $STOP_TIME ]]; then
                echo "VM did not stop in time. Exiting." >> $LOGFILE 2>&1
                exit 1
            fi
        done
    else
        # Try to restart Check Point processes if stop command unsuccessful to restore functionality.
        # Rebooting the machine would be another option in this case...
        echo "cpstop command failed. Restarting Check Point processes." >> $LOGFILE 2>&1
        ssh -q admin@$MGMT_NAME "cpstart" >> $LOGFILE 2>&1
        exit 1
    fi
fi

# do backup:
vzdump $MGMT_VMID --storage $STORAGE --notes-template {\{\guestname}} --prune-backups keep-last=$KEEP >> $LOGFILE 2>&1

# restart vm:
qm start $MGMT_VMID >> $LOGFILE 2>&1

echo "$(date) - Backup of VM $MGMT_VMID finished" >> $LOGFILE 2>&1
