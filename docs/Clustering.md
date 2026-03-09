# Running a Cluster

In order to run an ARK cluster, all you need are multiple servers sharing the `clusters` directory and using a shared,
unique `clusterid` - and a lot of RAM.
Additionally you can share the server files, so that all servers use the same version and you don't have to
store identical files twice on disk.

## Docker CLI

Example: (using the .env files in `/test`)
```shell script
IMAGE=drpsychick/arkserver
TAG=bionic
mkdir -p theisland ragnarok arkserver arkclusters theisland/saved ragnarok/saved

# start server 1 with am_arkAutoUpdateOnStart=true
serverdir=theisland
docker run --rm -it --name $serverdir \
  --env-file test/ark-$serverdir.env \
  -v $PWD/$serverdir:/ark \
  -v $PWD/$serverdir/saved:/arkserver/ShooterGame/Saved \
  -v $PWD/arkclusters:/arkserver/ShooterGame/Saved/clusters \
  -v $PWD/arkserver:/arkserver \
  -p 27015:27015/udp -p 7778:7778/udp -p 32330:32330 \
  $IMAGE:$TAG

# wait for the server to be up, it should download all mods and the game

# start server 2+ with am_arkAutoUpdateOnStart=false
# using the SAME `arkserver` and `arkclusters` directory
serverdir=ragnarok
docker run --rm -it --name $serverdir \
  --env-file test/ark-$serverdir.env \
  -v $PWD/$serverdir:/ark \
  -v $PWD/$serverdir/saved:/arkserver/ShooterGame/Saved \
  -v $PWD/arkclusters:/arkserver/ShooterGame/Saved/clusters \
  -v $PWD/arkserver:/arkserver \
  -p 27016:27016/udp -p 7780:7780/udp -p 32331:32331 \
  $IMAGE:$TAG

# now you can reach your servers on 27015 and 27016 respectively

# cleanup
rm -rf theisland ragnarok arkserver arkclusters
```

## Docker Compose

```yaml
services:
  theisland:
    image: drpsychick/arkserver
    env_file: ark-theisland.env
    volumes:
      - theisland:/ark
      - theisland-saved:/arkserver/ShooterGame/Saved
      - clusters:/arkserver/ShooterGame/Saved/clusters
      - serverfiles:/arkserver
    ports:
      - "27015:27015/udp"
      - "7778:7778/udp"
      - "32330:32330"

  ragnarok:
    image: drpsychick/arkserver
    env_file: ark-ragnarok.env
    volumes:
      - ragnarok:/ark
      - ragnarok-saved:/arkserver/ShooterGame/Saved
      - clusters:/arkserver/ShooterGame/Saved/clusters
      - serverfiles:/arkserver
    ports:
      - "27016:27016/udp"
      - "7780:7780/udp"
      - "32331:32331"

volumes:
  theisland:
  theisland-saved:
  ragnarok:
  ragnarok-saved:
  clusters:
  serverfiles:
```

## Testing Transfers

To test jumping from one server to another:
* join one server, enable cheats with `enablecheats <adminpassword>`
* cheat your character the transmitter tek engram `cheat GiveTekengramsTo <survivorID> transmitter`
* cheat your character a transmitter item `cheat gfi TekTransmitter 1 1 0`
* place the transmitter, turn it on, enter the inventory -> you should see "travel to another server" button in the middle
* click it and select the server you want to travel to

The `survivorID` is the number displayed when you hover over the specimen implant (diamond shaped item)
you always have (https://ark.fandom.com/wiki/Specimen_Implant).

## Important Notes

- Only the **first** server should have `am_arkAutoUpdateOnStart=true` when sharing server files — subsequent servers should set it to `false` and wait for the first to finish updating
- Each server needs unique ports (`am_ark_Port`, `am_ark_QueryPort`, `am_ark_RCONPort`)
- Each server needs its own `/ark` and `ShooterGame/Saved` volumes — only `clusters` and `serverfiles` are shared
