# Health Server

An optional lightweight HTTP health server that validates ARK RCON connectivity via `arkmanager rconcmd`. Useful for container orchestrators (Kubernetes, Docker Swarm) that need application-level health checks rather than simple TCP port probes.

## Why?

TCP health checks only verify that a port is open — they don't confirm the ARK server is actually running and responsive. In environments with service meshes (Istio, Linkerd) or reverse proxies, TCP handshakes may succeed even when the game server is down because the proxy completes the connection on behalf of the backend.

The health server performs a real RCON `ListPlayers` command against the running ARK server. If RCON responds, the server is genuinely up and accepting game connections.

## Enabling

Set the `HEALTH_SERVER` environment variable to `true`:

```bash
docker run -d \
    -e HEALTH_SERVER=true \
    -p 8080:8080 \
    ...
    drpsychick/arkserver
```

```yaml
# docker-compose.yml
services:
  ark:
    image: drpsychick/arkserver
    environment:
      HEALTH_SERVER: "true"
    ports:
      - "8080:8080"
```

## Configuration

| Variable             | Default | Description                        |
|----------------------|---------|------------------------------------|
| `HEALTH_SERVER`      | `false` | Enable the health server           |
| `HEALTH_SERVER_PORT` | `8080`  | Port the health server listens on  |

## Endpoints

| Path       | Method | Description                                                    |
|------------|--------|----------------------------------------------------------------|
| `/healthz` | GET    | RCON readiness check — `200` if RCON responds, `503` otherwise |
| `/livez`   | GET    | Process liveness — always `200` if the health server is running |

Any other path returns `404`.

### Response Format

All responses are `application/json`.

**`/healthz` — healthy:**
```json
{"status": "healthy"}
```

**`/healthz` — unhealthy (server starting up, crashed, or RCON unreachable):**
```json
{"status": "unhealthy"}
```

**`/livez`:**
```json
{"status": "alive"}
```

## Kubernetes Example

```yaml
containers:
  - name: ark
    image: drpsychick/arkserver
    env:
      - name: HEALTH_SERVER
        value: "true"
    ports:
      - containerPort: 8080
        protocol: TCP
        name: health
    readinessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 120
      periodSeconds: 30
      timeoutSeconds: 10
    livenessProbe:
      httpGet:
        path: /livez
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
```

## How It Works

The health server is a Python 3 `ThreadingHTTPServer` that runs as a background process alongside the ARK server. On each `/healthz` request it executes:

```
arkmanager rconcmd ListPlayers
```

- If `arkmanager` returns exit code 0, the server is healthy
- If it returns non-zero or times out (15s), the server is unhealthy
- Failures are logged to stderr for debugging
- Request logs are suppressed to avoid noise

The server starts right before `arkmanager start` in the entrypoint, so `/livez` becomes available almost immediately while `/healthz` will return `503` until the ARK server finishes loading and RCON becomes responsive.
