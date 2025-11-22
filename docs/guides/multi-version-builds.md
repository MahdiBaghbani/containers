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

# Version Manifests Guide

## Overview

Version manifests enable building multiple versions of the same service with different source versions, dependencies, and configurations. This is essential for supporting multiple upstream versions (like Reva v1.28 and v1.29) from a single service definition.

## Table of Contents

- [Quick Start](#quick-start)
- [Manifest Schema](#manifest-schema)
- [Version Resolution](#version-resolution)
- [CLI Usage](#cli-usage)
- [CI/CD Integration](#cicd-integration)
- [Examples](#examples)
- [Best Practices](#best-practices)

---

## Quick Start

### 1. Create a Version Manifest

Create `services/{service-name}/versions.nuon`:

```nuon
{
  "default": "v1.29.0",
  "versions": [
    {
      "name": "v1.29.0",
      "latest": true,
      // Tags auto-generated: ["v1.29.0", "latest", "v1.29", "v1"]
      "tags": ["v1.29", "v1"],
      "overrides": {
        "sources": {
          "reva": {
            "ref": "v1.29.0"
          }
        }
      }
    },
    {
      "name": "v1.28.0",
      // Tags auto-generated: ["v1.28.0", "v1.28"]
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

### 2. Build Specific Version

```bash
nu scripts/build.nu --service revad-base --version v1.29.0
```

### 3. Build All Versions

```bash
nu scripts/build.nu --service revad-base --all-versions
```

---

## Manifest Schema

### Top-Level Fields

| Field      | Type   | Required | Description                                                                                                          |
| ---------- | ------ | -------- | -------------------------------------------------------------------------------------------------------------------- |
| `default`  | string | Yes      | Default version to build when no `--version` flag is specified. Must match a version `name` in the `versions` array. |
| `versions` | list   | Yes      | List of version specifications                                                                                       |

**Validation Rules for `default` field:**

- The `default` value MUST exactly match a version `name` in the `versions` array
- Validation occurs during service configuration loading (before build starts)
- If `default` references a version that doesn't exist in `versions`, validation fails with error:

  ```text
  Error: Default version 'v1.0.0' not found in versions list
  ```

- **Important:** If you remove a version from the `versions` array but it's still referenced by `default`, the build will fail. Always update `default` when removing versions.

**Example of invalid manifest:**

```nuon
{
  "default": "v1.0.0",  // ERROR ERROR: v1.0.0 not in versions array
  "versions": [
    {
      "name": "v2.0.0",  // Only v2.0.0 exists
      "latest": true
    }
  ]
}
```

### Version Specification

| Field       | Type               | Required | Description                                                                                                                                                                                                  |
| ----------- | ------------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`      | string             | Yes      | Version identifier (automatically added as a tag). Must be unique across all versions. **MUST NOT include platform suffixes** (e.g., `-debian`, `-alpine`) - these are added automatically during expansion. |
| `latest`    | bool               | No       | Whether this version should be tagged as "latest" (default: false). Only ONE version can have this set to true. When true, "latest" tag is automatically added.                                              |
| `tags`      | list&lt;string&gt; | No       | Additional image tags (for aliases). Cannot contain the version `name` or `"latest"` (these are auto-generated). Tags must be unique across ALL versions.                                                    |
| `overrides` | record             | No       | Configuration overrides for this version                                                                                                                                                                     |

**WARNING: Platform Suffixes in Version Names**

Version names in the manifest MUST NOT include platform suffixes. Platform suffixes (e.g., `-debian`, `-alpine`) are automatically added during version expansion when a `platforms.nuon` manifest exists.

**WRONG:**

```nuon
{
  "name": "v1.0.0-debian"  // ERROR: Platform suffix in version name
}
```

**CORRECT:**

```nuon
{
  "name": "v1.0.0"  // Platform suffix added automatically during expansion
}
```

When building with `--version v1.0.0-debian`, the build system detects the platform suffix for filtering, but the version name in the manifest must be the base name without the suffix.

**Tag Generation Rules:**

- Final tags = `[name]` + (if `latest: true` then `["latest"]`) + `tags`
- Example: `name: "v3.3.2"`, `latest: true`, `tags: ["v3.3", "v3"]` -> Final: `["v3.3.2", "latest", "v3.3", "v3"]`
- The `name` and `"latest"` are automatically generated - do NOT include them in the `tags` array
- All tags must be globally unique across all versions in the manifest

### Override Fields

The `overrides` section can override any field from the base service config:

**Common Overrides:**

- `sources.{name}.ref` - Change source repository ref/branch/tag
- `sources.{name}.url` - Change source repository URL
- `external_images.{stage}.image` - Change external base images
- `build_args.{name}` - Override build arguments
- `dependencies.{name}.version` - Pin dependency to specific version

**Override Behavior:**

- Overrides are **deep merged** with base config
- Specific fields override; missing fields use base config values

**Source Replacement (Special Behavior):**

Source configurations use **per-key replacement** instead of deep merge. This is because source fields are mutually exclusive: a source cannot have both `path` (local) and `url`/`ref` (Git) at the same time.

**How Source Replacement Works:**

- When a source key appears in overrides, it **completely replaces** the default source for that key
- Sources from defaults that are **not** in overrides are **preserved**
- This applies to both global and platform-specific source overrides

**Example: Git Source to Local Source**

```nuon
{
  "default": "local",
  "defaults": {
    "sources": {
      "gaia": {
        "url": "https://github.com/example/gaia",
        "ref": "v1.0.0"
      },
      "nushell": {
        "url": "https://github.com/nushell/nushell",
        "ref": "0.108.0"
      }
    }
  },
  "versions": [
    {
      "name": "local",
      "overrides": {
        "sources": {
          "gaia": {
            "path": ".repos/gaia"
            // nushell omitted - will be preserved from defaults
          }
        }
      }
    }
  ]
}
```

**Result for `local` version:**

- `sources.gaia`: Only `path` field (no `url`/`ref`) - **replaced**
- `sources.nushell`: `url` and `ref` from defaults - **preserved**

**Important Notes:**

- Source replacement is **per-key only** - only source keys explicitly defined in overrides are replaced
- Other fields (`dependencies`, `external_images`, `build_args`, etc.) continue using normal deep-merge
- This behavior applies to both global and platform-specific source overrides

**Platform-Specific Overrides (Multi-Platform Services):**

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
          "reva": {"ref": "v1.0.0"}
        },
        // Platform-specific overrides (override global for specific platforms)
        "platforms": {
          "debian": {
            "build_args": {
              "DEBIAN_SPECIFIC": "value"
            },
            "sources": {
              "reva": {"ref": "v1.0.0-debian"}
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

**Platform Override Merge Precedence:**

1. Base config (`services/{service-name}.nuon`)
2. Platform config (`platforms.nuon`)
3. Global version overrides (`versions.nuon` - `overrides` excluding `platforms` key)
4. Platform-specific version overrides (`versions.nuon` - `overrides.platforms.{platform_name}`) - **highest priority**

Platform-specific overrides win over global overrides for the same field. All fields can be overridden per platform: `sources`, `external_images`, `build_args`, `dependencies`, `labels`, `dockerfile`.

**See Also:** [Multi-Platform Builds Guide](multi-platform-builds.md) for complete platform documentation.

### Top-Level Defaults

When multiple versions share the same configuration values, you can use the optional `defaults` field to reduce repetition. Defaults are deep-merged into each version's `overrides` field.

**Example: Reducing Repetition**

**Before (repetitive):**

```nuon
{
  "default": "v3.3.2",
  "versions": [
    {
      "name": "v3.3.2",
      "overrides": {
        "external_images": {
          "build": { "tag": "1.25-trixie" }
        },
        "dependencies": {
          "common-tools": { "version": "v1.0.0-debian" }
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
        }
      }
    }
  ]
}
```

**After (with defaults):**

```nuon
{
  "default": "v3.3.2",
  "defaults": {
    "external_images": {
      "build": { "tag": "1.25-trixie" }
    },
    "dependencies": {
      "common-tools": { "version": "v1.0.0-debian" }
    }
  },
  "versions": [
    {
      "name": "v3.3.2",
      "overrides": {}
    },
    {
      "name": "v3.3.3",
      "overrides": {}
    }
  ]
}
```

**Platform-Specific Defaults:**

For multi-platform services, you can define defaults that apply only to specific platforms:

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

**How Defaults Work:**

1. **Global defaults** merge into each version's `overrides` field
2. **Platform-specific defaults** (`defaults.platforms.{platform}`) merge into `overrides.platforms.{platform}`
3. **Version overrides** take precedence over defaults
4. If a version doesn't have an `overrides` field, defaults create it

**Migration:**

To migrate an existing manifest to use defaults:

1. Identify common values shared across all versions
2. Extract them to the `defaults` field
3. Remove duplicates from version `overrides`
4. Verify merged configs match exactly (field-by-field comparison)

**See Also:** [Version Manifest Schema Reference](../reference/version-manifest-schema.md#top-level-defaults) for complete defaults documentation.

---

## Version Resolution

### Service Version

When building a service, the version is resolved in this order:

1. **`--version` CLI flag** (highest priority) - Use specific version from manifest
2. **Manifest `default` field** - If no `--version` specified, uses the default version from the manifest
3. **Error if not found** - Build fails if version not in manifest

**Note:** All services MUST have a version manifest. There are no fallbacks to Git tags or "local" versions.

### Tags

Tags are auto-generated from the manifest:

1. **Version name** (always included)
2. **"latest" tag** (if `latest: true`)
3. **Custom tags** (from `tags` array)

### Dependency Versions

Dependencies resolve their version in this order:

1. **Explicit version** in dependency config: `"version": "v3.3.2"` -> always use this
2. **Parent service version** (auto-match) -> inherit from parent if no explicit version
3. **Error**: If no version can be determined, build fails with clear error message

**Note:** Dependencies do not fall back to their own manifest's default version or "latest" tag. They must either have an explicit version or inherit from the parent service version.

---

## CLI Usage

### Single Version Builds

```bash
# Build default version from manifest
nu scripts/build.nu --service revad-base

# Build specific version from manifest
nu scripts/build.nu --service revad-base --version v1.29.0

# Build custom version (not in manifest)
nu scripts/build.nu --service revad-base --version v1.30.0-rc1
```

### Multi-Version Builds

```bash
# Build all versions in manifest
nu scripts/build.nu --service revad-base --all-versions

# Build specific versions (comma-separated list)
# Note: --versions (plural) for multiple versions, --version (singular) for single version
nu scripts/build.nu --service revad-base --versions v1.29.0,v1.28.0

# Build only versions marked as "latest"
nu scripts/build.nu --service revad-base --latest-only
```

**Flag Distinction:**

- `--version <string>` - Build a single specific version
- `--versions <string>` - Build multiple versions (comma-separated list)

### CI Matrix Generation

```bash
# Output GitHub Actions matrix JSON
nu scripts/build.nu --service revad-base --matrix-json
```

Output:

```json
{
  "include": [
    { "version": "v1.29.0", "latest": true, "tags": "v1.29.0,v1.29,v1,latest" },
    { "version": "v1.28.0", "latest": false, "tags": "v1.28.0,v1.28" }
  ]
}
```

### Previewing Build Order

Use `--show-build-order` to preview dependency chains for multiple versions without building:

```bash
# Show build order for default version
nu scripts/build.nu --service revad-base --show-build-order

# Show build order for all versions
nu scripts/build.nu --service revad-base --show-build-order --all-versions

# Show build order for specific versions
nu scripts/build.nu --service revad-base --show-build-order --versions v1.29.0,v1.28.0

# Show build order for latest versions only
nu scripts/build.nu --service revad-base --show-build-order --latest-only

# Show build order for all versions, filtered to specific platform
nu scripts/build.nu --service revad-base --show-build-order --all-versions --platform production
```

**Output Format:**

For single-version:

```text
=== Build Order ===

1. common-tools:v1.0.0
2. revad-base:v1.29.0
```

For multi-version:

```text
=== Build Order ===

Version: v1.29.0
1. common-tools:v1.0.0
2. revad-base:v1.29.0

Version: v1.28.0
1. common-tools:v1.0.0
2. revad-base:v1.28.0
```

For multi-platform services, each version/platform combination is displayed separately:

```text
=== Build Order ===

Version: v1.29.0 (production)
1. common-tools:v1.0.0:production
2. revad-base:v1.29.0:production

Version: v1.29.0 (development)
1. common-tools:v1.0.0:development
2. revad-base:v1.29.0:development
```

**Use Cases:**

- Auditing dependency chains across multiple versions before building
- Verifying that all versions resolve dependencies correctly
- Understanding build order differences between versions
- Release planning and dependency impact analysis

**See Also:** [CLI Reference](../reference/cli-reference.md#--show-build-order) for complete flag documentation.

### Build Flags

All standard build flags work with version manifests:

```bash
# Build and push
nu scripts/build.nu --service revad-base --version v1.29.0 --push

# Build with progress output
nu scripts/build.nu --service revad-base --all-versions --progress plain

# Build without latest tag
nu scripts/build.nu --service revad-base --version v1.28.0 --latest false
```

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: Build Multi-Version Images

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  # Generate build matrix
  matrix:
    runs-on: ubuntu-latest
    outputs:
      revad-base: ${{ steps.reva.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4

      - name: Install Nushell
        run: curl -sSL https://install.nu | sh

      - name: Generate revad-base matrix
        id: reva
        run: |
          matrix=$(nu scripts/build.nu --service revad-base --matrix-json)
          echo "matrix=$matrix" >> $GITHUB_OUTPUT

  # Build all versions in parallel
  build-revad-base:
    needs: matrix
    runs-on: ubuntu-latest
    strategy:
      matrix: ${{ fromJson(needs.matrix.outputs.revad-base) }}
    steps:
      - uses: actions/checkout@v4

      - name: Build revad-base:${{ matrix.version }}
        run: |
          nu scripts/build.nu \
            --service revad-base \
            --version ${{ matrix.version }} \
            --push
```

### Conditional Latest Tagging

```yaml
- name: Build with latest tag
  if: matrix.latest == true
  run: |
    nu scripts/build.nu \
      --service revad-base \
      --version ${{ matrix.version }} \
      --push
```

---

## Examples

### Example 1: Simple Multi-Version Service

**Use Case:** Build Reva v1.29 and v1.28

`services/revad-base/versions.nuon`:

```nuon
{
  "default": "v1.29.0",
  "versions": [
    {
      "name": "v1.29.0",
      "latest": true,
      "tags": ["v1.29"],  // Only additional aliases; "v1.29.0" and "latest" are auto-generated
      "overrides": {
        "sources": {
          "reva": {"ref": "v1.29.0"}
        }
      }
    },
    {
      "name": "v1.28.0",
      "tags": ["v1.28"],  // Only additional alias; "v1.28.0" is auto-generated
      "overrides": {
        "sources": {
          "reva": {"ref": "v1.28.0"}
        }
      }
    }
  ]
}
```

Build commands:

```bash
# Build both versions
nu scripts/build.nu --service revad-base --all-versions

# Result:
# - revad-base:v1.29.0, revad-base:latest, revad-base:v1.29
# - revad-base:v1.28.0, revad-base:v1.28
```

### Example 2: Complex Version Matrix

**Use Case:** Nextcloud with different contacts app versions

`services/nextcloud/versions.nuon`:

```nuon
{
  "default": "v31.0.5",
  "versions": [
    {
      "name": "v31.0.5",
      "latest": true,
      "tags": ["v31"],  // "v31.0.5" and "latest" are auto-generated
      "overrides": {
        "sources": {
          "nextcloud": {"ref": "v31.0.5"},
          "contacts": {
            "url": "https://github.com/nextcloud-releases/contacts/releases/download/v7.0.6/contacts-v7.0.6.tar.gz",
            "ref": "v7.0.6"
          }
        }
      }
    },
    {
      "name": "v29.0.16",
      "tags": ["v29"],  // "v29.0.16" is auto-generated
      "overrides": {
        "sources": {
          "nextcloud": {"ref": "v29.0.16"},
          "contacts": {
            "url": "https://github.com/nextcloud-releases/contacts/releases/download/v6.0.2/contacts-v6.0.2.tar.gz",
            "ref": "v6.0.2"
          }
        }
      }
    }
  ]
}
```

### Example 3: Build Args Override

**Use Case:** Different build settings per version

```nuon
{
  "default": "prod",
  "versions": [
    {
      "name": "prod",
      "latest": true,
      // "prod" and "latest" are auto-generated, tags array can be empty or omitted
      "overrides": {
        "build_args": {
          "PACK_WITH_UPX": "true",
          "OPTIMIZATION_LEVEL": "3"
        }
      }
    },
    {
      "name": "debug",
      // "debug" is auto-generated from name
      "overrides": {
        "sources": {
          "reva": {"ref": "main"}
        },
        "build_args": {
          "PACK_WITH_UPX": "false",
          "DEBUG": "true"
        }
      }
    }
  ]
}
```

### Example 4: Edge/Development Builds

**Use Case:** Continuous builds from main branch

```nuon
{
  "default": "stable",
  "versions": [
    {
      "name": "stable",
      "latest": true,
      // Tags: ["stable", "latest", "v3.3.2"]
      "tags": ["v3.3.2"],  // "stable" and "latest" are auto-generated
      "overrides": {
        "sources": {
          "reva": {"ref": "v3.3.2"}
        }
      }
    },
    {
      "name": "edge",
      // Tags: ["edge", "dev", "main"]
      "tags": ["dev", "main"],  // "edge" is auto-generated
      "overrides": {
        "sources": {
          "reva": {"ref": "main"}
        }
      }
    }
  ]
}
```

---

## Best Practices

### Naming Conventions

**Version Names:**

- Use semantic version format: `v1.2.3`
- Use descriptive names for special versions: `edge`, `dev`, `stable`
- Version names must be unique across all versions in the manifest

**Tags:**

- Version name is automatically used as a tag (don't include in `tags` array)
- Use `latest: true` for the current production version (only one!)
- Use `tags` array for semantic version aliases: `["v1.29", "v1"]`
- Do NOT duplicate the version name or "latest" in the tags array
- All tags must be globally unique across ALL versions

### Organization

- One manifest per service
- Group related versions together
- Use comments to document version compatibility
- Use `defaults` to reduce repetition when versions share configuration

### Maintenance

- Archive old versions after EOL
- Keep at least 2 recent versions
- Test new versions before marking as `latest`
- Extract common values to `defaults` to reduce file size and maintenance burden

---

## Troubleshooting

### Error: "Version manifest not found"

**Solution:** Create `services/{service}/versions.nuon` or remove version-specific flags.

### Error: "Version 'x' not found in manifest"

**Solution:** Either add the version to the manifest or build without specifying a version.

### Dependency Version Mismatch

**Problem:** Service wants `revad-base:v2` but only `v3` is available.

**Solution:** Build the required dependency version first:

```bash
nu scripts/build.nu --service revad-base --version v2
nu scripts/build.nu --service cernbox-revad --version v2
```

---

## See Also

- [Version Manifest Schema Reference](../reference/version-manifest-schema.md) - Complete schema documentation
- [Dependency Management](../concepts/dependency-management.md) - How dependency versions are resolved
- [Multi-Platform Builds Guide](multi-platform-builds.md) - Platform-specific version overrides
- [CLI Reference](../reference/cli-reference.md) - Complete CLI documentation
- [Schema Files](../../schemas/versions.nuon) - Authoritative schema definition
