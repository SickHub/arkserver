ARG STEAMCMD_VERSION=latest
ARG AMG_BUILD=latest
# github-releases:arkmanager/ark-server-tools
ARG AMG_VERSION=v1.6.62
FROM drpsychick/steamcmd:$STEAMCMD_VERSION AS base

USER root

RUN apt-get update \
    && apt-get install -y \
    curl \
    cron \
    bzip2 \
    perl-modules \
    lsof \
    libc6-i386 \
    #    libsdl2-2.0.0:i386 \
    sudo \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

FROM base AS arkmanager-latest
RUN curl -sL "https://raw.githubusercontent.com/arkmanager/ark-server-tools/master/netinstall.sh" | bash -s steam

FROM base AS arkmanager-versioned
ARG AMG_VERSION
RUN curl -sL "https://raw.githubusercontent.com/arkmanager/ark-server-tools/$AMG_VERSION/netinstall.sh" | bash -s steam -- --unstable

ARG AMG_BUILD
FROM arkmanager-$AMG_BUILD
RUN ln -s /usr/local/bin/arkmanager /usr/bin/arkmanager

COPY arkmanager/arkmanager.cfg /etc/arkmanager/arkmanager.cfg
COPY arkmanager/instance.cfg /etc/arkmanager/instances/main.cfg
COPY run.sh /home/steam/run.sh
COPY log.sh /home/steam/log.sh

RUN echo "%sudo   ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers \
    && usermod -a -G sudo steam \
    && mkdir /ark /arkserver \
    && chown -R steam:steam /ark /arkserver

WORKDIR /home/steam
USER steam

ENV am_ark_SessionName=Ark\ Server \
    am_serverMap=TheIsland \
    am_ark_ServerAdminPassword=k3yb04rdc4t \
    am_ark_MaxPlayers=70 \
    am_ark_QueryPort=27015 \
    am_ark_Port=7778 \
    am_ark_RCONPort=32330 \
    am_ark_AltSaveDirectoryName=SavedArks \
    am_arkwarnminutes=15 \
    am_arkAutoUpdateOnStart=false

ENV VALIDATE_SAVE_EXISTS=false \
    BACKUP_ONSTART=false \
    LOG_RCONCHAT=0 \
    ARKCLUSTER=false

# only mount the steamapps directory
# mount /home/steam/.steam/steamapps if you want to share storage for steam mod staging
VOLUME /ark
# optionally shared volumes between servers in a cluster
VOLUME /arkserver
# mount /arkserver/ShooterGame/Saved seperate for each server
# mount /arkserver/ShooterGame/Saved/clusters shared for all servers

CMD [ "./run.sh" ]
