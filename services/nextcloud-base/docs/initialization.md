# Nextcloud Initialization System

Complete guide to container initialization flow, source preparation, and install/upgrade logic.

## Overview

The Nextcloud initialization system handles:

1. **Source Preparation** - CI volume mount detection and copy-on-write
2. **Version Detection** - Installed vs image version comparison
3. **Installation** - Fresh Nextcloud installation with database setup
4. **Upgrade** - Version upgrades with app migration
5. **Custom Logic** - OCM-specific post-installation operations
6. **Hook Execution** - User-provided initialization scripts

## Initialization Flow

### Entry Point

Container initialization is triggered by `entrypoint.sh`:

```bash
#!/bin/sh
# Run initialization via Nushell
nu /usr/bin/entrypoint-init.nu || {
  echo "Warning: Initialization failed, continuing..."
}

# Exec the CMD (e.g., apache2-foreground)
exec "$@"
```

### Conditions

Initialization runs if:

- Command starts with "apache" (e.g., `apache2-foreground`)
- Command is "php-fpm"
- `NEXTCLOUD_UPDATE=1` environment variable set

### Complete Flow

```text
1. Apache Configuration
   └─> Disable remoteip if APACHE_DISABLE_REWRITE_IP set

2. User/Group Detection
   ├─> Root: use APACHE_RUN_USER/APACHE_RUN_GROUP (default: www-data)
   └─> Non-root: use current UID/GID

3. Redis Configuration
   └─> Generate PHP session handler config if REDIS_HOST set

4. Source Preparation
   ├─> Detect CI volume mount (/usr/src/nextcloud -> /var/www/html)
   ├─> Copy source if needed (rsync)
   └─> Prepare directories (data, custom_apps, occ executable)

5. Version Detection
   ├─> Read installed version (/var/www/html/version.php)
   ├─> Read image version (/usr/src/nextcloud/version.php)
   ├─> Validate: no downgrade
   └─> Validate: no major version jump

6. Source Sync (if version upgrade/install needed)
   ├─> Rsync with upgrade.exclude
   ├─> Sync config, data, custom_apps, themes (if empty)
   └─> Force sync version.php

7a. Fresh Installation (installed = 0.0.0.0)
   ├─> pre-installation hook
   ├─> occ maintenance:install
   ├─> Custom post-install (OCM)
   └─> post-installation hook

7b. Upgrade (installed < image)
   ├─> pre-upgrade hook
   ├─> occ upgrade
   └─> post-upgrade hook

8. Htaccess Update (if NEXTCLOUD_INIT_HTACCESS set)
   └─> occ maintenance:update:htaccess

9. Config File Diff Warnings
   └─> Compare /usr/src/nextcloud/config/*.php vs /var/www/html/config/*.php

10. Before-Starting Hook

11. Return (exec CMD in entrypoint.sh)
```

## Source Preparation

### CI Volume Mount Detection

**Problem**: Nextcloud source code is in `/usr/src/nextcloud` but needs to be in `/var/www/html` for Apache.

**Solution**: Copy-on-write pattern

```nu
# Detect if source mount needs copying
export def detect_source_mount []
```

**Detection Logic:**

1. Check `/usr/src/nextcloud` exists and is readable
2. Verify required files: `version.php`, `index.php`, `occ`
3. Check `/var/www/html` is empty or missing Nextcloud files
4. Return true if copy needed

### Source Copy

```nu
# Copy source with rsync
export def copy_source_to_html [user: string, group: string]
```

**Copy Logic:**

1. Validate source directory (exists, not empty)
2. Run rsync:
   - Root: `rsync -rlDog --chown user:group`
   - Non-root: `rsync -rlD`
3. Verify target not empty after copy
4. Exit on failure

### Directory Preparation

```nu
# Prepare directories after copy
export def prepare_directories []
```

**Operations:**

1. Create `/var/www/html/data` (if missing)
2. Create `/var/www/html/custom_apps` (if missing)
3. Make `/var/www/html/occ` executable

## Apps Mounting Strategy

Child images (e.g., `nextcloud-contacts`) can bake Nextcloud apps into the image at `/usr/src/apps/{app-name}`. These apps are merged into the Nextcloud source at runtime, surviving CI mounts to `/usr/src/nextcloud`.

### App Location

**Baked apps location:** `/usr/src/apps/{app-name}`

This location is independent of `/usr/src/nextcloud`, allowing:

- CI users to mount their own Nextcloud source at `/usr/src/nextcloud`
- Baked apps to still be available (merged in at runtime)
- Users to override specific apps by mounting to `/usr/src/apps/{app-name}`

### Merge Behavior

```nu
# Merge apps from /usr/src/apps/ into /usr/src/nextcloud/apps/
export def merge_apps [user: string, group: string]
```

**Why `apps/` instead of `custom_apps/`:** Nextcloud checks `apps/` before `custom_apps/` when looking for apps. More importantly, `occ app:enable` downloads from the app store if the app isn't found in `apps/`. By merging to `apps/`, we ensure Nextcloud finds our baked apps before trying the app store.

