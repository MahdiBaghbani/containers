# CERNBox Configuration Reference

CERNBox-specific configuration, environment variables, and deployment settings.

> **Generic Reva Configuration**: For information about the configuration system, placeholder processing, and configuration file structure, see [Reva Base Configuration Documentation](../../revad-base/docs/configuration.md).

## Configuration Files

Configuration files are provided by the `revad-base` image and use generic names:

- `gateway.toml` - Gateway configuration
- `dataprovider-{type}.toml` - Dataprovider configurations (localhome, ocm, sciencemesh)
- `authprovider-{type}.toml` - Authprovider configurations (oidc, machine, ocmshares, publicshares)
- `shareproviders.toml` - Share providers configuration
- `groupuserproviders.toml` - User/group providers configuration

**Location:** Configs are in `services/revad-base/configs/` and copied to `/configs/revad` in the image.

See [Reva Base Configuration](../../revad-base/docs/configuration.md) for details on configuration structure and placeholder system.

## Environment Variables

### Common Variables

All containers use these common environment variables:

```bash
# Domain configuration
DOMAIN=cernbox-1-test-revad
REVAD_DOMAIN=cernbox-1-test-revad

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

### Gateway Variables

```bash
REVAD_GATEWAY_HOST=cernbox-1-test-revad-gateway
REVAD_GATEWAY_GRPC_PORT=9142
REVAD_GATEWAY_PORT=80
REVAD_GATEWAY_PROTOCOL=http
```

### Share Providers Variables

```bash
REVAD_SHAREPROVIDERS_HOST=cernbox-1-test-revad-shareproviders
REVAD_SHAREPROVIDERS_GRPC_PORT=9144
REVAD_OCMSHARES_JSON_FILE=/var/tmp/reva/shares.json
```

### User/Group Providers Variables

```bash
REVAD_GROUPUSERPROVIDERS_HOST=cernbox-1-test-revad-groupuserproviders
REVAD_GROUPUSERPROVIDERS_GRPC_PORT=9145
```

### Auth Provider Variables

```bash
# OIDC
REVAD_AUTHPROVIDER_OIDC_HOST=cernbox-1-test-revad-authprovider-oidc
REVAD_AUTHPROVIDER_OIDC_GRPC_PORT=9158
IDP_URL=https://1.idp.cloud.test.azadehafzar.io

# Machine
REVAD_AUTHPROVIDER_MACHINE_HOST=cernbox-1-test-revad-authprovider-machine
REVAD_AUTHPROVIDER_MACHINE_GRPC_PORT=9166

# OCM Shares
REVAD_AUTHPROVIDER_OCMSHARES_HOST=cernbox-1-test-revad-authprovider-ocmshares
REVAD_AUTHPROVIDER_OCMSHARES_GRPC_PORT=9278
```

### Dataprovider Variables

```bash
# Localhome
REVAD_DATAPROVIDER_LOCALHOME_HOST=cernbox-1-test-revad-dataprovider-localhome
REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT=9143
REVAD_DATAPROVIDER_LOCALHOME_PORT=80

# OCM
REVAD_DATAPROVIDER_OCM_HOST=cernbox-1-test-revad-dataprovider-ocm
REVAD_DATAPROVIDER_OCM_GRPC_PORT=9146
REVAD_DATAPROVIDER_OCM_PORT=80

# ScienceMesh
REVAD_DATAPROVIDER_SCIENCEMESH_HOST=cernbox-1-test-revad-dataprovider-sciencemesh
REVAD_DATAPROVIDER_SCIENCEMESH_GRPC_PORT=9147
REVAD_DATAPROVIDER_SCIENCEMESH_PORT=80
```

## Placeholder System

> **Generic Documentation**: For details on the placeholder system, placeholder syntax, and processing, see [Reva Base Configuration Documentation](../../revad-base/docs/configuration.md).

Placeholders are processed by initialization scripts during container startup. See [Reva Base Initialization](../../revad-base/docs/initialization.md) for details.

## Configuration Validation

### Required Environment Variables

- `DOMAIN` - Domain name (required)
- `REVAD_CONTAINER_MODE` - Container mode (required)
- `REVAD_GATEWAY_HOST` - Gateway hostname (required for gateway and dependent services)
- `REVAD_GATEWAY_GRPC_PORT` - Gateway gRPC port (required for gateway and dependent services)

### Optional Environment Variables

Most variables have defaults defined in initialization scripts. See CERNBox-specific defaults below.

## Related Documentation

- [Architecture](architecture.md) - System architecture
- [Services](services.md) - Service descriptions
- [Deployment](deployment.md) - Deployment procedures
