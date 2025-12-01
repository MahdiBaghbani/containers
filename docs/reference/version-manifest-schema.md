<!--
# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
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
# Version Manifest Schema

## Overview

Complete reference for the version manifest schema (`versions.nuon` files).

**CRITICAL REQUIREMENT:** All services MUST have a version manifest. The build system requires version manifests for all services - there are no fallbacks to Git tags or "local" versions. If a version manifest is missing, the build will fail with a clear error message.

## Schema Location

Version manifests are stored as `.nuon` files in service directories:

- `services/{service-name}/versions.nuon` - Version manifest (REQUIRED for all services)

For the authoritative schema file, see [`schemas/versions.nuon`](../../schemas/versions.nuon).

## Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `default` | string | Yes | Default version to build when no `--version` flag is specified. Must match a version `name` in the `versions` array. |
| `defaults` | record | No | Top-level defaults applied to all versions unless overridden. Structure matches `overrides` field. Deep-merged into each version's overrides. |
| `versions` | list | Yes | List of version specifications |

### Validation Rules for `default` field

- The `default` value MUST exactly match a version `name` in the `versions` array
- Validation occurs during version manifest validation (before build starts)
- If `default` references a version that doesn't exist in `versions`, validation fails with error:

  ```text
  Error: Default version 'v1.0.0' not found in versions list
  ```

- **Important:** If you remove a version from the `versions` array but it's still referenced by `default`, the build will fail. Always update `default` when removing versions.

## Top-Level Defaults

The optional `defaults` field allows you to define common configuration values that apply to all versions unless overridden. This reduces repetition when multiple versions share the same configuration.

### Defaults Structure

The `defaults` field has the same structure as the `overrides` field in version specifications:

- `sources` - Default source repository refs/URLs
- `external_images` - Default external image tags
- `build_args` - Default build arguments
- `dependencies` - Default dependency versions
- `platforms` - Platform-specific defaults (for multi-platform services)

### How Defaults Work

1. **Global defaults** are deep-merged into each version's `overrides` field
2. **Platform-specific defaults** (`defaults.platforms.{platform}`) are deep-merged into `overrides.platforms.{platform}` for each platform
3. **Version overrides** take precedence over defaults (overrides win)
4. If a version doesn't have an `overrides` field, defaults create it

### Merge Order

```text
Base Config
  ->
Platform Config (with platform defaults applied)
  ->
Version Overrides (with version defaults already merged)
  ├─ Global overrides (defaults -> overrides)
  └─ Platform-specific overrides (defaults.platforms -> overrides.platforms)
```

### Example: Using Defaults

**Before (repetitive):**

```nuon
{
  "default": "v3.3.3",
  "versions": [
    {
      "name": "v3.3.3",
      "overrides": {
        "external_images": {
          "build": { "tag": "1.25-trixie" }
        },
        "dependencies": {
          "common-tools": { "version": "v1.0.0-debian" }
        },
        "platforms": {
          "production": {
            "external_images": {
              "runtime": { "tag": "nonroot" }
            }
          }
        }
      }
    },
    {
      "name": "v3.3.3",
      "overrides": {
        "external_images": {
          "build": { "tag": "1.25-trixie" }
        },
        "dependencies": {
          "common-tools": { "version": "v1.0.0-debian" }
        },
        "platforms": {
          "production": {
            "external_images": {
              "runtime": { "tag": "nonroot" }
            }
          }
        }
      }
    }
  ]
}
```

**After (with defaults):**

```nuon
{
  "default": "v3.3.3",
  "defaults": {
    "external_images": {
      "build": { "tag": "1.25-trixie" }
    },
    "dependencies": {
      "common-tools": { "version": "v1.0.0-debian" }
    },
    "platforms": {
      "production": {
        "external_images": {
          "runtime": { "tag": "nonroot" }
        }
      }
    }
  },
  "versions": [
    {
      "name": "v3.3.3",
      "overrides": {}
    },
    {
      "name": "v3.3.3",
      "overrides": {}
    }
  ]
}
```

