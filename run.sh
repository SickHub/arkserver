#!/usr/bin/env bash

# Define directories
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPODIR="$(dirname "$SCRIPTDIR")"
ARKSERVER=${ARKSERVER_SHARED:-"/ark/server"}

# Always fail script if a command fails
set -eo pipefail

echo "###########################################################################"
echo "# Ark Server - " `date`
echo "###########################################################################"

# Determine if the user has root or sudo privileges
if [ "$(id -u)" -eq 0 ]; then
    HAS_PRIVILEGES=true
    echo "detected root user... Continuing..."
elif id -Gn $(whoami) | grep -qw 'root'; then
    HAS_PRIVILEGES=true
    echo "Detected membership in the 'root' group (GID 0)... Continuing..."
elif sudo -n true 2>/dev/null; then
    HAS_PRIVILEGES=true
    echo "detected sudo capable user... Continuing..."
else
    HAS_PRIVILEGES=false
    echo "detected non-root user that is not sudo-capable... Continuing, without root or sudo...."
fi

# Ensure correct file permissions (checking ownership) only if root/sudo is available
if [ "$HAS_PRIVILEGES" = true ]; then
    echo "Ensuring correct permissions..."
    sudo find /ark -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
    sudo find /home/steam -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
else
    echo "Skipping permission fix as root or sudo privileges are not available."
fi

if [ -n "$ARKSERVER_SHARED" ]; then
  # Directory created when something is mounted to 'Saved'
  if [ "$HAS_PRIVILEGES" = true ] && [ -d "$ARKSERVER_SHARED/ShooterGame" ]; then
    sudo chown steam:steam $ARKSERVER_SHARED/ShooterGame
  fi
  echo "Shared server files in $ARKSERVER_SHARED..."
  
  # Ensure the Saved directory is mounted properly
  if [ -z "$(mount | grep "on $ARKSERVER_SHARED/ShooterGame/Saved ")" ]; then
    echo "===> ABORT !"
    echo "You seem to be using a shared server directory: '$ARKSERVER_SHARED'"
    echo "But you have NOT mounted your game instance saved directory to '$ARKSERVER_SHARED/ShooterGame/Saved'"
    exit 1
  fi

  # Shared server files do not support staging directory
  export am_arkStagingDir=
fi

# Cluster setup
if [ "$ARKCLUSTER" = "true" ]; then
  if [ "$HAS_PRIVILEGES" = true ] && [ -d "$ARKSERVER/ShooterGame/Saved" ]; then
    sudo chown steam:steam $ARKSERVER/ShooterGame/Saved
  fi
  echo "Shared clusters files in $ARKSERVER/ShooterGame/Saved/clusters..."
  if [ -z "$(mount | grep "on $ARKSERVER/ShooterGame/Saved/clusters ")" ]; then
    echo "===> ABORT !"
    echo "You have ARKCLUSTER=true set, but your shared clusters directory is not mounted!"
    exit 1
  fi
fi


# Remove arkmanager tracking files if they exist
# They can cause issues with starting the server multiple times
# due to the restart command not completing when the container exits
echo "Cleaning up any leftover arkmanager files..."
[ -f $ARKSERVER/ShooterGame/Saved/.ark-warn-main.lock ] && rm -rf $ARKSERVER/ShooterGame/Saved/.ark-warn-main.lock
[ -f $ARKSERVER/ShooterGame/Saved/.ark-update.lock ] && rm -rf $ARKSERVER/ShooterGame/Saved/.ark-update.lock
[ -f $ARKSERVER/ShooterGame/Saved/.ark-update.time ] && rm -rf $ARKSERVER/ShooterGame/Saved/.ark-update.time
[ -f $ARKSERVER/ShooterGame/Saved/.arkmanager-main.pid ] && rm -rf $ARKSERVER/ShooterGame/Saved/.arkmanager-main.pid
[ -f $ARKSERVER/ShooterGame/Saved/.arkserver-main.pid ] && rm -rf $ARKSERVER/ShooterGame/Saved/.arkserver-main.pid
[ -f $ARKSERVER/ShooterGame/Saved/.autorestart ] && rm -rf $ARKSERVER/ShooterGame/Saved/.autorestart
[ -f $ARKSERVER/ShooterGame/Saved/.autorestart-main ] && rm -rf $ARKSERVER/ShooterGame/Saved/.autorestart-main

# Create necessary directories if they don't exist
[ ! -d /ark/config ] && mkdir /ark/config
[ ! -d /ark/log ] && mkdir /ark/log
[ ! -d /ark/backup ] && mkdir /ark/backup
[ ! -d /ark/staging ] && mkdir /ark/staging

if [ ! -d $ARKSERVER/ShooterGame/Binaries ]; then
  echo "No game files found. Preparing for install..."
  mkdir -p $ARKSERVER/ShooterGame
  mkdir -p $ARKSERVER/ShooterGame/Saved/Config/LinuxServer
  mkdir -p $ARKSERVER/ShooterGame/Saved/$am_ark_AltSaveDirectoryName
  mkdir -p $ARKSERVER/ShooterGame/Content/Mods
  mkdir -p $ARKSERVER/ShooterGame/Binaries/Linux/
fi

echo "Creating arkmanager.cfg from environment variables..."
echo -e "# Ark Server Tools - arkmanager config\n# Generated from container environment variables\n\n" > /ark/config/arkmanager.cfg
if [ -f /ark/config/arkmanager_base.cfg ]; then
  cat /ark/config/arkmanager_base.cfg >> /ark/config/arkmanager.cfg
