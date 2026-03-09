# arkserver
ARK: Survival Evolved dedicated server image, for single instances and clusters.

[![CircleCI](https://img.shields.io/circleci/build/github/SickHub/arkserver)](https://app.circleci.com/pipelines/github/SickHub/arkserver) [![Docker image](https://img.shields.io/docker/image-size/drpsychick/arkserver?sort=date)](https://hub.docker.com/r/drpsychick/arkserver/tags) [![Docker Pulls](https://img.shields.io/docker/pulls/drpsychick/arkserver.svg?style=flat-square)](https://hub.docker.com/r/drpsychick/arkserver/) [![License](https://img.shields.io/dub/l/vibe-d.svg?style=flat-square)](https://github.com/drpsychick/arkserver/blob/master/LICENSE)

[![GitHub issues](https://img.shields.io/github/issues/SickHub/arkserver.svg)](https://github.com/SickHub/arkserver/issues) [![GitHub closed issues](https://img.shields.io/github/issues-closed/SickHub/arkserver.svg)](https://github.com/SickHub/arkserver/issues?q=is%3Aissue+is%3Aclosed) [![GitHub pull requests](https://img.shields.io/github/issues-pr/SickHub/arkserver.svg)](https://github.com/SickHub/arkserver/pulls) [![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed/SickHub/arkserver.svg)](https://github.com/SickHub/arkserver/pulls?q=is%3Apr+is%3Aclosed) [![Contributors](https://img.shields.io/github/contributors/SickHub/arkserver.svg)](https://github.com/SickHub/arkserver/graphs/contributors) [![Paypal](https://img.shields.io/badge/donate-paypal-00457c.svg?logo=paypal)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=FTXDN7LCDWUEA&source=url) [![GitHub Sponsor](https://img.shields.io/badge/github-sponsor-blue?logo=github)](https://github.com/sponsors/DrPsychick)

### Features
* Automated install (pull the image and run, no additional commands necessary)
* Built on [drpsychick/steamcmd](https://github.com/drpsychick/steamcmd) with the latest `steamcmd`
* Configuration via Environment Variables
* Easy crontab manipulation for automated backups, updates, daily restarts, weekly dino wipes, etc
* Simple volume structure for server files, config, logs, backups, etc
* Inherently includes all features present in `arkmanager`
* Optional [RCON health server](docs/HealthServer.md) for application-level readiness checks

### Docker Image: [`drpsychick/arkserver`](https://hub.docker.com/r/drpsychick/arkserver)
| Tag | Description |
|-----|-------------|
| [`latest`](https://hub.docker.com/layers/drpsychick/arkserver/latest/images/sha256-59e6f0d445fa00b26111346854b561d6b1f9b1853e34808a9f1ebffdf32cc703) | most recent build from the master branch |
| [`latest-v1.6.62`](https://hub.docker.com/layers/drpsychick/arkserver/latest-v1.6.62/images/sha256-82d8b119c03f04033e399b33cd6a997ab61b88d5e692caf6339349f7ff4495b3) | release builds |

### Documentation

|                     |                                                     |
| ------------------- | --------------------------------------------------- |
| Install             | [Docker, Compose & Kubernetes](docs/Install.md)     |
| Configuration       | [Environment Variables & Volumes](docs/Configuration.md) |
| arkmanager          | [arkmanager/ark-server-tools](https://github.com/arkmanager/ark-server-tools) |
| Clustering          | [Multi-Map Cluster Setup](docs/Clustering.md)       |
| Health Server       | [RCON Health Endpoint](docs/HealthServer.md)        |
| Helm Chart          | [ark-server-charts](https://github.com/SickHub/ark-server-charts)             |

## Quick Start

```bash
docker run -d \
    -v steam:/home/steam/.steam/steamapps \
    -v ark:/ark \
    -p 27015:27015 -p 27015:27015/udp \
    -p 7778:7778 -p 7778:7778/udp \
    -p 7777:7777 -p 7777:7777/udp \
    drpsychick/arkserver
```

See [Install](docs/Install.md) for Docker Compose and Kubernetes examples.

## Credits

* Heavily based on [TuRz4m/Ark-docker](https://github.com/TuRz4m/Ark-docker)
* Uses [FezVrasta](https://github.com/FezVrasta)'s [arkmanager/ark-server-tools](https://github.com/arkmanager/ark-server-tools) for server management
* Forked from [thmhoag/arkserver](https://github.com/thmhoag/arkserver) (August 2022 — split after unaccepted PR)
