# Nextcloud Entrypoint System

Architecture and implementation details of the Nushell-based entrypoint system.

## Overview

The entrypoint system provides container lifecycle management through a modular Nushell architecture:

- **Bash Wrapper** (`entrypoint.sh`) - Calls Nushell, execs CMD
- **Nushell Orchestrator** (`entrypoint-init.nu`) - Main initialization flow
- **Modular Libraries** (`lib/*.nu`) - Specialized functions by domain

## Architecture

### Component Structure

```text
services/nextcloud-base/scripts/
├── entrypoint.sh                    # Bash wrapper (entry point)
├── entrypoint-init.nu              # Nushell orchestrator
└── lib/
    ├── utils.nu                    # Core utilities
    ├── apache-config.nu            # Apache configuration
    ├── redis-config.nu             # Redis session handler
    ├── source-prep.nu              # Source preparation & CI mounts
    ├── nextcloud-init.nu           # Install/upgrade logic
    ├── hooks.nu                    # Hook execution
    └── post-install.nu             # OCM custom logic
```

### Design Principles

1. **Separation of Concerns** - Each module handles one domain
2. **Selective Imports** - Import only what's needed (no wildcards)
3. **Fail-Fast** - Critical errors exit immediately
4. **Idempotent** - Can be run multiple times safely
5. **Observable** - Log all major operations

## Module Reference

### utils.nu

**Core utility functions used across all modules.**

```nu
# Detect user/group for container execution
export def detect_user_group []
  -> {user: string, group: string, uid: int, gid: int}

# Execute command as specified user
export def run_as [user: string, command: string]

# Check if directory is empty
export def directory_empty [dir: string] -> bool

# Get environment variable with Docker secrets support
export def file_env [var_name: string, default: string = ""]
  -> string

# Safe environment variable access
export def get_env_or_default [var_name: string, default: string = ""]
  -> string
```

**Key Features:**

- **User Detection**: Handles www-data for root, current user for non-root
- **Apache Syntax**: Strips `#` prefix from user/group names
- **Docker Secrets**: Supports `${VAR}_FILE` pattern
- **Safe Access**: Try-catch for missing environment variables

### apache-config.nu

**Apache web server configuration.**

```nu
# Configure Apache based on environment variables
export def configure_apache [cmd_args: list<string>]
```

**Operations:**

- Checks if command starts with "apache"
- Disables remoteip module if `APACHE_DISABLE_REWRITE_IP` set

**Use Case:**

When running behind a reverse proxy that sets X-Forwarded-For headers, you may want to disable remoteip.

### redis-config.nu

**Redis session handler configuration for PHP.**

```nu
# Configure Redis as PHP session handler
export def configure_redis []
```

**Supported Configurations:**

- **Unix Socket**: `REDIS_HOST=/var/run/redis.sock`
- **TCP**: `REDIS_HOST=redis-server` (port: 6379 or `REDIS_HOST_PORT`)
- **Authentication**: `REDIS_HOST_PASSWORD`, `REDIS_HOST_USER`

**Generated Config:**

```ini
session.save_handler = redis
session.save_path = "tcp://redis:6379?auth=password"
redis.session.locking_enabled = 1
redis.session.lock_retries = -1
redis.session.lock_wait_time = 10000
```

Written to: `/usr/local/etc/php/conf.d/redis-session.ini`

### source-prep.nu

**Source preparation and CI volume mount handling.**

```nu
# Detect if source mount needs copying
export def detect_source_mount [] -> bool

# Copy source with rsync
export def copy_source_to_html [user: string, group: string]

# Prepare directories after copy
export def prepare_directories []

# Orchestrate all source prep
export def prepare_source [user: string, group: string]
```

**CI Volume Mount Pattern:**

1. **Build Time**: Nextcloud source at `/usr/src/nextcloud/`
2. **Runtime**: Need source at `/var/www/html/`
3. **Solution**: Detect and copy-on-write

**Enhanced Error Handling:**

- Pre-validation (source exists, readable, not empty)
- rsync exit code checking
- Post-validation (target not empty)
- Clear error messages

### nextcloud-init.nu

**Nextcloud installation and upgrade logic.**

```nu
# Compare semantic versions
export def version_greater [v1: string, v2: string] -> bool

# Get installed version from /var/www/html/version.php
export def get_installed_version [] -> string

# Get image version from /usr/src/nextcloud/version.php
export def get_image_version [] -> string

# Sync source files with upgrade exclusions
export def sync_source [user: string, group: string]

# Install Nextcloud with database config
export def install_nextcloud [user: string]

# Upgrade Nextcloud to new version
export def upgrade_nextcloud [user: string]
```

**Key Features:**

- **Automatic Database Detection**: SQLite, MySQL, PostgreSQL
- **Retry Logic**: Up to 10 attempts for install
- **Trusted Domains**: Auto-configure from environment
- **App Comparison**: Track disabled apps during upgrade

