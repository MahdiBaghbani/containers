# Nextcloud Contacts Service

Nextcloud service with Contacts app pre-installed and OCM Invites feature
support.

## Overview

`nextcloud-contacts` extends `nextcloud-base` with:

- **Contacts app** - Pre-baked and automatically enabled
- **OCM Invites support** - Open Cloud Mesh invitation workflow, configured
  from environment variables
- **UI build integration** - Automated npm build process for contacts app
  frontend
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
  -e CONTACTS_OCM_INVITES_MODE=advanced \
  -e CONTACTS_MESH_PROVIDERS_SERVICE=https://example.com/providers.json \
  nextcloud-contacts:latest
```

## Environment Variables

All OCM settings are written to the Contacts app config during container
initialization using `occ config:app:set contacts <key> ...`.

### Contacts App Configuration

- `CONTACTS_ENABLE_OCM_INVITES` - Enable OCM Invites feature (default: `false`)
  - Type: Boolean
  - Values: `true`, `false`, `1`, `0`, `yes`, `no` (case-insensitive)
  - Maps to app config: `contacts ocm_invites_enabled`
  - Example: `CONTACTS_ENABLE_OCM_INVITES=true`

- `CONTACTS_MESH_PROVIDERS_SERVICE` - OCM discovery service URL (optional)
  - Type: String (URL)
  - Default: Unset
  - Maps to app config: `contacts mesh_providers_service`
  - Example:
    `CONTACTS_MESH_PROVIDERS_SERVICE=https://example.com/providers.json`

### OCM Invites Mode and Flags

These variables control the OCM invites user experience. Use a mode preset or
override individual flags.

- `CONTACTS_OCM_INVITES_MODE` - UX mode preset (optional)
  - Type: String
  - Values: `basic`, `advanced`
  - Default: Unset (uses basic defaults)
  - `basic`: email is required, encoded copy button hidden
  - `advanced`: email is optional, encoded copy button shown

- `CONTACTS_OCM_INVITES_OPTIONAL_MAIL` - Allow optional email (override)
  - Type: Boolean
  - Default: Derived from mode (`false` for basic, `true` for advanced)
  - Maps to app config: `contacts ocm_invites_optional_mail`
  - When true, users can create invites without sending email and share the
    invite link manually.

- `CONTACTS_OCM_INVITES_ENCODED_COPY_BUTTON` - Show encoded copy button
  (override)
  - Type: Boolean
  - Default: Derived from mode (`false` for basic, `true` for advanced)
  - Maps to app config: `contacts ocm_invites_encoded_copy_button`
  - When true, shows the button to copy the base64-encoded invite.

- `CONTACTS_OCM_INVITES_DISABLE_SSRF_GUARD` - Disable discovery SSRF guard
  (optional)
  - Type: Boolean
  - Default: Unset (guard enabled)
  - Maps to app config: `contacts ocm_invites_disable_ssrf_guard`
  - When true, OCM discovery may reach reserved/private IP addresses and
    localhost. Only needed when a peer is addressed by a literal private or
    reserved IP address (or `localhost`); hostnames such as `nextcloud2.docker`
    are not blocked and do not require this. Leave unset in production.

**Note**: Per-flag variables override mode defaults. For example,
`CONTACTS_OCM_INVITES_MODE=basic` with
`CONTACTS_OCM_INVITES_ENCODED_COPY_BUTTON=true` uses basic defaults but shows
the encoded copy button.

### Nextcloud Base Variables

