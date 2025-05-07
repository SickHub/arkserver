#!/usr/bin/env bash

# Define directories
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPODIR="$(dirname "$SCRIPTDIR")"
ARKSERVER=${ARKSERVER_SHARED:-"/ark/server"}

# Always fail script if a command fails
set -eo pipefail

echo "###########################################################################"
echo "# Ark Server - $(date)"
echo "###########################################################################"

# Determine if the user has root or sudo privileges
if sudo -n true 2>/dev/null; then
    HAS_PRIVILEGES="true"
    echo "Detected sudo-capable user... Continuing with elevated privileges."
else
    HAS_PRIVILEGES="false"
    echo "Detected non-sudo user... Proceeding with limited permissions."
fi

# Fix ownership/permissions if possible
if [ "$HAS_PRIVILEGES" = "true" ]; then
    echo "Fixing ownership under /ark and /home/steam..."
    sudo find /ark -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
    sudo find /home/steam -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
else
    echo "Skipping chown: insufficient privileges."
fi

# Check for shared server path mount
if [ -n "$ARKSERVER_SHARED" ]; then
    if [ "$HAS_PRIVILEGES" = "true" ] && [ -d "$ARKSERVER_SHARED/ShooterGame" ]; then
        echo "Fixing ownership for shared ShooterGame directory..."
        sudo chown steam:steam "$ARKSERVER_SHARED/ShooterGame"
    fi
    echo "Shared server directory detected at $ARKSERVER_SHARED"

    echo "Checking if Saved directory is mounted..."
    if ! mount | grep -q "on $ARKSERVER_SHARED/ShooterGame/Saved "; then
        echo "===> ABORT!"
        echo "Expected mount at '$ARKSERVER_SHARED/ShooterGame/Saved' not found."
        echo "Please ensure your game instance's Saved directory is mounted correctly."
        exit 1
    fi

    export am_arkStagingDir=
fi

# Cluster setup
if [ "$ARKCLUSTER" = "true" ]; then
    echo "ARKCLUSTER enabled, verifying cluster mount..."

    if [ "$HAS_PRIVILEGES" = "true" ] && [ -d "$ARKSERVER/ShooterGame/Saved" ]; then
        sudo chown steam:steam "$ARKSERVER/ShooterGame/Saved"
    fi

    echo "Cluster files should be at $ARKSERVER/ShooterGame/Saved/clusters"

    if ! mount | grep -q "on $ARKSERVER/ShooterGame/Saved/clusters "; then
        echo "===> ABORT!"
        echo "ARKCLUSTER is enabled, but no mount found at '$ARKSERVER/ShooterGame/Saved/clusters'"
        exit 1
    fi
fi

# Cleanup old lock/pid files to avoid startup issues
echo "Cleaning up stale arkmanager lock and PID files..."
rm -vf $ARKSERVER/ShooterGame/Saved/.ark-warn-main.lock 2>/dev/null || true
rm -vf $ARKSERVER/ShooterGame/Saved/.ark-update.lock 2>/dev/null || true
rm -vf $ARKSERVER/ShooterGame/Saved/.ark-update.time 2>/dev/null || true
rm -vf $ARKSERVER/ShooterGame/Saved/.arkmanager-main.pid 2>/dev/null || true
rm -vf $ARKSERVER/ShooterGame/Saved/.arkserver-main.pid 2>/dev/null || true
rm -vf $ARKSERVER/ShooterGame/Saved/.autorestart 2>/dev/null || true
rm -vf $ARKSERVER/ShooterGame/Saved/.autorestart-main 2>/dev/null || true

# Ensure essential directories exist
for dir in /ark/config /ark/log /ark/backup /ark/staging; do
    if [ ! -d "$dir" ]; then
        echo "Creating missing directory: $dir"
        mkdir -p "$dir"
    fi
done

# Setup for fresh install if binaries missing
if [ ! -d "$ARKSERVER/ShooterGame/Binaries" ]; then
    echo "Game binaries not found. Preparing server directory structure..."
    mkdir -p "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer"
    mkdir -p "$ARKSERVER/ShooterGame/Saved/$am_ark_AltSaveDirectoryName"
    mkdir -p "$ARKSERVER/ShooterGame/Content/Mods"
    mkdir -p "$ARKSERVER/ShooterGame/Binaries/Linux/"
