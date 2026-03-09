# Installation

## Docker

```bash
docker pull drpsychick/arkserver:latest
```

Run with default settings:
```bash
docker run -d \
    -v steam:/home/steam/.steam/steamapps \
    -v ark:/ark \
    -p 27015:27015 -p 27015:27015/udp \
    -p 7778:7778 -p 7778:7778/udp \
    -p 7777:7777 -p 7777:7777/udp \
    drpsychick/arkserver
```

If the exposed ports are modified (in the case of multiple containers/servers on the same host) the `arkmanager` config will need to be modified to reflect the change as well. This is required so that `arkmanager` can properly check the server status and so that the ARK server itself can properly publish its IP address and query port to steam.

## Docker Compose

A ready-to-use [docker-compose.yml](docker/docker-compose.yml) is included:

```bash
docker compose up -d
```

Edit the environment variables in the compose file to customize your server. See [Configuration](Configuration.md) for all available options.

## Kubernetes

A StatefulSet is recommended over a Deployment — ARK servers are stateful and need persistent storage for save data, config, and server files.

### Key Concepts

**fsGroup**: The image runs as user `steam` (UID/GID `1001`). Set `securityContext.fsGroup: 1001` so mounted volumes are writable.

**Secrets**: Store `am_ark_ServerAdminPassword`, `am_ark_ServerPassword`, and `am_arkopt_clusterid` in a Kubernetes Secret and reference via `secretKeyRef` rather than plaintext env vars.

**Shared Server Files**: Set `ARKSERVER_SHARED=/arkserver` and mount a separate PVC at `/arkserver` to share the game binary across multiple map instances. Each instance still needs its own `/arkserver/ShooterGame/Saved` mount. See [Clustering](Clustering.md).

**Custom Ports**: When running multiple instances on the same node or behind a shared LoadBalancer IP, each server needs unique `am_ark_Port`, `am_ark_QueryPort`, and `am_ark_RCONPort` values. Set `am_arkNoPortDecrement=true` to prevent arkmanager from auto-adjusting ports.

**Mods**: Pass Steam Workshop mod IDs via `am_ark_GameModIds` as a comma-separated string. Mods are downloaded on first start and updated when `am_arkAutoUpdateOnStart=true`.

**Resources**: ARK servers are memory-heavy. Plan for 12-16Gi memory per instance. The server files themselves need ~250Gi of storage.

**Session Affinity**: Use `sessionAffinity: ClientIP` on the Service with a long timeout (3+ hours) to keep players connected to the same backend during long sessions.

### Single Instance

A complete single-instance example with health probes, resource limits, and session affinity:

- [k8s/statefulset.yaml](k8s/statefulset.yaml) — StatefulSet with health probes, resource limits, and a 50Gi PVC
- [k8s/service.yaml](k8s/service.yaml) — LoadBalancer Service with session affinity (3h timeout)

### Cluster with Shared Server Files

When running multiple maps, use shared PVCs for server binaries and cluster transfer data to avoid duplicating the ~50GB game install per instance. Add these env vars and volume mounts to each instance:

```yaml
          env:
            - name: ARKSERVER_SHARED
              value: "/arkserver"
            - name: ARKCLUSTER
              value: "true"
            - name: am_arkopt_clusterid
              valueFrom:
                secretKeyRef:
                  name: ark-secrets
                  key: cluster-id
          volumeMounts:
            - name: ark-data
              mountPath: /ark
            - name: ark-saved
              mountPath: /arkserver/ShooterGame/Saved
            - name: ark-cluster
              mountPath: /arkserver/ShooterGame/Saved/clusters
            - name: ark-serverfiles
              mountPath: /arkserver
```

Each instance needs its own `ark-data` and `ark-saved` volumes. The `ark-cluster` and `ark-serverfiles` volumes are shared across all instances in the cluster. For the full clustering guide, see [Clustering](Clustering.md).

### Production Considerations

#### Pod Security

The image runs as the `steam` user (non-root) internally. For hardened clusters:

```yaml
    spec:
      enableServiceLinks: false          # prevents leaking other service endpoints as env vars
      securityContext:
        fsGroup: 1001                    # match steam user GID for volume writes
      containers:
        - name: arkserver
          stdin: true                    # arkmanager expects an interactive TTY
          tty: true                      # required for proper signal handling and console
```