### hooks.nu

**Hook execution system.**

```nu
# Execute scripts in /docker-entrypoint-hooks.d/{hook_name}/
export def run_path [hook_name: string, user: string]
```

**Hook Discovery:**

1. Check `/docker-entrypoint-hooks.d/{hook_name}/` exists
2. Find all `*.sh` files
3. Verify executable flag
4. Sort alphabetically
5. Execute via `run_as`

**Error Handling:**

- Missing executable flag: Skip with warning
- Hook failure (exit != 0): Fail entire initialization

### post-install.nu

**OCM-specific custom logic.**

```nu
# Run custom post-installation operations
export def run_custom_post_install [user: string]

# Setup log files with permissions
def setup_log_files []
```

**Operations:**

1. Add database indices
2. Maintenance repair (expensive)
3. Set maintenance window
4. Config modifications
5. Disable firstrunwizard
6. Log file setup

## Hook System Usage

### Hook Types and Timing

```text
Installation Flow:
  pre-installation
  ├─> occ maintenance:install
  ├─> Custom post-install (OCM)
  └─> post-installation

Upgrade Flow:
  pre-upgrade
  ├─> occ upgrade
  └─> post-upgrade

Final:
  before-starting (both flows)
```

### Creating Hooks

**Directory Structure:**

```text
/docker-entrypoint-hooks.d/
├── pre-installation/
│   └── 01-prepare.sh
├── post-installation/
│   ├── 01-install-app.sh
│   └── 02-configure.sh
├── pre-upgrade/
│   └── 01-backup.sh
├── post-upgrade/
│   └── 01-verify.sh
└── before-starting/
    └── 01-finalize.sh
```

**Hook Script Template:**

```bash
#!/bin/sh
set -eu

# This hook runs as www-data user if container is root
# Use occ commands directly:
php /var/www/html/occ app:enable myapp

# Or any other initialization:
echo "Custom initialization completed"
```

**Permissions:**

```bash
chmod +x /docker-entrypoint-hooks.d/*/hook.sh
```

### Mounting Hooks

**Docker Run:**

```bash
docker run -d \
  -v ./hooks/post-installation:/docker-entrypoint-hooks.d/post-installation:ro \
  nextcloud:v30.0.11-debian
```

**Docker Compose:**

```yaml
services:
  nextcloud:
    image: nextcloud:v30.0.11-debian
    volumes:
      - ./hooks/post-installation:/docker-entrypoint-hooks.d/post-installation:ro
```

**Kubernetes:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nextcloud-hooks
data:
  01-install-app.sh: |
    #!/bin/sh
    php /var/www/html/occ app:enable myapp
---
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: nextcloud
      image: nextcloud:v30.0.11-debian
      volumeMounts:
        - name: hooks
          mountPath: /docker-entrypoint-hooks.d/post-installation
          readOnly: true
  volumes:
    - name: hooks
      configMap:
        name: nextcloud-hooks
        defaultMode: 0755
```

### Hook Examples

**Install Custom App:**

```bash
#!/bin/sh
# post-installation/01-install-contacts.sh
set -eu

# Enable contacts app (if available)
if php /var/www/html/occ app:list | grep -q contacts; then
  php /var/www/html/occ app:enable contacts
  echo "Contacts app enabled"
fi
```

**Configure App Settings:**

```bash
#!/bin/sh
# post-installation/02-configure-settings.sh
set -eu

# Set app config
php /var/www/html/occ config:app:set myapp setting --value=value

# Set system config
php /var/www/html/occ config:system:set mykey --value=myvalue
```

**Backup Before Upgrade:**

```bash
#!/bin/sh
# pre-upgrade/01-backup.sh
set -eu

# Backup database
php /var/www/html/occ maintenance:mode --on
mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE > /backup/nextcloud-pre-upgrade.sql
php /var/www/html/occ maintenance:mode --off

echo "Backup completed"
```

## CI Volume Mount Pattern

### Problem

Nextcloud source code is baked into the image at `/usr/src/nextcloud/`, but Apache serves from `/var/www/html/`. In production, this is handled by the official Nextcloud entrypoint. In CI/development, we need a copy-on-write pattern.

### Solution

```nu
# 1. Detect source mount
if (detect_source_mount) {
  # 2. Copy source
  copy_source_to_html $user $group
}