### Platform-Specific Defaults

You can define defaults that apply only to specific platforms:

```nuon
{
  "default": "v1.0.0",
  "defaults": {
    "external_images": {
      "build": { "tag": "1.25-trixie" }
    },
    "platforms": {
      "production": {
        "external_images": {
          "runtime": { "tag": "nonroot" }
        }
      },
      "development": {
        "external_images": {
          "runtime": { "tag": "trixie-slim" }
        }
      }
    }
  },
  "versions": [
    {
      "name": "v1.0.0",
      "overrides": {
        "platforms": {
          "production": {
            "external_images": {
              "runtime": { "tag": "custom-runtime" }  // Overrides default
            }
          }
          // development gets defaults.platforms.development automatically
        }
      }
    }
  ]
}
```

### Overriding Defaults

Version overrides take precedence over defaults:

```nuon
{
  "defaults": {
    "external_images": {
      "build": { "tag": "1.25-trixie" }  // Default
    }
  },
  "versions": [
    {
      "name": "v1.0.0",
      "overrides": {
        "external_images": {
          "build": { "tag": "1.26-trixie" }  // Overrides default
        }
      }
    }
  ]
}
```

### Validation Rules

Defaults are validated using the same rules as version overrides:

- Allows `sources` section
- Allows `tag` field in `external_images`
- Forbids `name` and `build_arg` in `external_images` (infrastructure - defined in base config or platforms.nuon)
- Platform names in `defaults.platforms` must match platforms in `platforms.nuon`

## Version Specification

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Version identifier (automatically added as a tag). Must be unique across all versions. **MUST NOT include platform suffixes** (e.g., `-debian`, `-alpine`) - these are added automatically during expansion. |
| `latest` | bool | No | Whether this version should be tagged as "latest" (default: false). Only ONE version can have this set to true. When true, "latest" tag is automatically added. |
| `tags` | list<string> | No | Additional image tags (for aliases). Cannot contain the version `name` or `"latest"` (these are auto-generated). Tags must be unique across ALL versions. |
| `overrides` | record | No | Configuration overrides for this version |

### WARNING: Platform Suffixes in Version Names

Version names MUST NOT include platform suffixes (e.g., `-debian`, `-alpine`). Platform suffixes are automatically added during version expansion when a `platforms.nuon` manifest exists.

#### WRONG

```nuon
{
  "name": "v1.0.0-debian"  // ERROR: Platform suffix in version name
}
```

#### CORRECT

```nuon
{
  "name": "v1.0.0"  // Platform suffix added automatically during expansion
}
```

If you specify `--version v1.0.0-debian` on the command line, the build system will detect the platform suffix and use it for filtering, but the version name in the manifest must be the base name without the suffix.

### Tag Generation Rules

- Final tags = `[name]` + (if `latest: true` then `["latest"]`) + `tags`
- Example: `name: "v3.3.3"`, `latest: true`, `tags: ["v3.3", "v3"]` -> Final: `["v3.3.3", "latest", "v3.3", "v3"]`
- The `name` and `"latest"` are automatically generated - do NOT include them in the `tags` array
- All tags must be globally unique across all versions in the manifest

## Override Fields

The `overrides` section can override any field from the base service config:

### Common Overrides

- `sources.{name}.ref` - Change source repository ref/branch/tag
- `sources.{name}.url` - Change source repository URL (required for multi-platform)
- `external_images.{stage}.tag` - Change external image tag (version control)
- `build_args.{name}` - Override build arguments
- `dependencies.{name}.version` - Pin dependency to specific version

**CRITICAL**: For `external_images` overrides, **ONLY** the `tag` field is allowed. The `name` and `build_arg` fields are **FORBIDDEN** (infrastructure - defined in base config or platforms.nuon).

