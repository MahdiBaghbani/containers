# Configuration System

This document describes the configuration system, placeholder processing, and configuration file structure for Reva services.

## Configuration Files

Configuration files are TOML format. Development images (`Dockerfile.development`)
hold resolved templates in `/configs/revad` (image) and process them to
`/etc/revad` (runtime). Production images (`Dockerfile.production`) create
the empty `/etc/revad` directory layout in the image but do not copy resolved
configs into it; runtime configs come from host volume mounts or from volumes
pre-populated by development containers.

### Configuration File Names

Configuration files use generic names (no platform prefix):

- `gateway.toml` - Gateway configuration
- `dataprovider-{type}.toml` - Dataprovider configuration (localhome, ocm, sciencemesh)
- `authprovider-{type}.toml` - Authprovider configuration (oidc, machine, ocmshares, publicshares)
- `shareproviders.toml` - Share providers configuration
- `groupuserproviders.toml` - User/group providers configuration

### Configuration Structure

Configuration files contain:

- **Service Definitions**: `[grpc.services.service_name]` sections
- **Template Variables**: `{{ grpc.services.service_name.address }}` for same-container services
- **Placeholders**: `{{placeholder:name:default-value}}` for external services and configuration
- **Environment Variables**: Values injected via placeholder processing

## Placeholder System

The configuration system uses placeholders for dynamic value injection at runtime.

### Placeholder Syntax

```text
{{placeholder:name:default-value}}
```

- **name**: Placeholder identifier (can include dots for nested values, e.g., `storageprovider.localhome`)
- **default-value**: Optional default value if not provided via environment variable

### Placeholder Types

#### Template Variables

Used for same-container services (Reva template system):

```text
{{ grpc.services.service_name.address }}
```

Examples:

- `{{ grpc.services.authregistry.address }}`
- `{{ grpc.services.appregistry.address }}`
- `{{ grpc.services.storageregistry.address }}`

These are processed by Reva's template system, not by initialization scripts.

#### Custom Placeholders

Used for external services and configuration:

```text
{{placeholder:shareproviders.address}}
{{placeholder:groupuserproviders.address}}
{{placeholder:log-level:debug}}
{{placeholder:jwt-secret:reva-secret}}
{{placeholder:storageprovider.localhome}}
```

### Placeholder Processing

Placeholders are processed by Nushell scripts during container initialization:

1. **Read Environment Variables**: Scripts read environment variables
2. **Build Placeholder Map**: Create map of placeholder names to values
3. **Process Templates**: Replace placeholders with actual values
4. **Save Configuration**: Write processed config to `/etc/revad`

See [Initialization](initialization.md) for details on the processing flow.

## Environment Variables

### Required Variables

- `DOMAIN` - Domain name (required)
- `REVAD_CONTAINER_MODE` - Container mode (required)

### Common Variables

All containers use these common environment variables:

```bash
# Domain configuration
DOMAIN=example.com

# Logging
REVAD_LOG_LEVEL=debug
REVAD_LOG_OUTPUT=/var/log/revad.log

# Security
REVAD_JWT_SECRET=reva-secret

# TLS
REVAD_TLS_ENABLED=false

# Configuration directory
REVAD_CONFIG_DIR=/etc/revad
```

### Service-Specific Variables

Each service type has specific environment variables. See platform-specific documentation (e.g., CERNBox) for complete variable lists.

#### Gateway Service Variables

Gateway containers support additional environment variables for ScienceMesh configuration:

```bash
# Mesh Directory URL (for mesh_directory_url field)
# Option 1: Explicit URL
MESHDIR_URL=https://meshdir.docker/meshdir

# Option 2: Construct from domain
MESHDIR_DOMAIN=meshdir.docker
# Results in: https://meshdir.docker/meshdir

# Directory Service URLs (for directory_service_urls field)
# Space-separated list of directory service URLs for ScienceMesh WAYF handler
# Independent of MESHDIR_URL/MESHDIR_DOMAIN (mesh_directory_url field)
# Invalid URLs are automatically removed with warnings
OCM_DIRECTORY_SERVICE_URLS="https://surfdrive.surf.nl/index.php/s/d0bE1k3P1WHReTq/download https://another.example.com/dir"

# Dev-only: skip TLS verification for ScienceMesh WAYF discovery client
# Affects both directory service fetch and OCM provider discovery
# OCM_CLIENT_INSECURE (specific) overrides OC_INSECURE (general). Parity with OpenCloud.
# Strict parsing: only "true" (case-insensitive) enables; everything else is false
# Do not set this in production environments
OCM_CLIENT_INSECURE=false
# OC_INSECURE=true   # General fallback; OCM_CLIENT_INSECURE overrides when both set
```

**Note**: `directory_service_urls` and `mesh_directory_url` are independent fields. Both can be set simultaneously. The `directory_service_urls` field supports multiple space-separated URLs, while `mesh_directory_url` is a single URL.

## Configuration Directory Structure

### Source Layout (Build Time)

Maintainer config sources live under the service tree, not directly in the
image path:

```text
services/revad-base/
├── configs/                    # Core templates (all bands)
│   ├── gateway.toml
│   ├── shareproviders.toml
│   └── ...
└── configs-overlays/
    └── master/                 # Band-specific whole-file overlays
        ├── gateway.toml
        └── shareproviders.toml
```

During the development image build, `resolve_configs` copies core top-level
files into `/configs/revad`, then replaces same-named files from
`configs-overlays/<band>` when that band directory exists. Build-time
partials merge afterward (see below).

### Image Structure

Development images only (`Dockerfile.development`). Production images
(`Dockerfile.production`) ship an empty `/etc/revad` tree only; populated
configs arrive at runtime via volume mounts (see Runtime Structure).

```text
/configs/revad/          # Resolved templates (development image)
├── gateway.toml
├── dataprovider-localhome.toml
├── dataprovider-ocm.toml
├── dataprovider-sciencemesh.toml
├── authprovider-oidc.toml
├── authprovider-machine.toml
├── authprovider-ocmshares.toml
├── authprovider-publicshares.toml
├── shareproviders.toml
├── groupuserproviders.toml
├── users.demo.json
├── groups.demo.json
└── providers.testnet.json
```

### Runtime Structure

```text
/etc/revad/              # Processed configs (volume)
├── gateway.toml         # Processed (placeholders replaced)
├── dataprovider-*.toml # Processed
├── authprovider-*.toml # Processed
├── shareproviders.toml  # Processed
├── groupuserproviders.toml # Processed
├── users.demo.json     # Copied from image
├── groups.demo.json    # Copied from image
└── providers.testnet.json # Copied from image
```

## Volume Mounts

### Configuration Volumes

Each service has its own configuration volume:

```yaml
volumes:
  - "${PWD}/volumes/config/reva-gateway:/etc/revad"
  - "${PWD}/volumes/config/reva-shareproviders:/etc/revad"
  # ... etc
```

Development containers write processed configs to these volumes. Production containers read from them.

### Data Volumes

Shared data volumes:

```yaml
volumes:
  - "${PWD}/volumes/data/reva/jsons:/var/tmp/reva"
```

## Config Band Resolver

Version and structural differences between Reva release lines are handled
during the development image build by the config band resolver, not by
partials.

### Model

During the development image build, `resolve_configs` (see
`services/revad-base/scripts/lib/resolve-configs.nu`) implements:

1. Copy every top-level file from `configs/` (core) into the destination.
2. If `configs-overlays/<band>` exists, copy same-named overlay files over
   the core copies (whole-file replacement, not field merge).
3. **Empty band string** (`""`): error `Config overlay band must not be
   empty`.
4. **Core-only band** (listed in `CORE_ONLY_BANDS`, currently `v3.10.1`)
   with no overlay directory: allowed; core files only.
5. **Any other band** with no overlay directory: error
   `Unknown or missing config overlay band: <band> ...`.

