# CERNBox Reva Configuration Overrides

This directory allows CERNBox-specific Reva configuration files to override the base configs from `revad-base`.

## How It Works

- **If this directory contains files**: They will be copied to `/configs/revad` during image build, overriding base configs with the same names
- **If this directory is empty or doesn't exist**: Base configs from `revad-base` will be used

## Base Configuration Reference

For information about base Reva configurations and the configuration system:

- **Base Configs**: See `services/revad-base/configs/` for all available base configuration templates
- **Configuration Documentation**: See `services/revad-base/docs/configuration.md` for configuration system details
- **Placeholder System**: See `services/revad-base/docs/configuration.md#placeholder-system` for placeholder syntax and usage
- **Service Documentation**: See `services/revad-base/docs/services.md` for service-specific configuration details
- **Reva Base Docs**: See `services/revad-base/docs/README.md` for complete documentation index

## Usage

To override a base config file, place a file with the same name here:

- `gateway.toml` - Override gateway configuration
- `dataprovider-localhome.toml` - Override localhome dataprovider config
- `authprovider-oidc.toml` - Override OIDC auth provider config
- `shareproviders.toml` - Override share providers config
- `groupuserproviders.toml` - Override user/group providers config
- Any `.json` files (users.json, groups.json, etc.)

## Example

To override the gateway config with CERNBox-specific settings:

```bash
cp /path/to/cernbox-gateway.toml configs/gateway.toml
```

The file will be copied to `/configs/revad/gateway.toml` during build, replacing the base config.

## Note

The `.gitkeep` file ensures this directory is tracked by git even when empty.