`enableServiceLinks: false` is especially important in namespaces with many services — Kubernetes injects every service as env vars by default, which can collide with `am_` prefixed arkmanager variables.

#### Image Pinning

For production stability, pin the image by digest instead of tag:

```yaml
          image: drpsychick/arkserver@sha256:59e6f0d445fa...
```

This prevents unexpected updates from pulling a new `:latest` during a pod reschedule. Upgrade deliberately by updating the digest.

#### LoadBalancer & Networking

**externalTrafficPolicy**: Use `Cluster` (default) for game servers. `Local` preserves client source IPs but requires the game client to connect to a node that actually runs the pod. `Cluster` routes from any node, which is more reliable for UDP game traffic.

```yaml
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
```

**Shared LoadBalancer IP**: Multiple ARK instances can share a single LoadBalancer IP as long as each uses unique ports. If your CNI/LB controller supports IP sharing annotations (e.g. Cilium's `lbipam.cilium.io/sharing-key`), all map instances can live behind one IP.

**Service Mesh / CNI Considerations**: If you run a service mesh like Istio in ambient mode, TCP health checks from monitoring tools may report false-healthy because the mesh proxy completes TCP handshakes before traffic reaches the pod. This is exactly why the [Health Server](HealthServer.md) exists — it validates actual RCON connectivity rather than just port reachability.

#### Network Policy

If your cluster runs default-deny network policies, ARK servers need ingress rules for game/query UDP, crossplay TCP, RCON (restricted to admin CIDRs), and the health endpoint. See [k8s/network-policy.yaml](k8s/network-policy.yaml) for a complete example.

Restrict RCON ingress to trusted admin CIDRs — RCON provides full server console access.

#### Monitoring with the Health Server

The health server enables proper application-level monitoring. In addition to Kubernetes probes, you can point external monitoring tools at the `/healthz` endpoint:

```
http://arkserver.<namespace>.svc.cluster.local:8080/healthz
```

Returns `200` with `{"status": "healthy"}` when RCON is responsive, `503` with `{"status": "unhealthy"}` when the server is still loading, crashed, or RCON is unreachable. This is the same RCON `ListPlayers` command that server admins use to check who's online — the health server just wraps it in HTTP for automation.

#### RCON Administration

The image includes `arkmanager` which provides RCON access for server administration. Common commands via `kubectl exec`:

```bash
# List connected players
kubectl exec -it arkserver-0 -- arkmanager rconcmd "ListPlayers"

# Broadcast a message to all players
kubectl exec -it arkserver-0 -- arkmanager broadcast "Server restarting in 15 minutes"

# Save the world
kubectl exec -it arkserver-0 -- arkmanager saveworld

# Graceful shutdown (warns players, saves, then stops)
kubectl exec -it arkserver-0 -- arkmanager stop --warn --saveworld
```

The health server uses this same `arkmanager rconcmd` mechanism under the hood — if `ListPlayers` succeeds, the server is up and accepting game connections.

#### HTTP Admin List Server

ARK supports loading admin lists, whitelists, and ban lists from HTTP URLs instead of local files. This is useful in Kubernetes where multiple server instances need to share the same lists without mounting the same config volume.

The [k8s/admin-list-server.yaml](k8s/admin-list-server.yaml) deploys an nginx server with [njs](https://nginx.org/en/docs/njs/) that reads Steam IDs from a Kubernetes Secret, deduplicates them, and serves them as plaintext. It includes:

- A **Secret** for Steam IDs (or use External Secrets Operator to sync from Vault)
- **ConfigMaps** for nginx config and the njs script
- A **Deployment** and **Service** exposing the endpoints

Available endpoints: `/AllowedCheaterSteamIDs.txt`, `/PlayersJoinNoCheckList.txt`, `/PlayersExclusiveJoinList.txt`

Configure your ARK server to load lists from the service URL:

```bash
am_arkopt_ExclusiveJoin="http://ark-admin-list-server:8080/PlayersExclusiveJoinList.txt"
```

The same pattern works for any text-based list ARK supports. Add more endpoints and Secret keys as needed.
