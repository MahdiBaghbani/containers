# Container Modes

The `revad-base` service supports multiple container modes via the `REVAD_CONTAINER_MODE` environment variable. Each mode determines which Reva services run in the container.

## Valid Container Modes

The following container modes are supported:

- `gateway` - Gateway services (gateway, authregistry, appregistry, storageregistry, preferences, etc.)
- `dataprovider-localhome` - Localhome storage provider
- `dataprovider-ocm` - OCM storage provider
- `dataprovider-sciencemesh` - ScienceMesh storage provider
- `authprovider-oidc` - OIDC/OAuth2 authentication provider
- `authprovider-machine` - Machine-to-machine authentication provider
- `authprovider-ocmshares` - OCM shares authentication provider
- `authprovider-publicshares` - Public shares authentication provider
- `shareproviders` - Share management services (usershareprovider, publicshareprovider, ocmshareprovider)
- `groupuserproviders` - User and group management services (userprovider, groupprovider)

## Mode Selection

The container mode is set via the `REVAD_CONTAINER_MODE` environment variable:

```bash
REVAD_CONTAINER_MODE=gateway
```

The entrypoint script validates the mode and routes to the appropriate initialization script.

## Mode-Specific Configuration

Each mode uses a specific configuration file:

- `gateway` → `gateway.toml`
- `dataprovider-{type}` → `dataprovider-{type}.toml`
- `authprovider-{type}` → `authprovider-{type}.toml`
- `shareproviders` → `shareproviders.toml`
- `groupuserproviders` → `groupuserproviders.toml`

Configuration files are located in `/configs/revad` (image) and processed to `/etc/revad` (runtime) during initialization.

## Mode Routing

The entrypoint script (`entrypoint-init.nu`) routes to mode-specific initialization:

1. Validates `REVAD_CONTAINER_MODE` against valid modes
2. Runs shared initialization (DNS, hosts, TLS, etc.)
3. Routes to mode-specific init script:
   - `init-gateway.nu` for gateway mode
   - `init-dataprovider.nu` for dataprovider modes
   - `init-authprovider.nu` for authprovider modes
   - `init-shareproviders.nu` for shareproviders mode
   - `init-groupuserproviders.nu` for groupuserproviders mode
4. Starts Reva daemon with mode-specific config file

## Related Documentation

- [Initialization](initialization.md) - Initialization process details
- [Configuration](configuration.md) - Configuration file structure
- [Services](services.md) - Service descriptions
