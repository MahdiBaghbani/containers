# JupyterHub OCM Webapp Runtime Service

JupyterHub image that terminates the OCM webapp-share launch. It is the remote
application that both the Nextcloud sender (`integration_jupyterhub`) and the
receiver (CERNBox or `ocmremotewebapp`) hand off to:

```
POST /services/ocm/open  ->  hub authenticator handoff  ->  302 .../lab
```

## Overview

The image layers the `nextcloud-ocm-jupyterhub` package onto the upstream
all-in-one `quay.io/jupyterhub/jupyterhub` base:

- **Authenticator** - `NextcloudOAuthenticator` (OCM `pre_spawn_start` /
  `refresh_user` hooks)
- **Managed services** - `ocm` (back-channel share push + browser launch) and
  `refresh-token`, mounted under `/services/ocm/`
- **Baked config** - `config/jupyterhub_config.py` using `SimpleSpawner` so the
  launch lands at `/lab` without a notebook image (Layer 3 deferred)
- **TLS** - first-class DockyPody TLS on `https://:443` with host identity
  `jupyterhub1.docker`

The package source is the `hub/` subdir of the SUNET
`nextcloud-integration_jupyterhub` repository - the same repo the sender app
comes from. It is cloned at build time via `clone-source.nu` and pinned in
`versions.nuon` (source key `integration_jupyterhub`), exactly like every other
service. To own the source, repoint that URL/ref to a fork (as `cernbox-web`
points at a `MahdiBaghbani` fork).

## Base image

- `quay.io/jupyterhub/jupyterhub:5.3.0` (pinned in `versions.nuon` as
  `external_images.runtime.tag`; wired via `platforms.nuon` build arg
  `BASE_HUB_IMAGE`)

This is the **all-in-one** JupyterHub image: it bundles JupyterHub, Node, and
`configurable-http-proxy` in a single container, which matches our deployment
shape (one container per role, in-hub TLS on `:443`, local `SimpleSpawner`).
JupyterHub's default proxy runs the `configurable-http-proxy` binary locally, so
it must be present in the image. The Zero-to-K8s `k8s-hub` image is intentionally
not used: it expects an external proxy pod and omits that binary, so the hub
cannot start standalone. The Dockerfile guards this with a build-time
`configurable-http-proxy --version` check and the entrypoint guards it at runtime
(`entrypoint-init.nu` proxy preflight). Because this base runs as root with no
UID 1000 user, the Dockerfile provisions `jovyan` (UID 1000) and hands it the hub
state dir so the hub still runs unprivileged under the `NET_BIND_SERVICE`
contract below.

## Required environment

See the upstream `hub/` package README for field semantics. The hub image reads
these at startup:

| Variable | Purpose |
| --- | --- |
| `NEXTCLOUD_HOST` | Public hostname of the paired Nextcloud (OAuth URLs) |
| `NEXTCLOUD_CLIENT_ID`, `NEXTCLOUD_CLIENT_SECRET` | OAuth client; set directly, or omit and let the OAuth handoff file provide them (see below) |
| `JUPYTERHUB_API_KEY`, `JUPYTERHUB_OCM_API_KEY` | Required hub service API tokens from the upstream package |
| `JUPYTER_HOST` | Public hub base URL for `oauth_callback_url` and `public_url` (see below) |
| `JUPYTERHUB_CRYPT_KEY` | 32-byte hex; required for `enable_auth_state` |
| `OCM_TRUSTED_BACK_CHANNEL_DOMAINS` | Allowlist of paired NC domains for `/services/ocm/{shares,revoke}` |
| `OCM_TRUSTED_ISSUER_DOMAINS` | Allowlist of OCM token issuers for `/services/ocm/open` |

Runtime TLS wiring:

| Variable | Purpose |
| --- | --- |
| `DOCKYPODY_TLS_CERT_NAME` | Baked cert basename (default `jupyterhub`); Python and Nushell derive `/tls/<name>.{crt,key}` from it |
| `JUPYTERHUB_SSL_CERT`, `JUPYTERHUB_SSL_KEY` | Optional explicit overrides; when unset the service falls back to `/tls/<cert_name>.{crt,key}` |

