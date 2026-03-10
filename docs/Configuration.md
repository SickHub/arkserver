# Configuration

All configuration is done through environment variables. The container translates `am_` prefixed variables into `arkmanager.cfg` entries at startup.

## Server Variables

| Variable                     | Default         | Description                                                       |
|------------------------------|-----------------|-------------------------------------------------------------------|
| `am_ark_SessionName`         | `Ark Server`    | Server name as shown on the Steam server list                     |
| `am_serverMap`               | `TheIsland`     | Map to load                                                       |
| `am_ark_ServerAdminPassword` | `k3yb04rdc4t`   | Admin password for in-game console and RCON                       |
| `am_ark_MaxPlayers`          | `70`            | Maximum concurrent players                                        |
| `am_ark_QueryPort`           | `27015`         | Steam query port (server list discovery)                          |
| `am_ark_Port`                | `7778`          | Game client connection port                                       |
| `am_ark_RCONPort`            | `32330`         | RCON port                                                         |
| `am_ark_AltSaveDirectoryName`| `SavedArks`     | Subdirectory name for save files                                  |
| `am_arkwarnminutes`          | `15`            | Minutes to warn players before updates/restarts                   |
| `am_arkAutoUpdateOnStart`    | `false`         | Automatically update server files on container start              |
| `am_arkflag_crossplay`       | `false`         | Allow crossplay with Epic Games players                           |

## Container Variables

| Variable             | Default  | Description                                                         |
|----------------------|----------|---------------------------------------------------------------------|
| `VALIDATE_SAVE_EXISTS` | `false` | Validate that a save file exists for the configured map on startup |
| `BACKUP_ONSTART`     | `false`  | Create a backup before starting the server                          |
| `LOG_RCONCHAT`       | `0`      | Fetch and log chat via RCON every N seconds (`0` = disabled)        |
| `ARKCLUSTER`         | `false`  | Enable cluster mode (requires `clusters` volume mount)              |
| `ARKSERVER_SHARED`   |          | Path to shared server binary files (e.g. `/arkserver`)              |
| `HEALTH_SERVER`      | `false`  | Enable the [HTTP health server](HealthServer.md)                    |
| `HEALTH_SERVER_PORT` | `8080`   | Port for the health server                                          |
| `AM_INSTALL_ARGS`    |          | Extra arguments for `arkmanager install`                            |
| `AM_UPDATE_ARGS`     |          | Extra arguments for `arkmanager update`                             |

## Custom arkmanager Variables

Any `arkmanager` configuration value can be set via environment variables prefixed with `am_`. The container strips the prefix and writes them to `arkmanager.cfg` at startup.

See the full list in the [arkmanager documentation](https://github.com/arkmanager/ark-server-tools#configuration-files).

### Examples

```bash
# Server password
am_ark_ServerPassword=s3cr3t

# Game mods (comma-separated Steam Workshop IDs)
am_ark_GameModIds=889745138,731604991

# Cluster ID
am_arkopt_clusterid=mycluster

# Server flags (set to empty string to enable)
am_arkflag_NoTransferFromFiltering=
am_arkflag_servergamelog=
am_arkflag_ForceAllowCaveFlyers=
```

## Volumes

| Path                                    | Required | Description                                                              |
|-----------------------------------------|----------|--------------------------------------------------------------------------|
| `/home/steam/.steam/steamapps`          | Optional | Steamapps and workshop files — mount to persist mod downloads            |
| `/ark`                                  | Yes      | Server config, logs, backups, and (if not shared) game files             |
| `/arkserver`                            | Optional | Shared server binary files (`ARKSERVER_SHARED=/arkserver`)               |
| `/arkserver/ShooterGame/Saved`          | Depends  | Per-instance save files — **required** when using shared server files    |
| `/arkserver/ShooterGame/Saved/clusters` | Depends  | Shared cluster transfer files — **required** when `ARKCLUSTER=true`     |

> **Note:** The `steam` user in the image has UID/GID `1001`/`1001`. All mounted volumes must be readable/writable by this UID/GID.

### Subdirectories of /ark

| Path           | Description                                      |
|----------------|--------------------------------------------------|
| `/ark/backup`  | Compressed backups from `arkmanager backup`       |
| `/ark/config`  | Server configuration files                        |
| `/ark/log`     | arkmanager and server log files                   |
| `/ark/server`  | Server installation (when not using shared files) |
| `/ark/staging` | Staging directory for game and mod updates        |