### Override Behavior

- Overrides are **deep merged** with base config
- Specific fields override; missing fields use base config values

### Platform-Specific Overrides (Multi-Platform Services)

When a service has a `platforms.nuon` manifest, you can override configuration per platform within a version:

```nuon
{
  "default": "v1.0.0",
  "versions": [
    {
      "name": "v1.0.0",
      "latest": true,
      "overrides": {
        // Global overrides (apply to all platforms)
        "sources": {
          "reva": {
            "url": "https://github.com/cs3org/reva",
            "ref": "v1.0.0"
          }
        },
        "external_images": {
          "build": {
            "tag": "1.25-trixie"
          }
        },
        "dependencies": {
          "revad-base": {
            "version": "v3.3.3"
          }
        },
        // Platform-specific overrides (override global for specific platforms)
        "platforms": {
          "debian": {
            "build_args": {
              "DEBIAN_SPECIFIC": "value"
            },
            "sources": {
              "reva": {"ref": "v1.0.0-debian"}
            },
            "external_images": {
              "build": {
                "tag": "1.26-trixie"
              }
            }
          },
          "alpine": {
            "build_args": {
              "ALPINE_SPECIFIC": "value"
            }
          }
        }
      }
    }
  ]
}
```

### Platform Override Merge Precedence

1. Base config (`services/{service-name}.nuon`)
2. Platform config (`platforms.nuon`)
3. Global version overrides (`versions.nuon` - `overrides` excluding `platforms` key)
4. Platform-specific version overrides (`versions.nuon` - `overrides.platforms.{platform_name}`) - **highest priority**

Platform-specific overrides win over global overrides for the same field. All fields can be overridden per platform: `sources`, `external_images`, `build_args`, `dependencies`, `labels`, `dockerfile`.

**CRITICAL**: For `external_images` in overrides, **ONLY** the `tag` field is allowed. The `name` and `build_arg` fields are **FORBIDDEN** (infrastructure - defined in platforms.nuon).

**See [Build System](../concepts/build-system.md#configuration-merging-multi-platform) for complete merge precedence documentation.**

## Complete Schema Example

```nuon
{
  "default": "v1.29.0",
  "versions": [
    {
      "name": "v1.29.0",
      "latest": true,
      "tags": ["v1.29", "v1"],
      "overrides": {
        "sources": {
          "reva": {
            "url": "https://github.com/cs3org/reva",
            "ref": "v1.29.0"
          }
        },
        "external_images": {
          "build": {
            "tag": "1.25-trixie"
          }
        },
        "dependencies": {
          "revad-base": {
            "version": "v3.3.3"
          }
        }
      }
    },
    {
      "name": "v1.28.0",
      "tags": ["v1.28"],
      "overrides": {
        "sources": {
          "reva": {
            "ref": "v1.28.0"
          }
        }
      }
    }
  ]
}
```

## Forbidden Fields

**CRITICAL**: The following fields are **FORBIDDEN** in version overrides:

- `external_images.{stage}.name` - Infrastructure, must be in base config (single-platform) or platforms.nuon (multi-platform)
- `external_images.{stage}.build_arg` - Infrastructure, must be in base config (single-platform) or platforms.nuon (multi-platform)
- `external_images.{stage}.image` - Legacy field, use `tag` instead
- `tls` section - Metadata, must be in base config only

**Error examples:**

```text
Version 'v1.0.0': external_images.build.name: Field forbidden. Define in base config (single-platform) or platforms.nuon (multi-platform).
Version 'v1.0.0': tls: Section forbidden. Configure TLS in base service config only.
```

## See Also

- [Multi-Version Builds Guide](../guides/multi-version-builds.md) - Complete version management guide
- [Multi-Platform Builds Guide](../guides/multi-platform-builds.md) - Platform-specific overrides
- [Schema File](../../schemas/versions.nuon) - Authoritative schema definition
