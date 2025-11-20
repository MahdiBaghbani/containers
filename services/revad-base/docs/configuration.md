# Configuration System

This document describes the configuration system, placeholder processing, and configuration file structure for Reva services.

## Configuration Files

Configuration files are TOML format and located in `/configs/revad` (image) and `/etc/revad` (runtime).

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

## Configuration Directory Structure

### Image Structure

```text
/configs/revad/          # Source templates (image)
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

## Related Documentation

- [Initialization](initialization.md) - Initialization process and config processing
- [Development Workflow](development-workflow.md) - Development → production workflow
- [Container Modes](container-modes.md) - Container mode system
