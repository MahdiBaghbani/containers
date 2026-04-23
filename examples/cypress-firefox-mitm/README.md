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

This example uses a tracked `.env` file for image tags, CA name, and host
ports. Edit `.env` if you need different values.

### Where to connect (host ports)

This example preserves the former `ocm-test-suite` host port convention:

- Cypress desktop UI: `https://localhost:5900`
- Firefox desktop UI: `https://localhost:5800`

Note: these Kasm-based images serve the desktop UI on port 6901 inside the
container. The compose file maps that to 5900/5800 on the host for familiarity.

### What to validate

1. Open Firefox at `https://localhost:5800`.
2. It should auto-open `https://mitmproxy.docker/`.
3. If Firefox trusts the DockyPody CA, the mitmweb UI should load without a TLS
   warning.
4. Open Cypress at `https://localhost:5900`, then open Chrome inside it and
   browse to `https://mitmproxy.docker/` and compare behavior.

Note: Cypress runs its own local proxy to instrument browser traffic. This
means Chrome launched by Cypress may show a certificate issued by `CypressProxyCA`
instead of the DockyPody CA. This is expected.
The key signal is that the page loads without a certificate warning once the
Cypress proxy CA is trusted by Chrome.

### Cypress project mount

The compose file mounts `./cypress-project` as `/workspace` and sets:

- `OCM_CYPRESS_PROJECT_DIR=/workspace`

This makes the example project the workspace root for Cypress.

### Cleanup

```bash
docker compose down
```
