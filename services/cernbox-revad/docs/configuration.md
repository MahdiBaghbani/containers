# Configuration Reference

Configuration files, environment variables, and template system documentation.

## Configuration Files

### Gateway Configuration

**File:** `cernbox-gateway.toml`  
**Location:** `services/cernbox-revad/configs/`

**Key Sections:**

- `[grpc.services.gateway]` - Gateway service configuration
- `[grpc.services.authregistry]` - Auth registry mapping
- `[grpc.services.storageregistry]` - Storage registry mapping

**Service Addresses:**

- Uses template variables for same-container services: `{{ grpc.services.authregistry.address }}`
- Uses placeholders for external services: `{{placeholder:shareproviders.address}}`

### Share Providers Configuration

**File:** `cernbox-shareproviders.toml`  
**Location:** `services/cernbox-revad/configs/`

**Key Sections:**

- `[grpc.services.usershareprovider]` - User share provider
- `[grpc.services.publicshareprovider]` - Public share provider
- `[grpc.services.ocmshareprovider]` - OCM share provider

### User/Group Providers Configuration

**File:** `cernbox-groupuserproviders.toml`  
**Location:** `services/cernbox-revad/configs/`

**Key Sections:**

- `[grpc.services.userprovider]` - User provider
- `[grpc.services.groupprovider]` - Group provider

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

The configuration system uses placeholders for dynamic value injection.

### Placeholder Syntax

```text
{{placeholder:name:default-value}}
```

- **name:** Placeholder identifier
- **default-value:** Optional default value if not provided

### Placeholder Types

#### Template Variables

Used for same-container services:

```text
{{ grpc.services.service_name.address }}
```

Examples:

- `{{ grpc.services.authregistry.address }}`
- `{{ grpc.services.appregistry.address }}`
- `{{ grpc.services.storageregistry.address }}`

#### Custom Placeholders

Used for external services and configuration:

```text
{{placeholder:shareproviders.address}}
{{placeholder:groupuserproviders.address}}
{{placeholder:log-level:debug}}
{{placeholder:jwt-secret:reva-secret}}
```

### Placeholder Processing

Placeholders are processed by Nushell scripts during container initialization:

1. **Read Environment Variables:** Scripts read environment variables

2. **Build Placeholder Map:** Create map of placeholder names to values

3. **Process Templates:** Replace placeholders with actual values

4. **Save Configuration:** Write processed config to `/etc/revad/`

## Volume Mounts

### Configuration Volumes

Each service has its own configuration volume:

```yaml
volumes:
  - "${PWD}/volumes/config/reva-gateway:/etc/revad"
  - "${PWD}/volumes/config/reva-shareproviders:/etc/revad"
  - "${PWD}/volumes/config/reva-groupuserproviders:/etc/revad"
  # ... etc
```

### Data Volumes

Shared data volumes:

```yaml
volumes:
  - "${PWD}/volumes/data/reva/jsons:/var/tmp/reva"
```

## Container Initialization

### Initialization Scripts

- **Gateway:** `init-gateway.nu`
- **Share Providers:** `init-shareproviders.nu`
- **User/Group Providers:** `init-groupuserproviders.nu`
- **Auth Providers:** `init-authprovider.nu`
- **Dataproviders:** `init-dataprovider.nu`

### Initialization Process

1. **Validate Environment:** Check required environment variables
2. **Copy Templates:** Copy config templates from image
3. **Process Placeholders:** Replace placeholders with values
4. **TLS Configuration:** Handle TLS certificate setup
5. **Start Service:** Launch Reva daemon with config file

## Configuration Validation

### Required Environment Variables

- `DOMAIN` - Domain name (required)
- `REVAD_CONTAINER_MODE` - Container mode (required)
- `REVAD_GATEWAY_HOST` - Gateway hostname (required)
- `REVAD_GATEWAY_GRPC_PORT` - Gateway gRPC port (required)

### Optional Environment Variables

Most variables have defaults defined in initialization scripts.

## Related Documentation

- [Architecture](architecture.md) - System architecture
- [Services](services.md) - Service descriptions
- [Deployment](deployment.md) - Deployment procedures
