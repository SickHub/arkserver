#!/usr/bin/env bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPODIR="$(dirname "$SCRIPTDIR")"
ARKSERVER=${ARKSERVER_SHARED:-"/ark/server"}

set -eo pipefail

echo "###########################################################################"
echo "# Ark Server - $(date)"
echo "###########################################################################"

# check if we have sudo
if sudo -n true 2>/dev/null; then
    HAS_PRIVILEGES="true"
    echo "Detected sudo capable user... Continuing..."
else
    HAS_PRIVILEGES="false"
    echo "Detected user that is not sudo-capable, continuing without sudo..."
fi

if [ "$HAS_PRIVILEGES" = "true" ]; then
    echo "Fixing ownership of /ark and /home/steam to steam:steam..."
    sudo find /ark -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
    sudo find /home/steam -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
fi

if [ -n "$ARKSERVER_SHARED" ]; then
  echo "Shared server mode enabled at $ARKSERVER_SHARED"

  if [ "$HAS_PRIVILEGES" = "true" ] && [ -d "$ARKSERVER_SHARED/ShooterGame" ]; then
    echo "Fixing ownership of ShooterGame directory..."
    sudo chown steam:steam "$ARKSERVER_SHARED/ShooterGame"
  fi

  if ! mount | grep -q "on $ARKSERVER_SHARED/ShooterGame/Saved "; then
    echo "===> ABORT!"
    echo "Shared directory detected at '$ARKSERVER_SHARED', but 'Saved' directory is not mounted to '$ARKSERVER_SHARED/ShooterGame/Saved'"
    exit 1
  fi

  export am_arkStagingDir=
fi

if [ "$ARKCLUSTER" = "true" ]; then
  echo "Cluster mode enabled"

  if [ "$HAS_PRIVILEGES" = "true" ] && [ -d "$ARKSERVER/ShooterGame/Saved" ]; then
    echo "Fixing ownership of Saved directory for cluster support..."
    sudo chown steam:steam "$ARKSERVER/ShooterGame/Saved"
  fi

  if ! mount | grep -q "on $ARKSERVER/ShooterGame/Saved/clusters "; then
    echo "===> ABORT!"
    echo "ARKCLUSTER is enabled but the clusters directory is not mounted to '$ARKSERVER/ShooterGame/Saved/clusters'"
    exit 1
  fi
fi

echo "Cleaning up potential leftover lock files..."
rm -f $ARKSERVER/ShooterGame/Saved/.ark-warn-main.lock
rm -f $ARKSERVER/ShooterGame/Saved/.ark-update.lock
rm -f $ARKSERVER/ShooterGame/Saved/.ark-update.time
rm -f $ARKSERVER/ShooterGame/Saved/.arkmanager-main.pid
rm -f $ARKSERVER/ShooterGame/Saved/.arkserver-main.pid
rm -f $ARKSERVER/ShooterGame/Saved/.autorestart
rm -f $ARKSERVER/ShooterGame/Saved/.autorestart-main

echo "Ensuring directory structure..."
mkdir -p /ark/config /ark/log /ark/backup /ark/staging

if [ ! -d "$ARKSERVER/ShooterGame/Binaries" ]; then
  echo "Binaries missing, creating base directory structure..."
  mkdir -p "$ARKSERVER/ShooterGame"
  mkdir -p "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer"
  mkdir -p "$ARKSERVER/ShooterGame/Saved/$am_ark_AltSaveDirectoryName"
  mkdir -p "$ARKSERVER/ShooterGame/Content/Mods"
  mkdir -p "$ARKSERVER/ShooterGame/Binaries/Linux/"
fi

echo "Generating arkmanager.cfg..."
{
  echo -e "# Ark Server Tools - arkmanager config"
  echo -e "# Generated from container environment variables\n"
  [ -f /ark/config/arkmanager_base.cfg ] && cat /ark/config/arkmanager_base.cfg
  echo -e "\narkserverroot=\"$ARKSERVER\""
  printenv | sed -n -r 's/am_(.*)=(.*)/\1=\"\2\"/ip'
} > /ark/config/arkmanager.cfg

if [ -w /var/spool/cron/crontabs/ ]; then
  echo "Filesystem is hardened, skipping cron setup"
else
  if [ ! -f /ark/config/crontab ]; then
    echo "Creating default crontab..."
    cat << EOF > /ark/config/crontab
# Ark cron jobs
*/30 * * * * arkmanager update --update-mods --warn --saveworld
10 */8 * * * arkmanager saveworld && arkmanager backup
15 10 * * * arkmanager restart --warn --saveworld
EOF
  fi

  CRONNUMBER=$(grep -v "^#" /ark/config/crontab | wc -l)
  if [ "$CRONNUMBER" -gt 0 ]; then
    echo "Setting up cron..."
    if [ "$HAS_PRIVILEGES" = "false" ]; then
      echo "Starting cron as non-root..."
      cron && tail -f /dev/null
    else
      echo "Starting cron service..."
      sudo service cron start
    fi

    echo "Installing crontab..."
    crontab /ark/config/crontab
  fi
fi

echo "Creating config symlinks..."
[ -f /ark/config/AllowedCheaterSteamIDs.txt ] && ln -sf /ark/config/AllowedCheaterSteamIDs.txt "$ARKSERVER/ShooterGame/Saved/AllowedCheaterSteamIDs.txt"
[ -f /ark/config/Engine.ini ] && ln -sf /ark/config/Engine.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/Engine.ini"
[ -f /ark/config/Game.ini ] && ln -sf /ark/config/Game.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/Game.ini"
[ -f /ark/config/GameUserSettings.ini ] && ln -sf /ark/config/GameUserSettings.ini "$ARKSERVER/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini"

if [ "$VALIDATE_SAVE_EXISTS" = "true" ] && [ -n "$am_serverMap" ]; then
  savepath="$ARKSERVER/ShooterGame/Saved/$am_ark_AltSaveDirectoryName"
  savefile="$am_serverMap.ark"
  echo "Checking if save exists: $savefile"
  if [ ! -f "$savepath/$savefile" ]; then
    echo "ERROR: Save file '$savefile' not found at '$savepath'!"
    arkmanager notify "Critical error: unable to find $savefile in $savepath!"
    sleep 5m
    exit 1
  fi
fi

if [ "$BACKUP_ONSTART" = "true" ]; then
  echo "Running startup backup..."
  arkmanager backup
fi

function stop {
  echo "Received termination signal. Stopping Ark server..."
  arkmanager broadcast "Server is shutting down"
  arkmanager notify "Server is shutting down"
  arkmanager stop
  exit 0
}

set -m
trap stop INT QUIT TERM

if [ "$LOG_RCONCHAT" -gt 0 ]; then
  echo "Starting RCON chat logger..."
  bash -c ./log.sh &
fi

if [ "$LIST_MOUNTS" = "true" ]; then
  echo "Mount points:"
  echo "ARKSERVER_SHARED=$ARKSERVER_SHARED"
  echo "ARKCLUSTER=$ARKCLUSTER"
  for d in /ark "$ARKSERVER_SHARED" "$ARKSERVER/ShooterGame/Saved/" "$ARKSERVER/ShooterGame/Saved/SavedArks"; do
    echo "--> $d"
    ls -la "$d"
  done
fi

# === START ARK SERVER ===
echo "Starting Ark server..."
exec arkmanager run
