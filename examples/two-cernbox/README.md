## Example: two-cernbox local OCM lab

This example runs two CERNBox stacks on one Docker network with:

- local-network HTTPS on `https://cernbox1.docker/`
- local-network HTTPS on `https://cernbox2.docker/`
- per-instance local-network Keycloak on `https://idp1.docker/` (cernbox1) and
  `https://idp2.docker/` (cernbox2)
- shared Firefox desktop UI exposed on the host
- mitmproxy on the same Docker network for best-effort server-to-server capture
- Reva master-band behavior with the `master-development` cernbox-revad image

This is a sender / receiver lab, not a production deployment.

Hostnames inside the compose network:

- cernbox1: `https://cernbox1.docker/`
- cernbox2: `https://cernbox2.docker/`
- idp1 (cernbox1): `https://idp1.docker/`
- idp2 (cernbox2): `https://idp2.docker/`
- MITM proxy transport: `http://mitm:8080`
- mitmweb UI: `https://mitmproxy.docker/`

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
nu scripts/dockypody.nu build --service idp --version v26.4.2
nu scripts/dockypody.nu build --service cernbox-web --version master
nu scripts/dockypody.nu build --service cernbox-revad --version master-development --platform development
```

### Configuration

The tracked `.env` file is the source of truth for local defaults.

Important defaults:

- `IMAGE_CERNBOX_REVAD=master-development`
- `IMAGE_CERNBOX_WEB=master`
- `MITMPROXY_IMAGE=mitmproxy:v12.2.2`
- `FIREFOX_UI_PORT=5803`
- `FIREFOX_START_URL=https://cernbox1.docker/`
- `CERNBOX1_DOMAIN=cernbox1.docker`
- `CERNBOX2_DOMAIN=cernbox2.docker`
- `IDP1_URL=https://idp1.docker`
- `IDP2_URL=https://idp2.docker`
- `CERNBOX_HTTP_PROXY=http://mitm:8080`
- `CERNBOX_HTTPS_PROXY=http://mitm:8080`

The example keeps Reva microservices on internal HTTP while both `cernbox-web`
instances and both IdPs serve HTTPS directly on the compose network.

### Important MITM note

This stack wires the example for proxy-based observation, but it is still
best-effort on the Reva side.

The compose file injects `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` into the
Reva services that are the most likely outbound OCM callers. The tracked `.env`
also lets you test strict vs bypassed TLS behavior by changing
`OCM_CLIENT_INSECURE`.

That said, core Reva OCM client code does not consistently honor proxy env
variables for every outbound path, so treat mitmproxy here as an observability
aid, not as a guaranteed full capture point for every OCM hop.

### Clean reset

If you need a fully clean restart after domain or config changes:

```bash
docker compose down --remove-orphans --timeout 5 || true
rm -rf volumes
```

This clears generated `/etc/revad` mounts, both cernbox web data trees, and the
shared JSON state so the stack can re-template against the current `.env`
values.

### Quick start

From this directory:

```bash
docker compose up -d --wait
```

`--wait` blocks until services with baked image healthchecks (both IdPs, Reva
dev images, both cernbox-web instances) report healthy. Readiness is defined in
the Dockerfiles, not duplicated in this compose file.

### Firefox UI

- Firefox desktop UI: `https://localhost:5803`

The Firefox container serves the desktop UI on port 6901; compose maps it to
5803 on the host by default.

Suggested tabs once Firefox is up:

1. `https://cernbox1.docker/`
2. `https://cernbox2.docker/`
3. `https://mitmproxy.docker/`

### Login users

The baked Keycloak realm includes these demo users:

- `einstein` / `relativity`
- `marie` / `radioactivity`

The Keycloak bootstrap admin remains `admin` / `admin`, but you should not need
that for normal CERNBox sender / receiver testing.

### What to validate

1. Open Firefox at `https://localhost:5803`.
2. It should auto-open `https://cernbox1.docker/`.
3. Log into `cernbox1.docker` as one user and confirm the OIDC redirect reaches
   `https://idp1.docker/`.
4. Open `https://cernbox2.docker/` in a second tab and log into it as the other
   user; its OIDC redirect reaches `https://idp2.docker/`.
5. Keep `https://mitmproxy.docker/` open in a third tab when you want
   to inspect mitmweb.
6. Validate the two-node OCM flow you care about:
   - OCM share creation from one CERNBox node to the other
   - webapp protocol negotiation
   - open remotely from `web-app-ocm`
   - share-root open
   - nested-path open inside a received share

### Manual OCM sender / receiver flow

Use `cernbox1` as sender and `cernbox2` as receiver.

1. Log into `cernbox1.docker` as `einstein`.
2. Log into `cernbox2.docker` as `marie`.
3. Create the remote share or open-remote flow from `cernbox1` toward
   `cernbox2`.
4. Accept or open the received content on `cernbox2`.
5. Watch mitmweb for any cross-node flows that do traverse the configured
   proxy.

### Optional explicit proxy smoke test

If you want one direct proof that the proxy itself is reachable on the compose
network, run a proxied request manually from any container that has `curl`:

```bash
docker compose exec <container-with-curl> sh -lc 'curl -fsS -x http://mitm:8080 https://cernbox2.docker/ | head -c 200'
```

That check proves the proxy path exists. It does not prove every Reva OCM code
path will use it.

### Troubleshooting

- If `docker compose up` fails because a local image is missing, rebuild the
  exact image tag used in `.env`.
- If Firefox shows TLS warnings, regenerate TLS material with `make tls all`
  and rebuild the local images.
- If either CERNBox login redirects to an old public domain, clear the matching
  `volumes/cernbox1/data/cernbox-web` or `volumes/cernbox2/data/cernbox-web`
  tree and restart so `config.json` is re-templated.
- If Reva still advertises stale domain values, clear the matching
  `volumes/cernbox1/config/reva-*` or `volumes/cernbox2/config/reva-*` trees and
  restart so `/etc/revad` is regenerated from the current env.
- If mitmweb stays empty during normal OCM flows, that can simply mean the
  specific Reva path bypassed proxy env usage. The stack wiring is still useful
  for future Reva-side transport work.

### Cleanup

```bash
docker compose down
```
