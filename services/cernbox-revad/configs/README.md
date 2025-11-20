# CERNBox Reva Configuration

This directory supports two mechanisms for customizing CERNBox Reva configurations:

1. **Full Config Overrides** - Complete replacement of base config files
2. **Partial Configs** - Extend base configs without duplication

## Configuration Mechanisms

### 1. Full Config Overrides

**Location**: `configs/*.toml` (this directory)

**How It Works**:

- Files placed directly in `configs/` are copied to `/configs/revad` during image build
- They completely replace base configs with the same names
- Use when you need to replace the entire configuration file

**When to Use**:

- Complete replacement of a base config
- Major configuration changes that affect most of the file
- Backward compatibility with existing override workflows

**Example**:

```bash
# Override entire gateway config
cp /path/to/cernbox-gateway.toml configs/gateway.toml
```

### 2. Partial Configs

**Location**: `configs/partial/*.toml`

**How It Works**:

- Partial configs are merged into target config files during build-time or runtime
- They extend base configs without duplicating the entire file
- Use when you only need to add or modify specific sections

**When to Use**:

- Adding new services (e.g., thumbnail service)
- Extending existing configs with additional settings
- Maintaining separation between base and service-specific configs

**Example**:

```bash
# Add thumbnail service via partial
cat > configs/partial/thumbnails.toml <<EOF
[target]
file = "gateway.toml"
order = 1

[http.services.thumbnails]
cache = "lru"
output_type = "jpg"
quality = 80
EOF
```

**See**: [Partial Config Schema Reference](../../../revad-base/docs/partial-config-schema.md) for complete documentation.

## Precedence

Configuration processing follows this order:

1. **Build-time**: Full overrides replace base configs
2. **Build-time**: Partials merge into base/overridden configs (baked into image)
3. **Runtime**: Full overrides in volume replace config copy
4. **Runtime**: Partials merge into config (volume first, then image fallback)
5. **Runtime**: Placeholders processed after all merges

## Base Configuration Reference

For information about base Reva configurations and the configuration system:

- **Base Configs**: See `services/revad-base/configs/` for all available base configuration templates
- **Configuration Documentation**: See `services/revad-base/docs/configuration.md` for configuration system details
- **Placeholder System**: See `services/revad-base/docs/configuration.md#placeholder-system` for placeholder syntax and usage
- **Service Documentation**: See `services/revad-base/docs/services.md` for service-specific configuration details
- **Reva Base Docs**: See `services/revad-base/docs/README.md` for complete documentation index
- **Partial Config Schema**: See `services/revad-base/docs/partial-config-schema.md` for partial config format and usage

## Available Config Files

You can override or extend these configuration files:

- `gateway.toml` - Gateway configuration
- `dataprovider-localhome.toml` - Localhome dataprovider config
- `dataprovider-ocm.toml` - OCM dataprovider config
- `dataprovider-sciencemesh.toml` - ScienceMesh dataprovider config
- `authprovider-oidc.toml` - OIDC auth provider config
- `authprovider-machine.toml` - Machine auth provider config
- `authprovider-ocmshares.toml` - OCM shares auth provider config
- `authprovider-publicshares.toml` - Public shares auth provider config
- `shareproviders.toml` - Share providers config
- `groupuserproviders.toml` - User/group providers config
- Any `.json` files (users.json, groups.json, etc.)

## CERNBox-Specific Partials

CERNBox includes the following partial configs:

- `configs/partial/thumbnails.toml` - Thumbnail service configuration (merged into `gateway.toml`)

See [CERNBox Configuration Documentation](../docs/configuration.md) for details on CERNBox-specific configuration.
