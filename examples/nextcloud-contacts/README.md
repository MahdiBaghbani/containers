## Example: two Nextcloud Contacts nodes + Firefox + mitmproxy

This example runs a local two-node Nextcloud Contacts lab for OCM invite work.
It is meant for sender/receiver testing, not generic Nextcloud browsing.

What this stack gives you:

- 2 isolated Nextcloud Contacts instances on one compose network
- HTTPS on stable in-network hostnames: `nextcloud1.docker` and `nextcloud2.docker`
- Firefox desktop UI exposed to the host
- mitmproxy for server-to-server OCM traffic capture
- Contacts OCM invites enabled in `advanced` mode
- local federation enabled with `NEXTCLOUD_ALLOW_LOCAL_REMOTE_SERVERS_MODE=allow`

Hostnames inside the compose network:

- nextcloud1: `https://nextcloud1.docker/`
- nextcloud2: `https://nextcloud2.docker/`
- mitmweb UI: `https://nextcloud-mitmproxy.docker/`

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
```

- A local-plane versions fragment for `nextcloud-contacts` (git-ignored).
  The `local` image tag is **not** a tracked manifest version; it lives only
  in the off-git local plane.

<!-- dockypody-docs-allow: nextcloud-contacts:local -->

  1. Create the local plane root (once):

```bash
mkdir -p .dockypody.local/services/nextcloud-contacts
```

  2. Add a versions fragment (sample only; same JSONC style as tracked
     manifests):

```nuon
{
  "versions": [
    {
      "name": "local",
      "latest": false,
      "overrides": {
        "sources": {
          "contacts": {
            "path": "../nextcloud-contacts"
          }
        }
      }
    }
  ]
}
```

Save as `.dockypody.local/services/nextcloud-contacts/versions.nuon`.

3. Build the local-plane version:

```bash
nu scripts/dockypody.nu build --plane local --service nextcloud-contacts --version local
```

This example uses `IMAGE_NEXTCLOUD_CONTACTS=local` in `.env`, so build the
local-plane `local` Contacts image before `docker compose up`.

### Configuration

The tracked `.env` file is the source of truth for local defaults.

Important defaults:

- `IMAGE_NEXTCLOUD_CONTACTS=local`
- `FIREFOX_UI_PORT=5801`
- `FIREFOX_START_URL=https://nextcloud1.docker/index.php/apps/contacts/ocm-invites`
- `CONTACTS_ENABLE_OCM_INVITES=true`
- `CONTACTS_OCM_INVITES_MODE=advanced`
- `NEXTCLOUD_ALLOW_LOCAL_REMOTE_SERVERS_MODE=allow`

Optional:

- set `CONTACTS_MESH_PROVIDERS_SERVICE` if you want a mesh-provider list
- change the admin or DB credentials in `.env` before first boot

### Quick start

From this directory:

```bash
docker compose up -d
```

### Firefox UI

- Firefox desktop UI: `https://localhost:5801`

The Firefox container serves the desktop UI on port 6901; compose maps it to
5801 on the host by default.

### What to validate

1. Open Firefox at `https://localhost:5801`.
2. It should auto-open the Contacts invites view on `nextcloud1.docker`.
3. Log into `nextcloud1.docker` with `admin` / `admin`.
4. Open `https://nextcloud2.docker/index.php/apps/contacts/ocm-invites` in a second tab.
5. Log into `nextcloud2.docker` with `admin` / `admin`.
6. Open `https://nextcloud-mitmproxy.docker/` when you want to inspect mitmweb.

Notes:

- This stack now uses a distinct compose project, network, container names, and
  Firefox host port, so it can coexist with the sibling `examples/nextcloud`
  stack.
- The explicit proxy smoke test below is the deterministic MITM capture check.
- `advanced` invite mode keeps email optional so you can share the invite link
  or token manually between the two tabs.

### Manual invite flow

Use `nextcloud1` as sender and `nextcloud2` as receiver.

1. In the `nextcloud1` tab, open Contacts OCM invites.
2. Create an invite without email, then copy the invite link or token.
3. In the `nextcloud2` tab, open the accept flow.
4. Paste the invite token or open the invite link while logged into `nextcloud2`.
5. Accept the invite and confirm the federated contact shows up.

If you are testing WAYF-style discovery, keep mitmweb open and watch for the
cross-node OCM requests.

### Deterministic cross-container capture smoke test

This proves mitmproxy can observe traffic from one Nextcloud container to the
other over the shared network when the request is explicitly proxied.

Run from this directory:

```bash
docker compose exec nextcloud1 sh -lc 'curl -fsS -x http://nextcloud-mitmproxy.docker:8080 https://nextcloud2.docker/.well-known/ocm | head -c 200'
```

Then open mitmweb and confirm there is a flow for
`nextcloud2.docker/.well-known/ocm`.

### Troubleshooting

- If `docker compose up` fails because `nextcloud-contacts:local` is missing,
  confirm `.dockypody.local/services/nextcloud-contacts/versions.nuon` exists,
  then rebuild with
  `nu scripts/dockypody.nu build --plane local --service nextcloud-contacts --version local`.
- If build fails with a tracked-plane "version not found" error for `local`,
  retry with `--plane local`. That version name exists only in the local
  fragment, not in tracked `services/nextcloud-contacts/versions.nuon`.
- If Firefox shows TLS warnings, regenerate TLS material with `make tls all`
  and rebuild the local images.
- If OCM invites do not appear, make sure you are using the `local` image and
  not a standard Contacts tag without OCM support.
- If sender-to-receiver federation fails, confirm
  `NEXTCLOUD_ALLOW_LOCAL_REMOTE_SERVERS_MODE=allow` is still present in `.env`.

### Cleanup

```bash
docker compose down
```