# 3. Always prepare directories
prepare_directories
```

### Detection Logic

**Conditions for Copy:**

1. `/usr/src/nextcloud` exists and is readable
2. Required files present: `version.php`, `index.php`, `occ`
3. `/var/www/html` is empty OR missing Nextcloud files

**Skip Copy if:**

- Source missing or empty
- Target already has Nextcloud files

### Copy Mechanics

**Root User:**

```bash
rsync -rlDog --chown www-data:www-data /usr/src/nextcloud/ /var/www/html/
```

**Non-Root User:**

```bash
rsync -rlD /usr/src/nextcloud/ /var/www/html/
```

**Validation:**

- Pre-copy: Verify source valid
- Post-copy: Verify target not empty
- Fail fast on errors

### Multi-Container Scenarios

**Problem**: Multiple containers starting simultaneously may race to copy source.

**Current Behavior**: No file locking (Nushell limitation)

**Mitigation**:

- Copy-on-write is idempotent
- Rsync handles concurrent writes safely
- Acceptable for most deployments

**Future Enhancement**: Add external `flock` if needed

### Development Workflow

**Local Development:**

```bash
# Mount source as volume
docker run -d \
  -v ./nextcloud-source:/usr/src/nextcloud:ro \
  -v nextcloud-data:/var/www/html \
  nextcloud:v30.0.11-debian
```

Entrypoint detects mount and copies on first start.

**Subsequent Starts:**

Source already in `/var/www/html/`, no copy needed.

## Custom Logic Integration

### OCM-Specific Operations

Custom post-installation logic runs **after** Nextcloud installation but **before** user hooks:

```text
Flow:
  pre-installation hook
  ├─> occ maintenance:install
  ├─> Custom post-install (OCM) <-- HERE
  └─> post-installation hook
```

### Why After Install?

1. Nextcloud must be installed before running occ commands
2. Database must exist for index operations
3. Config file must exist for modifications

### Why Before User Hooks?

1. System-level setup (indices, repair) comes first
2. User hooks can depend on OCM operations
3. Consistent state for user customization

### Customization Points

**For Custom Logic:**

- Modify `lib/post-install.nu`
- Add/remove operations as needed
- Maintain fail-fast error handling

**For User Logic:**

- Use `post-installation` hooks
- Mount scripts as volumes
- Keep hooks focused and tested

## Error Handling

### Fail-Fast Philosophy

All critical operations fail immediately:

```nu
# Example: Source copy validation
if not ($source_dir | path exists) {
  print $"Error: Source directory does not exist: ($source_dir)"
  exit 1
}
```

### Exit Codes

- **0**: Success
- **1**: Failure (all errors)

No custom exit codes - simple pass/fail.

### Error Messages

**Format:**

```text
Error: <What went wrong>
<Additional context>
```

**Examples:**

```text
Error: rsync failed with exit code 23
/usr/src/nextcloud: Permission denied

Error: Can't start Nextcloud because the version of the data (30.0.11) is higher than the docker image version (29.0.10) and downgrading is not supported.
Are you sure you have pulled the newest image version?
```

### Recovery

**General Strategy:**

1. Read error message
2. Fix underlying issue
3. Restart container

**No State Persistence:**

Entrypoint is stateless - safe to restart anytime.

## Performance Considerations

### Source Copy Performance

**Rsync is Fast:**

- Uses incremental algorithm
- Only copies changed files
- Hardlinks when possible

**Typical Times:**

- First copy (full): 2-5 seconds
- Subsequent copies (updates): <1 second

### Hook Execution

**Sequential, Not Parallel:**

Hooks run one at a time in alphabetical order.

**Performance Tips:**

- Keep hooks fast (<5s each)
- Use async operations if needed
- Parallelize in hook scripts, not system

### Initialization Overhead

**Typical Timings:**

- User detection: <100ms
- Redis config: <100ms
- Source copy (if needed): 2-5s
- Version detection: <500ms
- Installation (DB-dependent): 10-60s
- Upgrade (version-dependent): 5-120s

**Total**: 15-180s depending on scenario

## Troubleshooting

### Entrypoint Debugging

**Enable Verbose Logging:**

Add debug prints to modules:

```nu
print $"DEBUG: user=($user), uid=($uid)"
```

**Check Logs:**

```bash
docker logs <container-id>
```

### Common Issues

#### "Module not found"

- Check file permissions (scripts must be readable)
- Check COPY commands in Dockerfile
- Verify module paths in imports

#### "Command not found: nu"

- Nushell not in PATH
- Check common-tools dependency
- Verify Nushell binary location

#### "Permission denied"

- Check script executable flags
- Check directory permissions
- Verify user/group settings

## Migration from Bash

### Differences from Official Entrypoint

**What's the Same:**

- Hook system (compatible)
- Version detection logic
- Install/upgrade flow
- Environment variables

**What's Different:**

- Implementation language (Nushell vs Bash)
- Modular architecture (vs monolithic script)
- Enhanced error handling
- OCM-specific customization

**Compatibility:**

Hooks written for official Nextcloud image work without modification.

## See Also

- [README.md](./README.md) - Service overview
- [initialization.md](./initialization.md) - Initialization flow
- [../../docs/guides/nushell-development.md](../../docs/guides/nushell-development.md) - Nushell development
- [../../docs/concepts/build-system.md](../../docs/concepts/build-system.md) - Build system
