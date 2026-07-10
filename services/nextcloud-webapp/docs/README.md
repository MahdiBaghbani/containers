# Nextcloud OCM Webapp Endpoints Service

Nextcloud service with the Contacts app plus **both** OCM webapp-share
Nextcloud apps pre-installed on one image:

- **integration_jupyterhub** - sender app: turns a notebook folder into an OCM
  webapp share and pushes it to a remote JupyterHub.
- **ocmremotewebapp** - receiver app: accepts inbound OCM webapp shares and
  presents a launch surface.

One image serves both roles; the running actor and config decide whether an
instance acts as sender or receiver. This mirrors how `nextcloud-contacts`
serves both sender and receiver roles for the contact-token flow.

## Overview

`nextcloud-webapp` extends `nextcloud-contacts` with:

- **integration_jupyterhub app** - sender, enabled by container hooks
- **ocmremotewebapp app** - receiver, enabled by container hooks
- **Contacts + OCM stack** - inherited from the `ocm-webapp-share` parent image
  (Contacts is required for OCM trust establishment before any share is accepted)
- **Rebased server base** - carries `LocalOCMDiscoveryEvent::getProvider()` that
  both apps depend on
- **UI + Composer build** - npm build and PHP autoloader generation for each app

The upstream `nextcloud-integration_jupyterhub` repository also contains a
sibling `hub/` Python package. That is the JupyterHub runtime and is packaged
separately as the `jupyterhub` service; only the `integration_jupyterhub/`
Nextcloud app directory is baked into this image.

## Quick Start

```bash
docker run -d \
  -p 80:80 \
  -e NEXTCLOUD_ADMIN_USER=admin \
  -e NEXTCLOUD_ADMIN_PASSWORD=secret \
  -e MYSQL_HOST=db \
  -e MYSQL_DATABASE=nextcloud \
  -e MYSQL_USER=nextcloud \
  -e MYSQL_PASSWORD=dbsecret \
  nextcloud-webapp:webapp-share-debian
```

## Environment Variables

This service inherits environment variables from `nextcloud-contacts` and
`nextcloud-base`. See:

- [nextcloud-contacts documentation](../../nextcloud-contacts/docs/README.md)
- [nextcloud-base documentation](../../nextcloud-base/docs/README.md)

### Sender: JupyterHub integration

Post-installation hooks configure the baked `integration_jupyterhub` app:

1. Enable the app (`90-enable-integration-jupyterhub.nu`)
2. Set OCM access token TTL, enable webapp sharing, and set webapp targets to
   `blank` (`91-configure-integration-jupyterhub.nu`)
3. When `JUPYTER_HOST` is set, call `integration_jupyterhub:set-url` and
   provision OAuth for the JupyterHub callback
   (`91-configure-integration-jupyterhub.nu`)

`before-starting/90-ensure-integration-jupyterhub.nu` re-enables the app on
later starts when Nextcloud is already installed.

- `JUPYTER_HOST` - JupyterHub host or base URL (optional)
  - Type: String (hostname or URL)
  - Default: Unset
  - When set, hooks run `integration_jupyterhub:set-url` with
    `https://<host>` (or the URL as given if it already includes a scheme)
  - Also provisions an OAuth client for
    `<hub-url>/hub/oauth_callback` via `oauth2:add-client`
  - When unset, hub URL and OAuth provisioning are skipped (TTL, webapp
    sharing, and targets are still applied)

- `INTEGRATION_JUPYTERHUB_OCM_ACCESS_TOKEN_TTL` - OCM access token lifetime
  - Type: Integer (seconds)
  - Default: `3600`
  - Maps to app config: `integration_jupyterhub ocm_access_token_ttl`

OAuth client credentials are written to
`/var/www/html/data/integration_jupyterhub_oauth.env` as
`INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_ID` and
`INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_SECRET`. Existing credentials are left
unchanged on later runs.

### Receiver: OCM Remote WebApp

Post-installation hook `92-enable-ocmremotewebapp.nu` enables the
`ocmremotewebapp` app; `before-starting/91-ensure-ocmremotewebapp.nu` re-enables
it on later starts. The receiver app needs no additional OCC configuration - it
registers its `folder` federation provider at boot and discovers the sender
origin from the inbound share.

## Versions

### webapp-share

- **Default**: `webapp-share`
- **Parent image**: `nextcloud-contacts:ocm-webapp-share-debian`
- **Sender app source**: `https://github.com/SUNET/nextcloud-integration_jupyterhub` (`main`)
- **Receiver app source**: `https://github.com/SUNET/ocmremotewebapp` (`main`)
- **Purpose**: Branch-pinned image basis carrying both webapp-share endpoints

## Architecture

### Build Process

Each app is built in parallel multi-stage lanes:

1. **Source Prepare** - Clone/copy upstream source; the sender lane extracts only
   `integration_jupyterhub/`, the receiver lane uses the app repo root
2. **UI Build** - Build frontend with `npm ci && npm run build`; both lanes build
   under the one manifest node image (`external_images.build.tag`, node 20 / npm 10).
   node 20 matches `integration_jupyterhub`'s lock, satisfies `vite 7` (node >=20.19),
   and npm 10 tolerates the `ocmremotewebapp` upstream lock that npm 11's stricter
   `npm ci` rejects
3. **Composer Deps** - Generate PHP autoloader
4. **App Assemble** - Combine artifacts, remove dev files
5. **Runtime** - Copy to `/usr/src/apps/{integration_jupyterhub,ocmremotewebapp}`

### Runtime Integration

- Apps are baked to `/usr/src/apps/integration_jupyterhub` and
  `/usr/src/apps/ocmremotewebapp` in the image
- At runtime, merged into `/usr/src/nextcloud/apps/...` by `nextcloud-base`
- Hooks enable both apps; the sender hooks additionally apply
  TTL/webapp-sharing/targets and, when `JUPYTER_HOST` is set, the hub URL and
  OAuth provisioning

### Hook Execution Order

Hooks execute alphabetically:

1. `before-starting/90-ensure-integration-jupyterhub.nu` - re-enable sender app
2. `before-starting/91-ensure-ocmremotewebapp.nu` - re-enable receiver app
3. `post-installation/90-enable-integration-jupyterhub.nu` - enable sender app
4. `post-installation/91-configure-integration-jupyterhub.nu` - sender config
5. `post-installation/92-enable-ocmremotewebapp.nu` - enable receiver app

## Building

```bash
# Build the default webapp-share image (both endpoints)
nu scripts/dockypody.nu build --service nextcloud-webapp

# Preview merged config
nu scripts/dockypody.nu inspect effective-config --service nextcloud-webapp
```

## See Also

- [nextcloud-contacts documentation](../../nextcloud-contacts/docs/README.md)
- [nextcloud-base documentation](../../nextcloud-base/docs/README.md)
- [jupyterhub documentation](../../jupyterhub/docs/README.md)
- [Dockerfile Development Guide](../../../docs/guides/dockerfile-development.md)
