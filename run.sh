#!/usr/bin/env bash

# Define script and repository directories
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPODIR="$(dirname "$SCRIPTDIR")"
ARKSERVER=${ARKSERVER_SHARED:-"/ark/server"}

# Exit immediately if a command fails
set -eo pipefail

echo "###########################################################################"
echo "# Ark Server - $(date)"
echo "###########################################################################"

# Check for sudo capability
if sudo -n true 2>/dev/null; then
    HAS_PRIVILEGES="true"
    echo "Detected sudo capable user... Continuing..."
else
    HAS_PRIVILEGES="false"
    echo "Detected user that is not sudo-capable, continuing without sudo..."
fi

# Fix permissions if possible
if [ "$HAS_PRIVILEGES" = "true" ]; then
    echo "Ensuring correct file and directory ownership..."
    sudo find /ark -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
    sudo find /home/steam -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
else
    echo "Skipping permission correction: no sudo/root access."
fi

# Shared directory setup
if [ -n "$ARKSERVER_SHARED" ]; then
  echo "Using shared server directory at $ARKSERVER_SHARED..."

  if [ "$HAS_PRIVILEGES" = "true" ] && [ -d "$ARKSERVER_SHARED/ShooterGame" ]; then
    echo "Fixing permissions on shared ShooterGame directory..."
    sudo chown steam:steam "$ARKSERVER_SHARED/ShooterGame"
  fi

  # Check if Saved directory is mounted
  if ! mount | grep -q "on $ARKSERVER_SHARED/ShooterGame/Saved "; then
    echo "===> ABORT!"
    echo "Shared directory detected at '$ARKSERVER_SHARED', but 'Saved' directory is not mounted to '$ARKSERVER_SHARED/ShooterGame/Saved'"
    exit 1
  fi

  # Shared directory disables staging
  export am_arkStagingDir=
fi

# Cluster setup
if [ "$ARKCLUSTER" = "true" ]; then
  echo "ARKCLUSTER=true is enabled. Preparing cluster setup..."

  if [ "$HAS_PRIVILEGES" = "true" ] && [ -d "$ARKSERVER/ShooterGame/Saved" ]; then
    echo "Fixing permissions on Saved directory..."
    sudo chown steam:steam "$ARKSERVER/ShooterGame/Saved"
  fi

  echo "Checking for mounted clusters directory at '$ARKSERVER/ShooterGame/Saved/clusters'..."
  if ! mount | grep -q "on $ARKSERVER/ShooterGame/Saved/clusters "; then
    echo "===> ABORT!"
    echo "ARKCLUSTER is enabled but the clusters directory is not mounted to '$ARKSERVER/ShooterGame/Saved/clusters'"
    exit 1
  fi
fi

# Cleanup old arkmanager lock files
echo "Cleaning up any leftover arkmanager lock/tracking files..."
rm -f $ARKSERVER/ShooterGame/Saved/.ark-warn-main.lock
rm -f $ARKSERVER/ShooterGame/Saved/.ark-update.lock
rm -f $ARKSERVER/ShooterGame/Saved/.ark-update.time
rm -f $ARKSERVER/ShooterGame/Saved/.arkmanager-main.pid
rm -f $ARKSERVER/ShooterGame/Saved/.arkserver-main.pid
rm -f $ARKSERVER/ShooterGame/Saved/.autorestart
rm -f $ARKSERVER/ShooterGame/Saved/.autorestart-main

# Create necessary directories
mkdir -p /ark/config /ark/log /ark/backup /ark/staging

# Check for game binaries
if [ ! -d "$ARKSERVER/ShooterGame/Binaries" ]; then
  echo "Game binaries not found. Preparing base directory structure..."
  mkdir -p "$ARKSERVER/ShooterGame"
  mkdir -p "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer"
  mkdir -p "$ARKSERVER/ShooterGame/Saved/$am_ark_AltSaveDirectoryName"
  mkdir -p "$ARKSERVER/ShooterGame/Content/Mods"
  mkdir -p "$ARKSERVER/ShooterGame/Binaries/Linux/"
fi

