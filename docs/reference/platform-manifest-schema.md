<!--
# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
-->

# Platform Manifest Schema

## Overview

Complete reference for the platform manifest schema (`platforms.nuon` files).

## Schema Location

Platform manifests are stored as `.nuon` files in service directories:

- `services/{service-name}/platforms.nuon` - Platform manifest

For the authoritative schema file, see [`schemas/platforms.nuon`](../../schemas/platforms.nuon).

## JSONC Compatibility Requirement

**CRITICAL**: All `.nuon` files (including `platforms.nuon`) MUST use quoted keys for JSONC compatibility. See [Service Configuration](../concepts/service-configuration.md) for details.

## Top-Level Fields

| Field       | Type   | Required | Description                                                                                                                                                                  |
| ----------- | ------ | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `default`   | string | Yes      | Default platform name. Must match a platform `name` in the `platforms` array.                                                                                                |
| `defaults`  | record | No       | Top-level defaults applied to all platforms unless overridden. Structure matches platform config (without `name` and `dockerfile`). Deep-merged into each platform's config. |
| `platforms` | list   | Yes      | List of platform configurations                                                                                                                                              |

## Top-Level Defaults

The optional `defaults` field allows you to define common configuration values that apply to all platforms unless overridden. This reduces repetition when multiple platforms share the same configuration.

### Defaults Structure

The `defaults` field has the same structure as platform configs, but excludes:

- `name` - Each platform must have its own name
- `dockerfile` - Each platform must have its own dockerfile path

Allowed fields:

- `build_args` - Default build arguments
- `external_images` - Default external images (infrastructure only: name and build_arg)
- `dependencies` - Default dependencies (infrastructure only: service and build_arg)
- `labels` - Default labels

### How Defaults Work

1. **Defaults** are deep-merged into each platform's config
2. **Platform configs** take precedence over defaults (platform wins)
3. If a platform doesn't define a field, it uses the default

### Merge Order

```text
Base Config
  ->
Platform Config (with platform defaults already merged)
  ->
Version Overrides
```

### Example: Using Defaults

**Before (repetitive):**

```nuon
{
  "default": "production",
  "platforms": [
    {
      "name": "production",
      "dockerfile": "Dockerfile.production",
      "external_images": {
        "build": {
          "name": "golang",
          "build_arg": "BASE_BUILD_IMAGE"
        },
        "runtime": {
          "name": "gcr.io/distroless/static-debian12",
          "build_arg": "BASE_RUNTIME_IMAGE"
        }
      },
      "dependencies": {
        "common-tools": {
          "service": "common-tools",
          "build_arg": "COMMON_TOOLS_IMAGE"
        }
      }
    },
    {
      "name": "development",
      "dockerfile": "Dockerfile.development",
      "external_images": {
        "build": {
          "name": "golang",
          "build_arg": "BASE_BUILD_IMAGE"
        },
        "runtime": {
          "name": "debian",
          "build_arg": "BASE_RUNTIME_IMAGE"
        }
      },
      "dependencies": {
        "common-tools": {
          "service": "common-tools",
          "build_arg": "COMMON_TOOLS_IMAGE"
        }
      }
    }
  ]
}
```

**After (with defaults):**

```nuon
{
  "default": "production",
  "defaults": {
    "external_images": {
      "build": {
        "name": "golang",
        "build_arg": "BASE_BUILD_IMAGE"
      }
    },
    "dependencies": {
      "common-tools": {
        "service": "common-tools",
        "build_arg": "COMMON_TOOLS_IMAGE"
      }
    }
  },
  "platforms": [
    {
      "name": "production",
      "dockerfile": "Dockerfile.production",
      "external_images": {
        "runtime": {
          "name": "gcr.io/distroless/static-debian12",
          "build_arg": "BASE_RUNTIME_IMAGE"
        }
      }
    },
    {
      "name": "development",
      "dockerfile": "Dockerfile.development",
      "external_images": {
        "runtime": {
          "name": "debian",
          "build_arg": "BASE_RUNTIME_IMAGE"
        }
      }
    }
  ]
}
```

### Overriding Defaults

Platform configs take precedence over defaults:

```nuon
{
  "defaults": {
    "external_images": {
      "build": {
        "name": "golang",
        "build_arg": "BASE_BUILD_IMAGE"
      }
    }
  },
  "platforms": [
    {
      "name": "production",
      "dockerfile": "Dockerfile.production",
      "external_images": {
        "build": {
          "name": "golang",
          "build_arg": "BASE_BUILD_IMAGE"
        },
        "runtime": {
          "name": "custom-runtime",  // Overrides default
          "build_arg": "BASE_RUNTIME_IMAGE"
        }
      }
    }
  ]
}
```

### Validation Rules

Defaults are validated using the same rules as platform configs:

- Forbids `sources` section (version control - define in versions.nuon overrides only)
- Forbids `tag` field in `external_images` (version control - define in versions.nuon overrides)
- Forbids `version` field in `dependencies` (version control - define in versions.nuon overrides)
- Requires `name` and `build_arg` in `external_images` (if present)
- Requires `service` and `build_arg` in `dependencies` (if present)

## Platform Specification

| Field             | Type   | Required | Description                                                                                         |
| ----------------- | ------ | -------- | --------------------------------------------------------------------------------------------------- |
| `name`            | string | Yes      | Platform identifier (lowercase alphanumeric with dashes). Must be unique within the platforms list. |
| `dockerfile`      | string | Yes      | Platform-specific Dockerfile path                                                                   |
| `build_args`      | record | No       | Platform-specific build args                                                                        |
| `external_images` | record | No       | Platform-specific external images (infrastructure only: name and build_arg, no tag)                 |
| `dependencies`    | record | No       | Platform-specific dependencies (infrastructure only: service and build_arg, no version)             |
| `labels`          | record | No       | Platform-specific labels                                                                            |

## Platform Name Rules

Platform names must:

- Be lowercase alphanumeric with optional dashes: `^[a-z0-9]+(?:-[a-z0-9]+)*$`
- Dashes are optional: single-word names (e.g., `debian`, `alpine`) don't need dashes
- Multi-word names use dashes (e.g., `ubuntu-jammy`, `redhat-9`)
- Not contain double dashes (`--`)
- Not end with a dash (`-`)
- Be unique within the platforms list

**Valid:** `debian`, `alpine`, `ubuntu-jammy`, `debian12`, `redhat-9`  
**Invalid:** `Debian` (uppercase), `alpine_3.19` (underscore), `ubuntu--lts` (double dash), `debian-` (trailing dash)

### Validation Error Examples

If validation fails, you'll see errors like:

```text
Error: Platform name 'Debian' must be lowercase alphanumeric with dashes only (matches: ^[a-z0-9]+(?:-[a-z0-9]+)*$)

Error: Platform name 'alpine_3.19' contains invalid character '_'. Use dashes instead: 'alpine-3-19'

Error: Platform name 'ubuntu--lts' contains double dashes. Use single dash: 'ubuntu-lts'

Error: Platform name 'debian-' ends with a dash. Remove trailing dash: 'debian'

Error: Default platform 'invalid' not found in platforms list

Error: Platform name 'debian' is not unique (appears multiple times in platforms list)
```

## Complete Schema Example

```nuon
{
  "default": "debian",
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "Dockerfile.debian",
      "build_args": {
        "BASE_IMAGE": "debian:12-slim",
        "VARIANT": "standard"
      },
      "external_images": {
        "base": {
          "name": "debian",
          "build_arg": "BASE_IMAGE"
        }
      },
      "dependencies": {
        "other_service": {
          "service": "other-service",
          "build_arg": "OTHER_SERVICE_IMAGE"
        }
      },
      "labels": {
        "org.opencontainers.image.variant": "debian"
      }
    },
    {
      "name": "alpine",
      "dockerfile": "Dockerfile.alpine",
      "build_args": {
        "BASE_IMAGE": "alpine:3.19"
      }
    }
  ]
}
```

## Configuration Merging

**See [Build System](../concepts/build-system.md#configuration-merging-multi-platform) for authoritative merge precedence documentation.**

When a platform manifest exists, configurations are merged in this order:

```text
Base Config (services/{service-name}.nuon)
  ->
Platform Config (from platforms.nuon)
  ->
Global Version Overrides (from versions.nuon)
  ->
Platform-Specific Version Overrides (from versions.nuon)
  ->
Final Config
```

### Merge Rules

1. **Dockerfile**: Replaced entirely (platform config wins)
2. **Records**: Deep-merged recursively (nested records merged, keys combined)
3. **Lists, strings, numbers**: Replaced entirely (platform config wins, same as dockerfile)

For complete details on configuration merging, see [Build System](../concepts/build-system.md).

## Forbidden Fields

**CRITICAL**: The following fields are **FORBIDDEN** in `platforms.nuon`:

- `sources` section - Version control, must be in `versions.nuon` overrides only
- `external_images.{stage}.tag` - Version control, must be in `versions.nuon` overrides
- `external_images.{stage}.image` - Legacy field, use `name` instead
- `dependencies.{name}.version` - Version control, must be in `versions.nuon` overrides
- `tls` section - Metadata, must be in base config only

**Error examples:**

```text
Platform 'debian': sources: Section forbidden. Define in versions.nuon overrides only.
Platform 'debian': external_images.build.tag: Field forbidden. Define in versions.nuon overrides.
Platform 'debian': dependencies.revad-base.version: Field forbidden. Define in versions.nuon overrides.
```

## See Also

- [Multi-Platform Builds Guide](../guides/multi-platform-builds.md) - Complete platform management guide
- [Build System](../concepts/build-system.md) - Configuration merging details
- [Schema File](../../schemas/platforms.nuon) - Authoritative schema definition