**Merge Logic:**

1. Check if `/usr/src/apps/` exists (return early if not)
2. Ensure `/usr/src/nextcloud/apps/` exists
3. For each app directory in `/usr/src/apps/`:
   - Skip if app already exists in target (allows user override)
   - Validate app structure (must have `appinfo/info.xml`)
   - Copy app to `/usr/src/nextcloud/apps/{app-name}`
   - Set ownership if running as root

### Override Precedence

Apps can be overridden at multiple levels:

| Priority | Location | Description |
|----------|----------|-------------|
| 1 (highest) | `/var/www/html/apps/{app}` | Direct runtime mount |
| 2 | `/usr/src/nextcloud/apps/{app}` | User's Nextcloud source includes app |
| 3 | `/usr/src/apps/{app}` | User-mounted app override |
| 4 (lowest) | `/usr/src/apps/{app}` (baked) | Image-baked app |

### CI Mount Scenarios

#### Scenario 1: Default (no mounts)

- Uses baked Nextcloud source
- Uses baked apps from `/usr/src/apps/`
- Apps merged into Nextcloud at runtime

#### Scenario 2: Mount `/usr/src/nextcloud` only

- Uses user's Nextcloud source
- Baked apps still merged into user's Nextcloud `apps/`
- User can include apps in their Nextcloud source to override baked ones

#### Scenario 3: Mount `/usr/src/apps/{app}` only

- Uses baked Nextcloud source
- User's app version used instead of baked app
- Good for testing app changes

#### Scenario 4: Mount both

- Uses user's Nextcloud source
- Uses user's app version
- Full control over all components

#### Scenario 5: Mount `/var/www/html/apps/{app}`

- Direct runtime override
- Skips merge process entirely
- Most direct but volatile (lost on container restart unless persisted)

### Hook Range Conventions

Apps should use hooks with numbers in the `51-99` range:

| Range | Purpose |
|-------|---------|
| `00-50` | Reserved for system/nextcloud-base hooks |
| `51-99` | Available for app-specific hooks |

Example: `99-enable-contacts.nu` runs after all system hooks.

## Version Management

### Version Detection

**Installed Version:**

```nu
php -r 'require "/var/www/html/version.php"; echo implode(".", $OC_Version);'
```

Returns: `30.0.11` or `0.0.0.0` (not installed)

**Image Version:**

```nu
php -r 'require "/usr/src/nextcloud/version.php"; echo implode(".", $OC_Version);'
```

Returns: `30.0.11`

### Version Validation

**Downgrade Prevention:**

```nu
if installed_version > image_version {
  error: "Downgrading is not supported"
  exit 1
}
```

**Major Version Jump Prevention:**

```nu
if image_major > (installed_major + 1) {
  error: "Can only upgrade one major version at a time"
  exit 1
}
```

Example: v29 -> v30 OK, v29 -> v31 ERROR

### Version Comparison

```nu
# Semantic version comparison
export def version_greater [v1: string, v2: string]
```

Uses natural sort to determine if v1 > v2.

## Installation

### Fresh Installation Flow

```text
1. pre-installation hook
2. occ maintenance:install
3. Custom post-install
4. post-installation hook
```

### Installation Logic

```nu
export def install_nextcloud [user: string]
```

**Steps:**

1. **Check Credentials:**

   - `NEXTCLOUD_ADMIN_USER` required
   - `NEXTCLOUD_ADMIN_PASSWORD` required
   - Exit early if missing (manual web install)

2. **Build Install Options:**

   - Admin credentials
   - Data directory (optional)
   - Database config (SQLite/MySQL/PostgreSQL)

3. **Run Installation:**

   - Retry up to 10 times (database might not be ready)
   - Sleep 10s between retries
   - Fail hard after 10 attempts

4. **Set Trusted Domains:**
   - Parse `NEXTCLOUD_TRUSTED_DOMAINS` (space-separated)
   - Set via `occ config:system:set trusted_domains N --value=DOMAIN`

### Database Support

**SQLite:**

```bash
SQLITE_DATABASE=nextcloud
```

**MySQL:**

```bash
MYSQL_HOST=db
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=secret
```

**PostgreSQL:**

```bash
POSTGRES_HOST=db
POSTGRES_DB=nextcloud
POSTGRES_USER=nextcloud
POSTGRES_PASSWORD=secret
```

**Docker Secrets:**

All password/credential variables support `${VAR}_FILE` pattern:

```bash
MYSQL_PASSWORD_FILE=/run/secrets/mysql_password
```

## Upgrade

### Upgrade Flow

```text
1. pre-upgrade hook
2. occ upgrade
3. post-upgrade hook
```

### Upgrade Logic

```nu
export def upgrade_nextcloud [user: string]
```

**Steps:**

1. **Save App List (Before):**

```bash
occ app:list | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_before
```

1. **Run Upgrade:**

```bash
occ upgrade
```

1. **Save App List (After):**

```bash
occ app:list | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_after
```