# Generate arkmanager.cfg
echo "Creating arkmanager.cfg from environment variables..."
{
  echo -e "# Ark Server Tools - arkmanager config"
  echo -e "# Generated from container environment variables\n"
  [ -f /ark/config/arkmanager_base.cfg ] && cat /ark/config/arkmanager_base.cfg
  echo -e "\narkserverroot=\"$ARKSERVER\""
  printenv | sed -n -r 's/am_(.*)=(.*)/\1=\"\2\"/ip'
} > /ark/config/arkmanager.cfg

# Skip cron setup if filesystem is hardened
if [ -w /var/spool/cron/crontabs/ ]; then
  echo "Filesystem is hardened, skipping cron setup..."
else
  if [ ! -f /ark/config/crontab ]; then
    echo "Creating default crontab configuration..."
    cat << EOF > /ark/config/crontab
# Ark cron jobs
*/30 * * * * arkmanager update --update-mods --warn --saveworld
10 */8 * * * arkmanager saveworld && arkmanager backup
15 10 * * * arkmanager restart --warn --saveworld
EOF
  fi

  CRONNUMBER=$(grep -v "^#" /ark/config/crontab | wc -l)
  if [ "$CRONNUMBER" -gt 0 ]; then
    echo "Valid crontab entries detected..."
    if [ "$HAS_PRIVILEGES" = "false" ]; then
      echo "Non-root user starting cron in background..."
      cron && tail -f /dev/null
    else
      echo "Starting cron service as root..."
      sudo service cron start
    fi

    echo "Installing crontab..."
    crontab /ark/config/crontab
  else
    echo "No active crontab entries found."
  fi
fi

# Create symlinks for server configuration files
echo "Linking server configuration files..."
[ -f /ark/config/AllowedCheaterSteamIDs.txt ] && ln -sf /ark/config/AllowedCheaterSteamIDs.txt "$ARKSERVER/ShooterGame/Saved/AllowedCheaterSteamIDs.txt"
[ -f /ark/config/Engine.ini ] && ln -sf /ark/config/Engine.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/Engine.ini"
[ -f /ark/config/Game.ini ] && ln -sf /ark/config/Game.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/Game.ini"
[ -f /ark/config/GameUserSettings.ini ] && ln -sf /ark/config/GameUserSettings.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini"

# Optional: validate save file
if [ "$VALIDATE_SAVE_EXISTS" = "true" ] && [ -n "$am_serverMap" ]; then
  savepath="$ARKSERVER/ShooterGame/Saved/$am_ark_AltSaveDirectoryName"
  savefile="$am_serverMap.ark"
  echo "Validating save file presence: $savefile at $savepath"
  if [ ! -f "$savepath/$savefile" ]; then
    echo "ERROR: Save file '$savefile' not found at '$savepath'!"
    echo "Attempting Discord notification via arkmanager..."
    arkmanager notify "Critical error: unable to find $savefile in $savepath!"
    sleep 5m
    exit 1
  else
    echo "Save file '$savefile' found."
  fi
else
  echo "Save file validation is disabled or missing map name."
fi

# Optional: backup on start
if [ "$BACKUP_ONSTART" = "true" ]; then
  echo "BACKUP_ONSTART=true, performing backup..."
  arkmanager backup
else
  echo "Backup on start is not enabled."
fi

# Define signal handler for clean shutdown
function stop {
  echo "Shutting down server due to signal..."
  arkmanager broadcast "Server is shutting down"
  arkmanager notify "Server is shutting down"
  arkmanager stop
  exit 0
}

# Setup signal trap
set -m
trap stop INT QUIT TERM

# Optional: start RCON logging
if [ "$LOG_RCONCHAT" -gt 0 ]; then
  echo "RCON logging enabled. Starting log.sh..."
  bash -c ./log.sh &
fi

# Optional: list mounts
if [ "$LIST_MOUNTS" = "true" ]; then
  echo "Mount points summary:"
  echo "ARKSERVER_SHARED=$ARKSERVER_SHARED"
  echo "ARKCLUSTER=$ARKCLUSTER"
  for d in /ark "$ARKSERVER_SHARED" "$ARKSERVER/ShooterGame/Saved/" "$ARKSERVER/ShooterGame/Saved/SavedArks"; do
    echo "--> $d"
    ls -la "$d"
  done
fi
