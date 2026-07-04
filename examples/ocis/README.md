## Example: two oCIS + Firefox + mitmproxy

This example runs two oCIS instances plus Firefox and mitmproxy on one Docker
network.

Hostnames (inside the compose network):

- ocis1: `https://ocis1.docker/`
- ocis2: `https://ocis2.docker/`
- mitmweb UI: `https://ocis-mitmproxy.docker/`

### Prerequisites

- Docker with Compose v2
- DockyPody images built locally:
  - `mitmproxy:v12.2.2`
  - `firefox:v150.0.0`
  - `ocis:v8.0.1` (or the tag in `OCIS_IMAGE`)

### Quick start

From this directory:

```bash
docker compose up -d --wait
```

`--wait` blocks until both oCIS containers pass their compose healthcheck (curl
HTTPS root). Firefox starts only after both instances report ready.

### Firefox UI (host port)

- Firefox desktop UI: `https://localhost:5800`

### Cleanup

```bash
docker compose down
```