1. **Show Disabled Apps:**

```bash
diff /tmp/list_before /tmp/list_after
```

### Source Sync During Upgrade

```nu
export def sync_source [user: string, group: string]
```

**Sync Strategy:**

1. **Main Sync (with exclusions):**

   ```bash
   rsync --delete --exclude-from=/upgrade.exclude /usr/src/nextcloud/ /var/www/html/
   ```

2. **Selective Directory Sync (if empty):**

   - `config/`
   - `data/`
   - `custom_apps/`
   - `themes/`

3. **Force Sync version.php:**

```bash
rsync --include '/version.php' --exclude '/*' /usr/src/nextcloud/ /var/www/html/
```

## Custom Post-Installation Logic (OCM)

After fresh installation, OCM-specific operations run:

```nu
export def run_custom_post_install [user: string]
```

### Operations

1. **Add Missing Database Indices:**

   ```bash
   occ db:add-missing-indices
   ```

2. **Maintenance Repair:**

   ```bash
   occ maintenance:repair --include-expensive
   ```

3. **Set Maintenance Window:**

   ```bash
   occ config:system:set maintenance_window_start --type=integer --value=1
   ```

4. **Allow Local Remote Servers:**

   - Modifies `/var/www/html/config/config.php`
   - Adds: `'allow_local_remote_servers' => true,`

5. **Disable Firstrunwizard:**

   ```bash
   occ app:disable firstrunwizard
   ```

6. **Setup Log Files:**
   - Remove old logs
   - Create fresh logs:
     - `/var/log/apache2/access.log`
     - `/var/log/apache2/error.log`
     - `/var/www/html/data/nextcloud.log`
   - Set ownership: `www-data:root`
   - Set permissions: `g=u`

## Hook Execution

Hooks are discovered and executed at specific lifecycle points.

### Hook Types

- `pre-installation` - Before `occ maintenance:install`
- `post-installation` - After custom post-install
- `pre-upgrade` - Before `occ upgrade`
- `post-upgrade` - After `occ upgrade`
- `before-starting` - Before final exec (last chance to modify)

### Hook Discovery

```nu
export def run_path [hook_name: string, user: string]
```

**Discovery Logic:**

1. Check `/docker-entrypoint-hooks.d/{hook_name}/` exists
2. Find all `*.sh` files
3. Check executable flag
4. Sort alphabetically
5. Execute each script via `run_as`

### Executing Hooks

**As root:**

```bash
su -p www-data -s /bin/sh -c "/path/to/hook.sh"
```

**As non-root:**

```bash
sh -c "/path/to/hook.sh"
```

**Error Handling:**

- Hook failure stops initialization
- Exit code != 0 causes immediate exit 1

### Hook Example

```bash
#!/bin/sh
# /docker-entrypoint-hooks.d/post-installation/01-install-app.sh

# Enable a custom app
php /var/www/html/occ app:enable myapp

# Set custom config
php /var/www/html/occ config:system:set myconfig --value=myvalue
```

## Error Handling

### Fail-Fast Philosophy

All critical operations fail immediately on error:

- Source copy failure -> exit 1
- Version detection failure -> exit 1
- Downgrade attempt -> exit 1
- Major version jump -> exit 1
- Hook failure -> exit 1

### Validation

**Pre-Operation Validation:**

- Check source directory exists
- Check source directory not empty
- Check target permissions

**Post-Operation Validation:**

- Verify rsync succeeded (exit code)
- Verify target not empty after copy
- Verify version.php readable

### Logging

Each major step logs its status:

- "Running as user: www-data (33)"
- "Copying Nextcloud source..."
- "Source copy completed successfully"
- "Installed version: 30.0.11"
- "Initializing nextcloud 30.0.11 ..."

## Troubleshooting

### Source Copy Fails

**Symptom:** "Error: rsync failed with exit code N"

**Causes:**

- Source directory missing
- Source directory empty
- Permission issues

**Solution:** Check `/usr/src/nextcloud` exists and contains Nextcloud files

### Installation Hangs

**Symptom:** "Retrying install..."

**Causes:**

- Database not ready
- Database credentials wrong
- Network issues

**Solution:**

- Wait for database to be ready
- Check credentials
- Use Docker healthchecks

### Upgrade Fails

**Symptom:** "Can't start Nextcloud because..."

**Causes:**

- Downgrade attempt
- Major version jump
- Corrupted installation

**Solution:**

- Pull correct image version
- Upgrade incrementally (v29 -> v30 -> v31)
- Restore from backup

### Hooks Don't Run

**Symptom:** Hook scripts not executing

**Causes:**

- Missing executable flag
- Wrong directory
- Wrong file extension

**Solution:**

```bash
chmod +x /docker-entrypoint-hooks.d/post-installation/*.sh
```

## See Also

- [README.md](./README.md) - Service overview
- [entrypoint.md](./entrypoint.md) - Entrypoint architecture
- [../../docs/concepts/service-configuration.md](../../docs/concepts/service-configuration.md) - Service configuration
