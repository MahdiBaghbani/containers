## Example: cypress + firefox + mitmproxy

This example runs three DockyPody images on the same Docker network so:

- `firefox.docker` can open `https://mitmproxy.docker/`
- `cypress.docker` can open the same URL in Chrome inside the Cypress desktop
- you can validate whether the DockyPody CA is trusted by both browsers

### Prerequisites

- Docker with Compose v2

### Quick start

From this directory:

```bash
docker compose up -d
```

To override images, CA name, or host ports using the tracked env file:

```bash
docker compose --env-file env up -d
```

### Where to connect (host ports)

This example preserves the former `ocm-test-suite` host port convention:

- Cypress desktop UI: `https://localhost:5700`
- Firefox desktop UI: `https://localhost:5800`

Note: these Kasm-based images serve the desktop UI on port 6901 inside the
container. The compose file maps that to 5700/5800 on the host for familiarity.

### What to validate

1. Open Firefox at `https://localhost:5800`.
2. It should auto-open `https://mitmproxy.docker/`.
3. If Firefox trusts the DockyPody CA, the mitmweb UI should load without a TLS
   warning.
4. Open Cypress at `https://localhost:5700`, then open Chrome inside it and
   browse to `https://mitmproxy.docker/` and compare behavior.

### Cypress project mount

The compose file mounts `./cypress-project` as `/workspace` and sets:

- `OCM_CYPRESS_PROJECT_DIR=/workspace`

This makes the example project the workspace root for Cypress.

### Cleanup

```bash
docker compose down
```

If you started the stack with `--env-file env`, use the same flag for down:

```bash
docker compose --env-file env down
```
