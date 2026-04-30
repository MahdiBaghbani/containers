## Example: two Nextcloud + Firefox + mitmproxy

This example runs 2 Nextcloud instances plus 1 Firefox and 1 mitmproxy container
on the same Docker network.

Goals:

- Keep everything self-contained (no Traefik, no external networks).
- Use stable in-network hostnames ending in `.docker`.
- Make DNS inside containers reliable by setting upstream resolvers in Compose.
- Expose only the Firefox desktop UI port to the host.
- Make it easy to capture traffic with mitmproxy while driving the UI in Firefox.

Hostnames (inside the compose network):

- nextcloud1: `https://nextcloud1.docker/`
- nextcloud2: `https://nextcloud2.docker/`
- mitmweb UI: `https://nextcloud-mitmproxy.docker/`

### Prerequisites

- Docker with Compose v2
- DockyPody images built locally:
  - `mitmproxy:v1.0.0`
  - `firefox:v1.0.0`
  - `nextcloud-contacts:<tag>` (set by `IMAGE_NEXTCLOUD_CONTACTS`)

### Quick start

From this directory:

```bash
docker compose up -d
```

### Firefox UI (host port)

- Firefox desktop UI: `https://localhost:5800`

The container serves the desktop UI on port 6901; the compose file maps it to
5800 on the host by default.

### What to validate

1. Open Firefox at `https://localhost:5800`.
2. It should auto-open `https://nextcloud1.docker/`.
3. Open `https://nextcloud2.docker/` in another tab.
4. Open `https://nextcloud-mitmproxy.docker/` when you want to inspect mitmweb.

Notes:

- This compose stack uses platform-specific hostnames so it can run beside the
  other examples without container-name collisions.
- The explicit proxy smoke test below is the deterministic MITM capture check.
- Nextcloud is configured for WAYF-style contacts invites UX with:
  - `CONTACTS_ENABLE_OCM_INVITES=true`
  - `CONTACTS_OCM_INVITES_MODE=advanced`

### A deterministic cross-container capture smoke test

This proves mitmproxy can observe traffic from one Nextcloud container to the
other over the shared network when the request is explicitly proxied.

Run from this directory:

```bash
docker exec nextcloud1.docker sh -lc 'curl -fsS -x http://nextcloud-mitmproxy.docker:8080 https://nextcloud2.docker/.well-known/ocm | head -c 200'
```

Then open mitmweb and confirm there is a flow for `nextcloud2.docker/.well-known/ocm`.

### Cleanup

```bash
docker compose down
```
