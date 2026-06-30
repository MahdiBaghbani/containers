## Example: two OpenCloud + Firefox + mitmproxy

This example runs two OpenCloud instances plus Firefox and mitmproxy on one
Docker network.

Hostnames (inside the compose network):

- opencloud1: `https://opencloud1.docker/`
- opencloud2: `https://opencloud2.docker/`
- mitmweb UI: `https://opencloud-mitmproxy.docker/`

### Prerequisites

- Docker with Compose v2
- DockyPody images built locally:
  - `mitmproxy:v12.2.2`
  - `firefox:v150.0.0`
  - `opencloud:v6.1.0` (or the tag in `OPENCLOUD_IMAGE`)

### Quick start

From this directory:

```bash
docker compose up -d --wait
```

`--wait` blocks until both OpenCloud containers pass their compose healthcheck
(curl HTTPS root). Firefox starts only after both instances report ready.

### Firefox UI (host port)

- Firefox desktop UI: `https://localhost:5800`

### Cleanup

```bash
docker compose down
```
