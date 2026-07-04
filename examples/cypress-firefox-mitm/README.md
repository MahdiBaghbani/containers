## Example: cypress + firefox + mitmproxy

This example runs three DockyPody images on one Docker network with:

- local-network mitmweb on `https://cypress-mitmproxy.docker/`
- direct in-network browser access through Kasm Firefox
- direct in-network browser access through the Cypress desktop image
- a small mounted Cypress project for manual browser-side validation

This is a CA-trust and browser-runtime lab, not a production deployment.

Hostnames inside the compose network:

- mitmweb UI: `https://cypress-mitmproxy.docker/`
- Firefox desktop container: `cypress-firefox.docker`
- Cypress desktop container: `cypress-runner.docker`

### Prerequisites

- Docker with Compose v2
- Nushell
- TLS material generated once from `repos/containers`:

```bash
make tls all
```

- Local DockyPody images built from `repos/containers`:

```bash
nu scripts/dockypody.nu build --service mitmproxy --version v12.2.2
nu scripts/dockypody.nu build --service firefox --version v150.0.0
nu scripts/dockypody.nu build --service cypress --version v15.14.1 --platform dev
```

### Configuration

The tracked `.env` file is the source of truth for local defaults.

Important defaults:

- `MITMPROXY_IMAGE=mitmproxy:v12.2.2`
- `FIREFOX_IMAGE=firefox:v150.0.0`
- `CYPRESS_IMAGE=cypress:v15.14.1-dev`
- `MITM_CA_NAME=dockypody`
- `CYPRESS_UI_PORT=5900`
- `FIREFOX_UI_PORT=5800`

The compose file mounts `./cypress-project` as `/workspace` and sets
`OCM_CYPRESS_PROJECT_DIR=/workspace`, so the sample project becomes the
workspace root inside the Cypress desktop image.

Firefox auto-opens `https://cypress-mitmproxy.docker/` on startup so you can
check CA trust immediately.

### Clean reset

If you need a fully clean restart after image or TLS changes:

```bash
docker compose down --remove-orphans --timeout 5 || true
```

This example is mostly stateless, so a compose shutdown is usually enough.

### Quick start

From this directory:

```bash
docker compose up -d
```

### Desktop UIs

- Cypress desktop UI: `https://localhost:5900`
- Firefox desktop UI: `https://localhost:5800`

Both Kasm-based images serve the desktop UI on port 6901 inside the container.
Compose maps that to 5900/5800 on the host for familiarity.

### What to validate

1. Open Firefox at `https://localhost:5800`.
2. It should auto-open `https://cypress-mitmproxy.docker/`.
3. If Firefox trusts the DockyPody CA, the mitmweb UI should load without a TLS
   warning.
4. Open Cypress at `https://localhost:5900`, then open Chrome inside it and
   browse to `https://cypress-mitmproxy.docker/`.
5. Compare the two browser runtimes:
   - Firefox proves the DockyPody CA is trusted in the standalone browser.
   - Chrome inside the Cypress desktop proves the page still loads in the
     Cypress-controlled browser environment.

Note: Cypress runs its own local proxy to instrument browser traffic. Chrome
launched by Cypress may therefore show a certificate issued by `CypressProxyCA`
instead of the DockyPody CA. This is expected. The key signal is that the page
loads without a browser certificate warning once the Cypress proxy CA is
trusted by Chrome.

### Troubleshooting

- If `docker compose up` fails because a local image is missing, rebuild the
  exact image tag used in `.env`.
- If Firefox shows TLS warnings, regenerate TLS material with `make tls all`
  and rebuild the local images.
- If Chrome inside Cypress shows a different CA issuer, that can be normal;
  focus on whether the page loads without a browser security block.
- If the mounted sample project is not visible inside Cypress, confirm
  `./cypress-project` is mounted as `/workspace`.

### Cleanup

```bash
docker compose down
```
