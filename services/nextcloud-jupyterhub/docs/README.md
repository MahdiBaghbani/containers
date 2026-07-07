# Nextcloud JupyterHub Integration Service

Nextcloud service with the Contacts app and JupyterHub integration app
pre-installed. This image layers `integration_jupyterhub` on top of the
contacts-based sender stack used for OCM webapp-share work.

## Overview

`nextcloud-jupyterhub` extends `nextcloud-contacts` with:

- **integration_jupyterhub app** - Pre-baked and enabled by container hooks
- **Contacts + OCM stack** - Inherited from the `ocm-contacts-app` parent image
- **UI build integration** - npm/webpack build for the app frontend
- **Composer dependencies** - PHP autoloader generation for the app

The upstream repository also contains a sibling `hub/` Python package. Only
the `integration_jupyterhub/` Nextcloud app directory is baked into this image.

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
  nextcloud-jupyterhub:webapp-share-debian
```

## Environment Variables

This service inherits environment variables from `nextcloud-contacts` and
`nextcloud-base`. See:

- [nextcloud-contacts documentation](../../nextcloud-contacts/docs/README.md)
- [nextcloud-base documentation](../../nextcloud-base/docs/README.md)

### JupyterHub integration

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

## Versions

### webapp-share

- **Default**: `webapp-share`
- **Parent image**: `nextcloud-contacts:ocm-contacts-app-debian`
- **App source**: `https://github.com/SUNET/nextcloud-integration_jupyterhub`
- **App ref**: `main`
- **Purpose**: Branch-pinned sender image basis for the webapp-share flow

## Architecture

### Build Process

The integration app is built in multiple stages:

1. **Source Prepare** - Clone/copy upstream source, extract only
   `integration_jupyterhub/`
2. **UI Build** - Build frontend with `npm ci && npm run build`
3. **Composer Deps** - Generate PHP autoloader
4. **App Assemble** - Combine artifacts, remove dev files
5. **Runtime** - Copy to `/usr/src/apps/integration_jupyterhub`

### Runtime Integration

- App is baked to `/usr/src/apps/integration_jupyterhub` in the image
- At runtime, merged into `/usr/src/nextcloud/apps/integration_jupyterhub`
  by `nextcloud-base`
- Hooks enable the app, apply TTL/webapp-sharing/targets settings, and
  optionally set the hub URL plus OAuth when `JUPYTER_HOST` is present

### Hook Execution Order

Hooks execute alphabetically:

1. `before-starting/90-ensure-integration-jupyterhub.nu` - Re-enables the app
   when Nextcloud is installed but the app is disabled
2. `post-installation/90-enable-integration-jupyterhub.nu` - Enables the app
   after install
3. `post-installation/91-configure-integration-jupyterhub.nu` - Sets TTL,
   enables webapp sharing, sets targets to `blank`, and when `JUPYTER_HOST`
   is set runs `integration_jupyterhub:set-url` and OAuth provisioning

## Building

```bash
# Build the default webapp-share sender image
nu scripts/dockypody.nu build --service nextcloud-jupyterhub

# Preview merged config
nu scripts/dockypody.nu inspect effective-config --service nextcloud-jupyterhub
```

## See Also

- [nextcloud-contacts documentation](../../nextcloud-contacts/docs/README.md)
- [nextcloud-base documentation](../../nextcloud-base/docs/README.md)
- [Dockerfile Development Guide](../../../docs/guides/dockerfile-development.md)
