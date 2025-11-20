# Container Initialization

This document describes the container initialization process for `revad-base` development images.

## Overview

Development images process configuration templates at runtime, replacing placeholders with values from environment variables and writing processed configs to volumes.

## Initialization Flow

### 1. Entrypoint Execution

The container starts with `entrypoint.sh`, which calls `entrypoint-init.nu`:

```bash
ENTRYPOINT ["/usr/bin/entrypoint.sh"]
CMD ["tail", "-F", "/var/log/revad.log"]
```

### 2. Mode Validation

The entrypoint script validates `REVAD_CONTAINER_MODE`:

- Checks mode is in list of valid modes
- Raises error if invalid
- Routes to appropriate initialization script

### 3. Shared Initialization

All modes run shared initialization (`init_shared`):

- **DNS Resolution**: Writes `/etc/nsswitch.conf` (hosts: files dns)
- **Hosts File**: Adds domain entry to `/etc/hosts`
- **Log File**: Creates `/var/log/revad.log`
- **Directories**: Creates `/revad`, `/etc/revad`, `/var/tmp/reva`
- **Binaries**: Populates `/revad` with Reva binaries (if empty)
- **TLS**: Sets up TLS certificates and CA trust store (if enabled)

### 4. Mode-Specific Initialization

Each mode runs its specific initialization script:

- **Gateway**: `init-gateway.nu` - Processes gateway config, sets up service addresses
- **Dataprovider**: `init-dataprovider.nu` - Processes dataprovider config based on type
- **Authprovider**: `init-authprovider.nu` - Processes authprovider config based on type
- **Share Providers**: `init-shareproviders.nu` - Processes share providers config
- **Group/User Providers**: `init-groupuserproviders.nu` - Processes user/group providers config

### 5. Configuration Processing

Each mode-specific init script:

1. **Checks for existing config** in `/etc/revad` (volume)

   - If exists: Skips copy, processes placeholders only
   - If missing: Copies from `/configs/revad` (image) to `/etc/revad` (volume)

2. **Processes placeholders**:

   - Reads environment variables
   - Builds placeholder map
   - Replaces placeholders in config file
   - Saves processed config to `/etc/revad`

3. **Copies JSON files** (if needed):

   - Copies users, groups, providers JSON files from `/configs/revad` to `/etc/revad`

4. **TLS configuration**:
   - Disables TLS cert/key lines if TLS disabled
   - Processes TLS-related placeholders if TLS enabled

### 6. Service Startup

After initialization, the script starts the Reva daemon:

- Uses `-c` flag to load specific config file (not `--dev-dir`)
- Starts daemon in background
- Redirects output to log file
- Container continues with `tail -F` to keep running

## Configuration Copy Logic

The initialization scripts use a copy-on-write pattern:

- **Source**: `/configs/revad` (image, read-only templates)
- **Destination**: `/etc/revad` (volume, processed configs)

**Why this pattern:**

1. **Volume Mounting**: `/etc/revad` is mounted from host → container
2. **Source Preservation**: `/configs/revad` (image) stays untouched
3. **User Edits**: Users can edit files in volume, scripts won't overwrite them
4. **Placeholder Updates**: Scripts always process placeholders (updates env var changes)

**Logic:**

```nu
# Check if config exists in /etc/revad (volume)
if not ($config_path | path exists) {
    # Copy from /configs/revad (image) to /etc/revad (volume)
    ^cp $source_config $config_path
    copy_json_files $CONFIG_DIR $revad_config_dir
}

# Always process placeholders (even if config exists)
process_placeholders $config_path $placeholder_map
```

## Volume Strategy

### Development Images

- **Process configs**: Scripts copy templates → process placeholders → write to volume
- **First run**: Volume empty → scripts populate it
- **Subsequent runs**: Volume has configs → scripts use them, process placeholders
- **User edits**: Users can edit volume configs → scripts preserve edits, update placeholders

### Production Images

- **No processing**: Production images have no scripts
- **Read-only**: Production images read from volumes (pre-processed configs)
- **Requirement**: Volumes must be populated by development containers first

## Initialization Scripts

### Shared Scripts

- `lib/shared.nu` - Shared initialization functions
- `lib/utils.nu` - Utility functions (placeholder processing, env vars)

### Mode-Specific Scripts

- `init-gateway.nu` - Gateway initialization
- `init-dataprovider.nu` - Dataprovider initialization
- `init-authprovider.nu` - Authprovider initialization
- `init-shareproviders.nu` - Share providers initialization
- `init-groupuserproviders.nu` - User/group providers initialization

### Entrypoint Scripts

- `entrypoint-init.nu` - Main orchestrator (validates mode, routes to init scripts)
- `entrypoint.sh` - Shell wrapper (calls nushell entrypoint, executes CMD)

## Environment Variables

### Required Variables

- `REVAD_CONTAINER_MODE` - Container mode (required)
- `DOMAIN` - Domain name (required)

### Optional Variables

Most variables have defaults defined in initialization scripts. See [Configuration](configuration.md) for complete list.

## Related Documentation

- [Container Modes](container-modes.md) - Container mode system
- [Configuration](configuration.md) - Configuration and placeholder system
- [Development Workflow](development-workflow.md) - Development → production workflow