This service inherits all environment variables from `nextcloud-base`. See
[nextcloud-base documentation](../../nextcloud-base/docs/README.md#environment-variables)
for:

- Installation variables (`NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD`, etc.)
- Database configuration (`MYSQL_*`, `POSTGRES_*`, `SQLITE_*`)
- Redis configuration (`REDIS_*`)
- Apache configuration (`APACHE_*`)

## Versions

### Standard Version

- **Default**: `v8.1.0-nc-master`
- **Source**: `https://github.com/nextcloud/contacts`
- **Ref**: `v8.1.0`
- **Features**: Standard Contacts app, no OCM Invites

### OCM Variant

- **Name**: `v8.1.0-ocm-nc-master`
- **Source**: `https://github.com/MahdiBaghbani/nextcloud-contacts`
- **Ref**: `mahdi/fix/ui-optional-email`
- **Features**: Contacts app with OCM Invites feature
- **Usage**: Set `CONTACTS_ENABLE_OCM_INVITES=true` to enable OCM
  functionality

A `local` variant builds the contacts app from a local checkout
(`../nextcloud-contacts`) and is what the bundled example deploys. The
`sta-ocm-m6` variant is also tracked for milestone-specific testing.

## OCM Invites Feature

The OCM Invites feature allows exchanging cloud IDs through the OCM invitation
workflow:

- Button to invite remote users to exchange cloud IDs
- Email is optional (in advanced mode) - invites can be shared manually via
  link
- Button to manually accept an invite (supports invite links, codes, and
  encoded invites)
- WAYF page allowing the receiver of the invite to open and accept the
  invitation
- Listing of open invitations
- Option to resend (only for invites with email) or revoke open invitations

### Enabling OCM Invites

1. Use an OCM-capable version, for example
   `nextcloud-contacts:v8.1.0-ocm-nc-master`
2. Set environment variable: `CONTACTS_ENABLE_OCM_INVITES=true`
3. Optionally set mode: `CONTACTS_OCM_INVITES_MODE=basic` or `advanced`
4. Optionally configure mesh providers service:
   `CONTACTS_MESH_PROVIDERS_SERVICE=<URL>`

The feature is configured automatically during container initialization from
the environment variables above.

### Basic vs Advanced Mode

**Basic mode** (default) is designed for simpler deployments:

- Email address is required when creating invites
- Encoded copy button is hidden (cleaner UI)

**Advanced mode** is for power users and testing:

- Email address is optional (invites can be shared manually)
- Encoded copy button is shown for technical users

Example with advanced mode:

```bash
docker run -d \
  -e CONTACTS_ENABLE_OCM_INVITES=true \
  -e CONTACTS_OCM_INVITES_MODE=advanced \
  -e CONTACTS_MESH_PROVIDERS_SERVICE=https://example.com/providers.json \
  nextcloud-contacts:v8.1.0-ocm-nc-master
```

### Manual Configuration

If you prefer manual control, configure the app after container startup with
core `occ` commands:

```bash
docker exec <container> php /var/www/html/occ config:app:set contacts ocm_invites_enabled --value=true --type=boolean
docker exec <container> php /var/www/html/occ config:app:set contacts mesh_providers_service --value=<URL> --type=string
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
- Presence is enforced during `before-starting` by `90-ensure-contacts.nu`
- Automatically enabled via hook: `90-enable-contacts.nu`
- OCM Invites configured via hook: `91-enable-contacts-ocm-invites.nu`

### Hook Execution Order

Hooks execute alphabetically:

1. `before-starting/90-ensure-contacts.nu` - Verifies the baked app is present
   in the runtime tree before Apache starts
2. `post-installation/90-enable-contacts.nu` - Enables contacts app after
   install
3. `post-installation/91-enable-contacts-ocm-invites.nu` - Configures OCM
   Invites from environment variables (when any OCM env var is set)

## Building

```bash
# Build default version
nu scripts/dockypody.nu build --service nextcloud-contacts

# Build specific OCM-enabled version
nu scripts/dockypody.nu build --service nextcloud-contacts --version v8.1.0-ocm-nc-master

# Build with local source
CONTACTS_MODE=local CONTACTS_PATH=/path/to/contacts nu scripts/dockypody.nu build --service nextcloud-contacts
```

## Troubleshooting

### OCM Invites Not Enabled

**Symptom**: `CONTACTS_ENABLE_OCM_INVITES=true` but the feature is not active

**Causes**:

- Hook execution failed (check container logs)
- App config not applied

**Solution**:

- Check container logs for warnings from
  `91-enable-contacts-ocm-invites.nu`
- Verify the value:
  `occ config:app:get contacts ocm_invites_enabled`
- Set it manually:
  `occ config:app:set contacts ocm_invites_enabled --value=true --type=boolean`

### Mesh Providers Service Not Configured

**Symptom**: `CONTACTS_MESH_PROVIDERS_SERVICE` set but not applied

**Causes**:

- Invalid URL format (must start with `http://` or `https://`)
- Hook execution failed

**Solution**:

- Verify the URL scheme
- Check container logs for warnings
- Set it manually:
  `occ config:app:set contacts mesh_providers_service --value=<URL> --type=string`

### Discovery Fails for a Peer Addressed by a Private IP

**Symptom**: Invite discovery to a peer addressed by a literal private/reserved
IP address (or `localhost`) returns no result

**Cause**: The discovery SSRF guard blocks reserved/private IP addresses and
localhost by default. Hostname-based peers (for example `nextcloud2.docker`) are
not affected.

**Solution**:

- Set `CONTACTS_OCM_INVITES_DISABLE_SSRF_GUARD=true` for trusted test or mesh
  environments, then rebuild or restart the container
- Or set it manually:
  `occ config:app:set contacts ocm_invites_disable_ssrf_guard --value=true --type=boolean`

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

- [nextcloud-base documentation](../../nextcloud-base/docs/README.md) - Base
  service documentation
- [nextcloud-base initialization](../../nextcloud-base/docs/initialization.md)
  - Initialization flow
- [Dockerfile Development Guide](../../../docs/guides/dockerfile-development.md)
  - Dockerfile patterns
