# Nextcloud Contacts Service

Nextcloud service with Contacts app pre-installed and OCM Invites feature support.

## Overview

`nextcloud-contacts` extends `nextcloud-base` with:

- **Contacts app** - Pre-baked and automatically enabled
- **OCM Invites support** - Optional feature for Open Cloud Mesh invitation workflow
- **UI build integration** - Automated npm build process for contacts app frontend
- **Composer dependencies** - PHP autoloader generation for contacts app

## Quick Start

### Basic Deployment

```bash
docker run -d \
  -p 80:80 \
  -e NEXTCLOUD_ADMIN_USER=admin \
  -e NEXTCLOUD_ADMIN_PASSWORD=secret \
  -e MYSQL_HOST=db \
  -e MYSQL_DATABASE=nextcloud \
  -e MYSQL_USER=nextcloud \
  -e MYSQL_PASSWORD=dbsecret \
  nextcloud-contacts:latest
```

### With OCM Invites Enabled

```bash
docker run -d \
  -p 80:80 \
  -e NEXTCLOUD_ADMIN_USER=admin \
  -e NEXTCLOUD_ADMIN_PASSWORD=secret \
  -e MYSQL_HOST=db \
  -e MYSQL_DATABASE=nextcloud \
  -e MYSQL_USER=nextcloud \
  -e MYSQL_PASSWORD=dbsecret \
  -e CONTACTS_ENABLE_OCM_INVITES=true \
  -e CONTACTS_MESH_PROVIDERS_SERVICE=https://surfdrive.surf.nl/index.php/s/d0bE1k3P1WHReTq/download \
  nextcloud-contacts:ocm-testing
```

## Environment Variables

### Contacts App Configuration

- `CONTACTS_ENABLE_OCM_INVITES` - Enable OCM Invites feature (default: `false`)
  - Type: Boolean
  - Values: `true`, `false`, `1`, `0`, `yes`, `no` (case-insensitive)
  - Description: Automatically enables OCM Invites feature after contacts app is enabled
  - Example: `CONTACTS_ENABLE_OCM_INVITES=true`
  - Note: Only available in `ocm-testing` version. Standard versions will log a warning if set.

- `CONTACTS_MESH_PROVIDERS_SERVICE` - OCM Discovery Service URL (optional)
  - Type: String (URL)
  - Default: Unset
  - Description: URL to OCM Discovery Service for mesh providers configuration
  - Example: `CONTACTS_MESH_PROVIDERS_SERVICE=https://surfdrive.surf.nl/index.php/s/d0bE1k3P1WHReTq/download`
  - Note: Requires `CONTACTS_ENABLE_OCM_INVITES=true` to be useful. Will log a warning if command is not available.

### Nextcloud Base Variables

This service inherits all environment variables from `nextcloud-base`. See [nextcloud-base documentation](../nextcloud-base/docs/README.md#environment-variables) for:

- Installation variables (`NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD`, etc.)
- Database configuration (`MYSQL_*`, `POSTGRES_*`, `SQLITE_*`)
- Redis configuration (`REDIS_*`)
- Apache configuration (`APACHE_*`)

## Versions

### Standard Version

- **Default**: `v8.1.0-nc-v32.0.2`
- **Source**: `https://github.com/nextcloud/contacts`
- **Ref**: `v8.1.0`
- **Features**: Standard Contacts app, no OCM Invites

### OCM Testing Version

- **Name**: `ocm-testing`
- **Source**: `https://github.com/sara-nl/nextcloud-contacts`
- **Ref**: `invite-for-cloudid-exchange`
- **Features**: Contacts app with OCM Invites feature
- **Usage**: Set `CONTACTS_ENABLE_OCM_INVITES=true` to enable OCM functionality

## OCM Invites Feature

The OCM Invites feature allows exchanging cloud IDs through OCM invitation workflow:

- Button to invite remote users to exchange cloudIDs
- **Email is optional** - invites can be shared manually via link
- Button to manually accept invite to exchange cloudIDs
- WAYF page allowing the receiver of the invite to open and accept the invitation
- Listing of open invitations
- Option to resend (only for invites with email), revoke open invitations

### Enabling OCM Invites

1. Use `ocm-testing` version: `nextcloud-contacts:ocm-testing`
2. Set environment variable: `CONTACTS_ENABLE_OCM_INVITES=true`
3. Optionally configure mesh providers service: `CONTACTS_MESH_PROVIDERS_SERVICE=<URL>`

The feature is automatically enabled during container initialization if the environment variable is set.

### Manual Enablement

If you prefer manual control, you can enable it after container startup:

```bash
docker exec <container> php /var/www/html/occ contacts:enable-ocm-invites
docker exec <container> php /var/www/html/occ contacts:set-mesh-providers-service <URL>
```

## Architecture

### Build Process

The Contacts app is built in multiple stages:

1. **Source Prepare** - Clone/copy contacts source code
2. **UI Build** - Build frontend with npm (Node.js)
3. **Composer Deps** - Generate PHP autoloader (vendor/autoload.php)
4. **App Assemble** - Combine artifacts, remove dev files
5. **Runtime** - Copy to `/usr/src/apps/contacts` for runtime merge

### Runtime Integration

- App is baked to `/usr/src/apps/contacts` in the image
- At runtime, merged into `/usr/src/nextcloud/apps/contacts` by `nextcloud-base`
- Automatically enabled via hook: `90-enable-contacts.nu`
- OCM Invites configured via hook: `91-enable-contacts-ocm-invites.nu` (if enabled)

### Hook Execution Order

Hooks execute alphabetically:

1. `90-enable-contacts.nu` - Enables contacts app
2. `91-enable-contacts-ocm-invites.nu` - Enables OCM Invites (if `CONTACTS_ENABLE_OCM_INVITES=true`)

## Building

```bash
# Build default version
nu scripts/dockypody.nu build --service nextcloud-contacts

# Build specific version
nu scripts/dockypody.nu build --service nextcloud-contacts --version ocm-testing

# Build with local source
CONTACTS_MODE=local CONTACTS_PATH=/path/to/contacts nu scripts/dockypody.nu build --service nextcloud-contacts
```

## Troubleshooting

### OCM Invites Not Enabled

**Symptom**: `CONTACTS_ENABLE_OCM_INVITES=true` but feature not enabled

**Causes**:

- Using standard version (OCM commands not available)
- Hook execution failed (check logs)

**Solution**:

- Use `ocm-testing` version
- Check container logs for warnings
- Manually enable: `occ contacts:enable-ocm-invites`

### Mesh Providers Service Not Configured

**Symptom**: `CONTACTS_MESH_PROVIDERS_SERVICE` set but not configured

**Causes**:

- Using standard version (command not available)
- Invalid URL format
- Hook execution failed

**Solution**:

- Use `ocm-testing` version
- Verify URL starts with `http://` or `https://`
- Check container logs for warnings
- Manually configure: `occ contacts:set-mesh-providers-service <URL>`

### Contacts App Not Enabled

**Symptom**: Contacts app not available in Nextcloud

**Causes**:

- App directory missing
- Hook execution failed

**Solution**:

- Check `/var/www/html/apps/contacts` exists
- Check container logs for errors
- Manually enable: `occ app:enable contacts`

## See Also

- [nextcloud-base documentation](../nextcloud-base/docs/README.md) - Base service documentation
- [nextcloud-base initialization](../nextcloud-base/docs/initialization.md) - Initialization flow
- [Dockerfile Development Guide](../../docs/guides/dockerfile-development.md) - Dockerfile patterns
