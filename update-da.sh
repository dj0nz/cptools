#!/bin/bash

# Update Check Point CPUSE Deployment Agent on all cluster members.
#
# This script musst be run on the Check Point management server itself. It pushes the 
# Deployment Agent (DA) package to outdated gateways via CPRID and installs it.
#
# Use case: Update DA in airgapped environments. If your firewalls are internet-connected, 
# they automatically update DA based on the "Automatically update Deployment Agent" policy
# 
# Prerequisites:
# - Download current DA package, see https://support.checkpoint.com/results/sk/sk92449
# - Copy to /var/log/tmp on your management server
# - Adjust $TARGET_VERSION and $AGENT_FILE
#
# Additional requirements:
# This script ONLY works correctly, if the management server knows all managed gateways by
# name, which, unfortunately, is not a given. See https://github.com/dj0nz/cptools/blob/main/add-gw-hostnames.sh 

# mgo jun 2026

# See https://disconnected.systems/blog/another-bash-strict-mode/
# 'set -e' is omitted on purpose: cprid_util returns non-zero on benign conditions and the arithmetic counters would abort the run.
set -uo pipefail

# shellcheck source=/dev/null
. /etc/profile.d/CP.sh

# CPRID port and binary
# See https://www.compuquip.com/blog/daemon-firewall-system for examples
PORT=18208
CPRID="$CPDIR/bin/cprid_util"
# Target version of the Deployment Agent
TARGET_VERSION=2771
AGENT_FILE="/var/log/tmp/DeploymentAgent_000002771_1.tgz"
# No DA update on these machines
BLACKLIST="example1 example2"

# Tunables
TCP_TIMEOUT=2          # cprid reachability probe (seconds)
INSTALL_TIMEOUT=120    # hard limit for the interactive installer (seconds)
POLL_TRIES=18          # post-install status polls
POLL_WAIT=5            # wait between polls (seconds)

# Local package must exist before we touch any gateway
[[ -f "$AGENT_FILE" ]] || { echo "Agent file $AGENT_FILE not found. Aborting."; exit 1; }

# Collect cluster members only, excluding standalone gateways and the mgmt itself. If you have standalone gateways, just
# expand the select statement with 'select ((."type" == "cluster-member") or (."type" == "simple-gateway"))'
GW_LIST=($(mgmt_cli -r true show gateways-and-servers limit 500 -f json | jq -r '.objects[]|select(.type=="cluster-member")|.name'))

[[ ${#GW_LIST[@]} -gt 0 ]] || { echo "No cluster members returned by mgmt_cli. Aborting."; exit 1; }

# Query installed DA build on a gateway. Echoes build number or empty string.
get_da_version() {
    local GW="$1"
    "$CPRID" -server "$GW" rexec -rcmd da_cli da_status 2>/dev/null | jq -r '.DABuildNumber' 2>/dev/null
}

# The update deployment agent function, essentially the heart of the program
update_deployment_agent() {
    local GW="$1"
    local OLD_VERSION="$2"

    # Skip the rest of the function if file cannot be copied
    if ! "$CPRID" -server "$GW" -verbose putfile -local_file "$AGENT_FILE" -remote_file "$AGENT_FILE"; then
        printf "%-20s %s\n" "$GW:" "File copy failed. Gateway skipped."
        return 1
    fi

    printf "%-20s %s" "$GW:" "Updating Agent from $OLD_VERSION to $TARGET_VERSION..."

    # Wrapped in timeout so a stuck rexec cannot block the whole run.
    timeout "$INSTALL_TIMEOUT" "$CPRID" -server "$GW" rexec -rcmd /bin/clish -c "installer agent install $AGENT_FILE" >/dev/null 2>&1

    # Da restarts after update, catch new version info
    local NEW_VERSION=""
    local i
    # A simple "sleep" might not be enough or too much, so poll until it answers with the target build
    for ((i=0; i<POLL_TRIES; i++)); do
        NEW_VERSION=$(get_da_version "$GW")
        [[ "$NEW_VERSION" == "$TARGET_VERSION" ]] && break
        sleep "$POLL_WAIT"
    done

    if [[ "$NEW_VERSION" == "$TARGET_VERSION" ]]; then
        echo "Ok"
        return 0
    else
        echo "CPUSE not updated!"
        return 1
    fi
}

TOTAL=0
OUTDATED=0
UPDATED=0

echo ""
echo "Deployment Agent Update"
echo "-----------------------"
for GW in "${GW_LIST[@]}"; do
    [[ " ${BLACKLIST,,} " == *" ${GW,,} "* ]] && continue
    ((++TOTAL))

    if ! timeout "$TCP_TIMEOUT" bash -c "</dev/tcp/$GW/$PORT" 2>/dev/null; then
        printf "%-20s %s\n" "$GW:" "Unreachable"
        continue
    fi

    VERSION=$(get_da_version "$GW")
    if [[ -z "$VERSION" ]]; then
        printf "%-20s %s\n" "$GW:" "PARSE_ERROR"
    elif [[ "$VERSION" == "$TARGET_VERSION" ]]; then
        printf "%-20s %s\n" "$GW:" "Target version already installed"
    else
        ((++OUTDATED))
        update_deployment_agent "$GW" "$VERSION" && ((++UPDATED))
    fi
done

echo ""
echo "$UPDATED of $OUTDATED gateways updated"