fi

echo -e "\n\narkserverroot=\"$ARKSERVER\"\n" >> /ark/config/arkmanager.cfg
printenv | sed -n -r 's/am_(.*)=(.*)/\1=\"\2\"/ip' >> /ark/config/arkmanager.cfg

if [ "$HAS_PRIVILEGES" = false ]; then
 echo "non-root, non-sudo user detected, cannot setup Crontab..."
elif [ -w /var/spool/cron/crontabs/ ]; then
 echo "Hardened filesystem detect, cannot setup Crontab..."
else

if [ ! -f /ark/config/crontab ]; then
  echo "Creating crontab..."
  cat << EOF >> /ark/config/crontab
# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
# *  *  *  *  * user-name  command to be executed

# Examples for Ark:
# 0 * * * * arkmanager update				# update every hour
# */15 * * * * arkmanager backup			# backup every 15min
# 0 0 * * * arkmanager backup				# backup every day at midnight
*/30 * * * * arkmanager update --update-mods --warn --saveworld
10 */8 * * * arkmanager saveworld && arkmanager backup
15 10 * * * arkmanager restart --warn --saveworld

EOF
fi

# If there is uncommented line in the file
CRONNUMBER=`grep -v "^#" /ark/config/crontab | wc -l`
if [ $CRONNUMBER -gt 0 ]; then
	echo "Starting cron service..."
	sudo service cron start

	echo "Loading crontab..."
	# We load the crontab file if it exist.
	crontab /ark/config/crontab
	
else
	echo "No crontab set."
fi
fi


# Create symlinks for configs
[ -f /ark/config/AllowedCheaterSteamIDs.txt ] && ln -sf /ark/config/AllowedCheaterSteamIDs.txt $ARKSERVER/ShooterGame/Saved/AllowedCheaterSteamIDs.txt
[ -f /ark/config/Engine.ini ] && ln -sf /ark/config/Engine.ini $ARKSERVER/ShooterGame/Saved/Config/LinuxServer/Engine.ini
[ -f /ark/config/Game.ini ] && ln -sf /ark/config/Game.ini $ARKSERVER/ShooterGame/Saved/Config/LinuxServer/Game.ini
[ -f /ark/config/GameUserSettings.ini ] && ln -sf /ark/config/GameUserSettings.ini $ARKSERVER/ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini

if [ "$VALIDATE_SAVE_EXISTS" = "true" -a ! -z "$am_serverMap" ]; then
	savepath="$ARKSERVER/ShooterGame/Saved/$am_ark_AltSaveDirectoryName"
	savefile="$am_serverMap.ark"
	echo "Validating that a save file exists for $am_serverMap"
	echo "Checking $savepath"
	if [! -f "$savepath/$savefile" ]; then
		echo "$savefile not found!"
		echo "Attempting to notify via Discord..."
		arkmanager notify "Critical error: unable to find $savefile in $savepath!"

		# wait on failure so we don't spam docker logs
		sleep 5m
		exit 1
	else
		echo "$savefile found."
	fi
else
	echo "Save file validation is not enabled."
fi

if [ "$BACKUP_ONSTART" = "true" ]; then
	echo "Backing up on start..."
	arkmanager backup
else
	echo "Backup on start is not enabled."
fi

function stop {
	arkmanager broadcast "Server is shutting down"
	arkmanager notify "Server is shutting down"
	arkmanager stop
	exit 0
}

# Stop server in case of signal INT, QUIT or TERM
# enable job control to catch signals
set -m
trap stop INT QUIT TERM

# log from RCON to stdout
if [ $LOG_RCONCHAT -gt 0 ]; then
  bash -c ./log.sh &
fi

if [ "$LIST_MOUNTS" = "true" ]; then
  echo "LIST Mounts:"
  echo "ARKSERVER_SHARED=$ARKSERVER_SHARED ARKCLUSTER=$ARKCLUSTER"
  for d in /ark $ARKSERVER_SHARED $ARKSERVER/ShooterGame/Saved/ $ARKSERVER/ShooterGame/Saved/SavedArks; do
    echo "--> $d"
    ls -la $d
  done
  if [ "$ARKCLUSTER" = "true" ]; then
    echo "--> $ARKSERVER/ShooterGame/Saved/clusters"
    ls -la $ARKSERVER/ShooterGame/Saved/clusters
  fi
  mount | grep "on /ark"
  exit 0
fi

if [ "$am_arkAutoUpdateOnStart" != "true" ]; then
  echo -n "Waiting for ARK server to be updated: "
  while (! arkmanager checkupdate); do
    echo -n "."
    sleep 10
  done
  echo

  if [ -n "$am_ark_GameModIds" ]; then
    echo -n "Waiting for mods to be updated: "
    # requires arkmanager >= v1.6.62
    while (arkmanager checkmodupdate --skip-workshop-dir); do
      echo -n "."
      sleep 10
    done
    echo
  fi
fi

# fix for broken steamcmd app_info_print: execute install/update manually, checking for updates fails.
# https://github.com/ValveSoftware/steam-for-linux/issues/9683#issuecomment-1826928761
if [ ! -f "$ARKSERVER/steamapps/appmanifest_376030.acf" ]; then
  arkmanager install
elif [ "$am_arkAutoUpdateOnStart" = "true" ]; then
  arkmanager update --force --no-autostart
fi

# run in subshell, so it does not trap signals
(arkmanager start --no-background --verbose) &
arkmanpid=$!
wait $arkmanpid
