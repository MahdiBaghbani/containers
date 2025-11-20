# Reva Base Service Documentation

This directory contains generic Reva service documentation that applies to all platforms using the revad-base image.

## Documentation Structure

- **[Architecture](architecture.md)** - Reva service architecture and multi-container patterns
- **[Services](services.md)** - Generic Reva service descriptions (gateway, dataprovider, authprovider, etc.)
- **[Configuration](configuration.md)** - Configuration system, placeholder processing, and config structure
- **[Container Modes](container-modes.md)** - Container mode system (`REVAD_CONTAINER_MODE`)
- **[Initialization](initialization.md)** - Initialization scripts and runtime configuration processing
- **[Development Workflow](development-workflow.md)** - Development → production workflow and volume strategy

## Platform-Specific Documentation

Platform-specific deployment documentation (e.g., CERNBox) is located in the platform service directories:

- CERNBox: `services/cernbox-revad/docs/`

## Overview

The `revad-base` service provides:

- **Reva Binary**: Compiled Reva daemon (`revad`)
- **Configuration Templates**: Generic Reva configuration files
- **Initialization Scripts**: Nushell scripts for runtime configuration processing
- **Container Modes**: Support for multiple container modes via `REVAD_CONTAINER_MODE`

## Key Concepts

### Container Modes

Each container runs in a specific mode determined by the `REVAD_CONTAINER_MODE` environment variable. Modes include:

- `gateway` - Gateway services
- `dataprovider-{type}` - Storage providers (localhome, ocm, sciencemesh)
- `authprovider-{type}` - Authentication providers (oidc, machine, ocmshares, publicshares)
- `shareproviders` - Share management services
- `groupuserproviders` - User and group management services

See [Container Modes](container-modes.md) for details.

### Configuration Processing

Development images process configuration templates at runtime:

1. Copy templates from `/configs/revad` (image) to `/etc/revad` (volume)
2. Process placeholders using environment variables
3. Write processed configs to volume
4. Start Reva daemon with processed config

Production images read pre-processed configs from volumes (no processing).

See [Initialization](initialization.md) and [Development Workflow](development-workflow.md) for details.

### Placeholder System

Configuration files use placeholders for dynamic value injection:

- Template variables: `{{ grpc.services.service_name.address }}`
- Custom placeholders: `{{placeholder:name:default-value}}`

See [Configuration](configuration.md) for details.

## Related Documentation

- [Build System](../../../docs/concepts/build-system.md) - Build system architecture
- [Service Configuration](../../../docs/concepts/service-configuration.md) - Service configuration schema
- [Nushell Development Guide](../../../docs/guides/nushell-development.md) - Nushell scripting guide
