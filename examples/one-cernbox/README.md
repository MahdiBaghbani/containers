## Example: one-cernbox local-network lab

This example runs a single CERNBox stack on one Docker network with:

- local-network HTTPS on `https://cernbox1.docker/`
- local-network Keycloak on `https://idp.docker/`
- direct in-network browser access through Kasm Firefox
- Reva master-band behavior with the `master-development` cernbox-revad image

### Prerequisites

- Docker with Compose v2
- Nushell
- TLS material generated once from `repos/containers`:

```bash
make tls all
```

- Local DockyPody images built from `repos/containers`:

```bash
nu scripts/dockypody.nu build --service firefox --version v150.0.0
nu scripts/dockypody.nu build --service idp --version v26.4.2
nu scripts/dockypody.nu build --service cernbox-web --version master
nu scripts/dockypody.nu build --service cernbox-revad --version master-development --platform development
```

### Configuration

The tracked `.env` file is the source of truth for local defaults.

Important defaults:

- `CERNBOX_DOMAIN=cernbox1.docker`
- `IDP_URL=https://idp.docker`
- `IMAGE_CERNBOX_REVAD=master-development`
- `IMAGE_CERNBOX_WEB=master`
- `FIREFOX_UI_PORT=5802`
- `FIREFOX_START_URL=https://cernbox1.docker/`

The example keeps Reva microservices on internal HTTP while `cernbox-web` and
the IdP serve HTTPS directly on the compose network.

### Clean reset

If you need a fully clean restart after domain or config changes:

```bash
docker compose down --remove-orphans --timeout 5 || true
rm -rf volumes
```

This clears generated `/etc/revad` mounts and the persisted cernbox web
`config.json`, so the stack can re-template against the current `.env` values.

### Quick start

From this directory:

```bash
docker compose up -d
```

### Firefox UI

- Firefox desktop UI: `https://localhost:5802`

The Firefox container serves the desktop UI on port 6901; compose maps it to
5802 on the host by default.

### What to validate

1. Open Firefox at `https://localhost:5802`.
2. It should auto-open `https://cernbox1.docker/`.
3. Log into CERNBox and confirm the OIDC redirect reaches `https://idp.docker/`.
4. Confirm login returns to `https://cernbox1.docker/`.
5. Validate the master-band OCM flow you care about:
   - OCM share creation
   - webapp protocol negotiation
   - open remotely from `web-app-ocm`
   - share-root open
   - nested-path open inside a received share

### Troubleshooting

- If `docker compose up` fails because a local image is missing, rebuild the
  exact image tag used in `.env`.
- If Firefox shows TLS warnings, regenerate TLS material with `make tls all`
  and rebuild the local images.
- If login redirects to an old public domain, clear `volumes/data/cernbox-web`
  and restart so `config.json` is re-templated.
- If Reva still advertises stale domain values, clear `volumes/config/reva-*`
  and restart so `/etc/revad` is regenerated from the current env.

### Cleanup

```bash
docker compose down
```
