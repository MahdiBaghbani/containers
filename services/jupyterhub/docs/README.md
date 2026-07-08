# JupyterHub OCM Webapp Runtime Service

JupyterHub image that terminates the OCM webapp-share launch. It is the remote
application that both the Nextcloud sender (`integration_jupyterhub`) and the
receiver (CERNBox or `ocmremotewebapp`) hand off to:

```
POST /services/ocm/open  ->  hub authenticator handoff  ->  302 .../lab
```

## Overview

The image layers the `nextcloud-ocm-jupyterhub` package onto the upstream
`quay.io/jupyterhub/k8s-hub` base:

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

- `quay.io/jupyterhub/k8s-hub:4.2.0` (pinned in `versions.nuon` as
  `external_images.runtime.tag`; wired via `platforms.nuon` build arg
  `BASE_HUB_IMAGE`)

## Required environment

See the upstream `hub/` package README for field semantics. The hub image reads
these at startup:

| Variable | Purpose |
| --- | --- |
| `NEXTCLOUD_HOST` | Public hostname of the paired Nextcloud (OAuth URLs) |
| `NEXTCLOUD_CLIENT_ID`, `NEXTCLOUD_CLIENT_SECRET` | OAuth client from the NC admin UI |
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