### OAuth client handoff

The hub's `NextcloudOAuthenticator` needs a Nextcloud OAuth client
(`NEXTCLOUD_CLIENT_ID` / `NEXTCLOUD_CLIENT_SECRET`). For deployments where the
paired Nextcloud provisions the client dynamically (the OCM webapp-share
topology), pass the two values indirectly through a shared file instead of
static env:

| Variable | Purpose |
| --- | --- |
| `NEXTCLOUD_OAUTH_ENV_FILE` | Path to a KEY=VALUE file carrying `INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_ID` and `INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_SECRET` |

The sender Nextcloud (`nextcloud-webapp`, hook
`91-configure-integration-jupyterhub.nu`) runs `oauth2:add-client` and writes
those keys to `INTEGRATION_JUPYTERHUB_OAUTH_ENV_FILE`. Mount the same path into
both containers (a shared volume) and set `NEXTCLOUD_OAUTH_ENV_FILE` here.

Resolution order: direct `NEXTCLOUD_CLIENT_ID`/`NEXTCLOUD_CLIENT_SECRET` win;
otherwise the values are read from `NEXTCLOUD_OAUTH_ENV_FILE`. Because the
sender provisions the client asynchronously, `entrypoint-init.nu` waits (up to
300s by default) for the handoff file before `jupyterhub_config.py` runs, so the
hub does not crash-loop while Nextcloud finishes installing. The readiness gate
requires both keys to carry non-empty values, so a half-written file does not
pass. Set `JUPYTERHUB_OAUTH_WAIT_TIMEOUT_SEC` to override the wait budget
(seconds; invalid or negative values fall back to 300).

TLS is required for this service. `entrypoint-init.nu` validates the runtime
contract before `jupyterhub` starts, and `jupyterhub_config.py` independently
resolves and validates the final cert/key paths. The hub binds `https://:443`.
Because the image runs as UID `1000`, runtime stacks must grant
`NET_BIND_SERVICE` when they want in-container HTTPS on port `443`.

### `JUPYTER_HOST` URL shape (HTTPS on 443 only)

`JUPYTER_HOST` is the **public** hostname clients and OAuth use. The hub binds
`https://:443`, so only the standard HTTPS endpoint is supported. Accepted
forms are a bare hostname or `https://...`. Explicit `:443` is accepted for
compatibility but normalized away. Any other port (for example `:8443`) is
rejected. `http://` is rejected.

At hub startup, `jupyterhub_config.py` normalizes `JUPYTER_HOST` to a bare
hostname in `os.environ` before the SUNET authenticator builds the OAuth
callback (`https://` + `JUPYTER_HOST` + `/hub/oauth_callback`). That prevents
doubled schemes when operators pass `https://...`. `public_url` is always
`https://<hostname>` with no port suffix.

| Operator `JUPYTER_HOST` | Normalized env value | `public_url` | OAuth callback |
| --- | --- | --- | --- |
| `jupyterhub1.docker` | `jupyterhub1.docker` | `https://jupyterhub1.docker` | `https://jupyterhub1.docker/hub/oauth_callback` |
| `https://jupyterhub1.docker` | `jupyterhub1.docker` | `https://jupyterhub1.docker` | `https://jupyterhub1.docker/hub/oauth_callback` |
| `jupyterhub1.docker:443` | `jupyterhub1.docker` | `https://jupyterhub1.docker` | `https://jupyterhub1.docker/hub/oauth_callback` |
| `https://jupyterhub1.docker:443` | `jupyterhub1.docker` | `https://jupyterhub1.docker` | `https://jupyterhub1.docker/hub/oauth_callback` |

Paired Nextcloud sender hooks accept the same hostname or `https://` base URL
forms; use HTTPS there as well.

## Building

```bash
nu scripts/dockypody.nu build --service jupyterhub

nu scripts/dockypody.nu inspect effective-config --service jupyterhub
```

## See Also

- [nextcloud-webapp documentation](../../nextcloud-webapp/docs/README.md)
- Upstream package source: `hub/` in `SUNET/nextcloud-integration_jupyterhub`