fi

echo "Generating arkmanager.cfg from environment..."
echo -e "# Ark Server Tools config\n# Generated from container environment\n" > /ark/config/arkmanager.cfg
[ -f /ark/config/arkmanager_base.cfg ] && cat /ark/config/arkmanager_base.cfg >> /ark/config/arkmanager.cfg
echo -e "\narkserverroot=\"$ARKSERVER\"\n" >> /ark/config/arkmanager.cfg
printenv | sed -n -r 's/am_(.*)=(.*)/\1=\"\2\"/ip' >> /ark/config/arkmanager.cfg

# Handle cron setup if crontab writable
if [ -w /var/spool/cron/crontabs/ ]; then
    echo "Filesystem is hardened; skipping crontab setup."
else
    if [ ! -f /ark/config/crontab ]; then
        echo "Creating default crontab..."
        cat <<EOF > /ark/config/crontab
*/30 * * * * arkmanager update --update-mods --warn --saveworld
10 */8 * * * arkmanager saveworld && arkmanager backup
15 10 * * * arkmanager restart --warn --saveworld
EOF
    fi

    CRONNUMBER=$(grep -v "^#" /ark/config/crontab | wc -l)
    if [ "$CRONNUMBER" -gt 0 ]; then
        echo "Loading and starting cron with $CRONNUMBER entries..."
        if [ "$HAS_PRIVILEGES" = false ]; then
            echo "Starting cron in background (non-root)..."
            cron && tail -f /dev/null &
        else
            echo "Starting cron service (sudo)..."
            sudo service cron start
        fi
        crontab /ark/config/crontab
    else
        echo "No valid (uncommented) crontab entries found."
    fi
fi

# Create config symlinks
ln -sf /ark/config/AllowedCheaterSteamIDs.txt "$ARKSERVER/ShooterGame/Saved/AllowedCheaterSteamIDs.txt" 2>/dev/null || true
ln -sf /ark/config/Engine.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/Engine.ini" 2>/dev/null || true
ln -sf /ark/config/Game.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/Game.ini" 2>/dev/null || true
ln -sf /ark/config/GameUserSettings.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini" 2>/dev/null || true

# Validate save file if requested
if [ "$VALIDATE_SAVE_EXISTS" = "true" ] && [ -n "$am_serverMap" ]; then
    savepath="$ARKSERVER/ShooterGame/Saved/$am_ark_AltSaveDirectoryName"
    savefile="$am_serverMap.ark"
    echo "Validating existence of save file: $savefile in $savepath"
    if [ ! -f "$savepath/$savefile" ]; then
        echo "ERROR: Save file '$savefile' not found in '$savepath'."
        echo "Attempting Discord notification..."
        arkmanager notify "Critical error: Save file missing: $savefile in $savepath"
        sleep 5m
        exit 1
    else
        echo "Save file found: $savepath/$savefile"
    fi
else
    echo "Save validation is not enabled or server map not set."
fi

# Backup on start if enabled
if [ "$BACKUP_ONSTART" = "true" ]; then
    echo "Backup on start is enabled. Creating backup..."
    arkmanager backup
else
    echo "Backup on start is not enabled."
fi

# Signal handler for graceful shutdown
function stop {
    echo "Shutdown signal received. Stopping server..."
    arkmanager broadcast "Server is shutting down"
    arkmanager notify "Server is shutting down"
    arkmanager stop
    exit 0
}

# Trap signals for proper shutdown
set -m
trap stop INT QUIT TERM

# Log RCON chat if enabled
if [ "${LOG_RCONCHAT:-0}" -gt 0 ]; then
    echo "Starting RCON chat logging..."
    bash -c ./log.sh &
fi

# Debug mount list if requested
if [ "$LIST_MOUNTS" = "true" ]; then
    echo "Mount listing requested..."
    echo "ARKSERVER_SHARED=$ARKSERVER_SHARED ARKCLUSTER=$ARKCLUSTER"
    for d in /ark "$ARKSERVER_SHARED" "$ARKSERVER/ShooterGame/Saved" "$ARKSERVER/ShooterGame/Saved/SavedArks"; do
        echo "--> Listing $d"
        ls -la "$d" || echo "Warning: Failed to list $d"
    done
fi