The development image build arg `REVA_CONFIG_BAND` selects the band.
`versions.nuon` sets it per published `revad-base` version (`master` or
`v3.10.1`). Production image builds do not invoke `resolve_configs`.

### Example: master vs v3.10.1

Core `shareproviders.toml` uses `webapp_template`. The `master` overlay
replaces that file with `webapp_endpoint` instead. The `v3.10.1` band has no
overlay directory, so it keeps `webapp_template` from core.

Core `gateway.toml` already sets `enable_webapp = true` and
`enable_code_flow` via a placeholder defaulting to `false`. The `master`
overlay replaces that file with `enable_code_flow = true`; `enable_webapp`
stays `true` in both bands.

Use `configs/` plus `configs-overlays/<band>/` for structural drift between
Reva versions. Do not encode version-band differences as partials.

## Partial Configuration System

Partials are an append-only layering mechanism for adding sections to an
already-resolved config. They are not the path for version or band structural
differences; those go through the band resolver above.

### Overview

Partial configs are TOML files that contain:

- A `[target]` section defining which config file to merge into
- Configuration content that is appended to the target file

### Build-Time vs Runtime

**Build-Time Partials**:

- Location: `services/{name}/configs/partial/*.toml`
- Merged during Dockerfile build, after band resolution
- Baked into development image at `/configs/revad/` (`Dockerfile.development`
  only; production images use `/etc/revad`)
- No markers (content directly merged)
- Use case: Service-specific append-only extensions (for example CERNBox
  extras on top of resolved `revad-base` configs)

**Runtime Partials**:

- Location: `/etc/revad/partial/*.toml` (volume) or `/configs/partial/*.toml` (image)
- Merged during container initialization
- Wrapped with comment markers for restart prevention
- Use case: End user adds custom services without rebuilding images

### Partial File Format

```toml
[target]
file = "gateway.toml"  # Target config file name
order = 10             # Optional: merge order (explicit numbers first, then alphabetical)

# Content below [target] is merged into target file
[http.services.thumbnails]
cache = "lru"
output_type = "jpg"
quality = 80
```

### Merge Process

Partials are merged **after** config copy but **before** placeholder processing:

1. Copy config from image to volume (if not exists)
2. **Merge partials** into existing config
3. Process placeholders
4. Apply TLS/other settings

This allows placeholders in partials to work correctly.

### Ordering

- Partials with explicit `order` numbers are sorted numerically
- Unnumbered partials are sorted alphabetically
- Auto-assigned order starts after highest explicit number
- Ordering is per-target (each target file has its own sequence)

### Marker System (Runtime Only)

Runtime partials are wrapped with comment markers to prevent duplicate appends on container restart:

```toml
# === Merged from: thumbnails.toml (order: 1) ===
# This section was automatically merged from a partial config file.
# DO NOT EDIT MANUALLY - changes will be lost on container restart.

[http.services.thumbnails]
cache = "lru"
# ... content ...

# === End of merge from: thumbnails.toml ===
```

On restart, old marked sections are removed before fresh partials are re-merged.

### Example

**Partial file** (`services/cernbox-revad/configs/partial/thumbnails.toml`):

```toml
[target]
file = "gateway.toml"
order = 1

[http.services.thumbnails]
cache = "lru"
output_type = "jpg"
quality = 80
```

**Result**: Content is merged into `gateway.toml` at order 1, before placeholder processing.

### Documentation

For complete documentation on partial configs:

- **Schema Reference**: See [`partial-config-schema.md`](partial-config-schema.md) for complete schema and examples
- **Schema File**: See [`services/revad-base/schemas/partial-config.nuon`](../schemas/partial-config.nuon) for authoritative schema definition

## Related Documentation

- [Architecture](architecture.md) - Build tuple and config bands
- [Initialization](initialization.md) - Initialization process and config processing
- [Development Workflow](development-workflow.md) - Development -> production workflow
- [Container Modes](container-modes.md) - Container mode system
