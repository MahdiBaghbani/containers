# JupyterHub OCM Webapp Runtime Service

JupyterHub image that terminates the OCM webapp-share launch. It is the remote
application that both the Nextcloud sender (`integration_jupyterhub`) and the
receiver (CERNBox or `ocmremotewebapp`) hand off to:

```
POST /services/ocm/open  ->  GET /hub/ocm-login  ->  302 .../lab
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

The package source is the `hub/` subdir of the SUNET
`nextcloud-integration_jupyterhub` repository - the same repo the sender app
comes from. It is cloned at build time via `clone-source.nu` and pinned in
`versions.nuon` (source key `integration_jupyterhub`), exactly like every other
service. To own the source, repoint that URL/ref to a fork (as `cernbox-web`
points at a `MahdiBaghbani` fork).

## Base image

- `quay.io/jupyterhub/k8s-hub:4.2.0` (pinned to the SUNET upstream default;
  override with build arg `BASE_HUB_IMAGE`)

## Required environment

See the upstream `hub/` package README for the full table. Key variables:

| Variable | Purpose |
| --- | --- |
| `NEXTCLOUD_HOST` | Public hostname of the paired Nextcloud (OAuth URLs) |
| `NEXTCLOUD_CLIENT_ID`, `NEXTCLOUD_CLIENT_SECRET` | OAuth client from the NC admin UI |
| `JUPYTER_HOST` | Public hostname of the hub (`oauth_callback_url`, `public_url`) |
| `JUPYTERHUB_CRYPT_KEY` | 32-byte hex; required for `enable_auth_state` |
| `OCM_TRUSTED_BACK_CHANNEL_DOMAINS` | Allowlist of paired NC domains for `/services/ocm/{shares,revoke}` |
| `OCM_TRUSTED_ISSUER_DOMAINS` | Allowlist of OCM token issuers for `/services/ocm/open` |

## Building

```bash
nu scripts/dockypody.nu build --service jupyterhub

nu scripts/dockypody.nu inspect effective-config --service jupyterhub
```

## See Also

- [nextcloud-webapp documentation](../../nextcloud-webapp/docs/README.md)
- Upstream package source: `hub/` in `SUNET/nextcloud-integration_jupyterhub`
