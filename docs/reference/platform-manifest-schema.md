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

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `default` | string | Yes | Default platform name. Must match a platform `name` in the `platforms` array. |
| `platforms` | list | Yes | List of platform configurations |

## Platform Specification

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Platform identifier (lowercase alphanumeric with dashes). Must be unique within the platforms list. |
| `dockerfile` | string | Yes | Platform-specific Dockerfile path |
| `build_args` | record | No | Platform-specific build args |
| `external_images` | record | No | Platform-specific external images (infrastructure only: name and build_arg, no tag) |
| `dependencies` | record | No | Platform-specific dependencies (infrastructure only: service and build_arg, no version) |
| `labels` | record | No | Platform-specific labels |

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
  ↓
Platform Config (from platforms.nuon)
  ↓
Global Version Overrides (from versions.nuon)
  ↓
Platform-Specific Version Overrides (from versions.nuon)
  ↓
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
