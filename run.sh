#!/usr/bin/env bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPODIR="$(dirname "$SCRIPTDIR")"
ARKSERVER=${ARKSERVER_SHARED:-"/ark/server"}

# always fail script if a cmd fails
set -eo pipefail

echo "###########################################################################"
echo "# Ark Server - " `date`
echo "###########################################################################"

echo "Ensuring correct permissions..."
sudo find /ark -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;
sudo find /home/steam -not -user steam -o -not -group steam -exec chown -v steam:steam {} \;

if [ -n "$ARKSERVER_SHARED" ]; then
  # directory is created when something is mounted to 'Saved'
  [ -d "$ARKSERVER_SHARED/ShooterGame" ] && sudo chown steam:steam $ARKSERVER_SHARED/ShooterGame
  echo "Shared server files in $ARKSERVER_SHARED..."
  if [ -z "$(mount | grep "on $ARKSERVER_SHARED/ShooterGame/Saved ")" ]; then
    echo "===> ABORT !"
    echo "You seem to be using a shared server directory: '$ARKSERVER_SHARED'"
    echo "But you have NOT mounted your game instance saved directory to '$ARKSERVER_SHARED/ShooterGame/Saved'"
    exit 1
  fi
  # Shared server files does not support staging directory
  export am_arkStagingDir=
fi

if [ "$ARKCLUSTER" = "true" ]; then
  # directory is created when something is mounted to 'clusters'
  [ -d "$ARKSERVER/ShooterGame/Saved" ] && chown steam:steam $ARKSERVER/ShooterGame/Saved
  echo "Shared clusters files in $ARKSERVER/ShooterGame/Saved/clusters..."
  if [ -z "$(mount | grep "on $ARKSERVER/ShooterGame/Saved/clusters ")" ]; then
    echo "===> ABORT !"
    echo "You seem to using ARKCLUSTER=true"
    echo "But you have NOT mounted your shared clusters directory to '$ARKSERVER/ShooterGame/Saved/clusters'"
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

# Create directories if they don't exist
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

# Stop server in case of signal INT or TERM
trap stop INT
trap stop TERM

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
    # requires arkmanager > v1.6.61a
    while (arkmanager checkmodupdate --skip-workshop-dir); do
      echo -n "."
      sleep 10
    done
    echo
  fi
fi

arkmanager start --no-background --verbose &
arkmanpid=$!
wait $arkmanpid
