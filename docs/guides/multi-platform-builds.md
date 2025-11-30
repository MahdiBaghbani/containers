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

# Multi-Platform Build Support

This guide covers the multi-platform build system that allows building different container image variants for different base platforms (e.g., Debian, Alpine, Ubuntu).

## Overview

The multi-platform build system allows a single service to produce multiple image variants, each optimized for a different base platform. This is useful when you need:

- Different base OS distributions (Debian vs Alpine)
- Different runtime environments (with/without specific tools)
- Platform-specific optimizations or dependencies

## Quick Start

### 1. Single-Platform Service (No Changes Required)

If your service doesn't need multiple platforms, nothing changes:

```bash
# Works exactly as before
nu scripts/build.nu --service my-service --version v1.0.0
```

### 2. Multi-Platform Service

Create a `platforms.nuon` manifest alongside your service config:

```text
services/
  my-service/
    my-service.nuon       # Base configuration (services/{service-name}.nuon)
    platforms.nuon        # NEW: Platform variants
    versions.nuon         # Version manifest
```

### Example `platforms.nuon`

```nuon
{
  "default": "debian",
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "Dockerfile.debian",
      "build_args": {
        "BASE_IMAGE": "debian:12-slim"
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

### Build All Platforms for a Version

```bash
nu scripts/build.nu --service my-service --version v1.0.0
# Builds: my-service:v1.0.0-debian, my-service:v1.0.0-alpine
```

### Build Specific Platform

```bash
nu scripts/build.nu --service my-service --version v1.0.0 --platform debian
# Builds only: my-service:v1.0.0-debian
```

## Platform Manifest Format

**Note**: All `.nuon` files (including `platforms.nuon`) MUST use quoted keys for JSONC compatibility. See [Service Configuration](../concepts/service-configuration.md) for details.

For complete schema documentation, see [Platform Manifest Schema Reference](../reference/platform-manifest-schema.md).

### Quick Reference: `platforms.nuon`

```nuon
{
  // Required: Default platform name
  "default": "debian",

  // Required: List of platform configurations
  "platforms": [
    {
      // Required: Platform identifier (lowercase alphanumeric with dashes)
      "name": "debian",

      // Required: Platform-specific Dockerfile path
      "dockerfile": "Dockerfile.debian",

      // Optional: Platform-specific build args
      "build_args": {
        "BASE_IMAGE": "debian:12-slim",
        "VARIANT": "standard"
      },

      // Optional: Platform-specific external images
      "external_images": {
        "base": {
          "image": "debian:12-slim",
          "build_arg": "BASE_IMAGE"
        }
      },

      // Optional: Platform-specific source repositories
      "sources": {
        "custom_lib": {
          "url": "https://github.com/example/lib",
          "ref": "v2.0.0"
        }
      },

      // Optional: Platform-specific dependencies
      "dependencies": {
        "other_service": {
          "version": "v1.0.0",
          "build_arg": "OTHER_SERVICE_IMAGE"
        }
      },

      // Optional: Platform-specific labels
      "labels": {
        "org.opencontainers.image.variant": "debian"
      }
    }
  ]
}
```

### Platform Name Rules

Platform names must:

- Be lowercase alphanumeric with optional dashes: `^[a-z0-9]+(?:-[a-z0-9]+)*$`
- Dashes are optional: single-word names (e.g., `debian`, `alpine`) don't need dashes
- Multi-word names use dashes (e.g., `ubuntu-jammy`, `redhat-9`)
- Not contain double dashes (`--`)
- Not end with a dash (`-`)
- Be unique within the platforms list

Valid: `debian`, `alpine`, `ubuntu-jammy`, `debian12`, `redhat-9`
Invalid: `Debian` (uppercase), `alpine_3.19` (underscore), `ubuntu--lts` (double dash), `debian-` (trailing dash)

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

### Example Merge

#### Base Config (services/my-service.nuon)

```nuon
{
  "name": "my-service",
  "context": ".",
  "dockerfile": "Dockerfile",  // Will be replaced
  "build_args": {
    "COMMON_ARG": "value1"
  },
  "labels": {
    "app.name": "my-service"
  }
}
```

#### Platform Config (debian)

```nuon
{
  "dockerfile": "Dockerfile.debian",  // Replaces base
  "build_args": {
    "BASE_IMAGE": "debian:12"  // Merged with COMMON_ARG
  },
  "labels": {
    "app.variant": "debian"  // Merged with app.name
  }
}
```

#### Result

```nuon
{
  "name": "my-service",
  "context": ".",
  "dockerfile": "Dockerfile.debian",  // From platform
  "build_args": {
    "COMMON_ARG": "value1",      // From base
    "BASE_IMAGE": "debian:12"   // From platform
  },
  "labels": {
    "app.name": "my-service",  // From base
    "app.variant": "debian"   // From platform
  }
}
```

## Version Expansion

When a platforms manifest exists, versions are automatically expanded to all platforms:

### versions.nuon

```nuon
{
  "default": "v1.0.0",
  "versions": [
    {
      "name": "v1.0.0",
      "latest": true
    }
  ]
}
```

#### Expansion (with 2 platforms: debian, alpine)

- Builds: `v1.0.0-debian`, `v1.0.0-alpine`
- Tags: `latest` (debian only, unprefixed), `latest-debian`, `latest-alpine`, `v1.0.0-debian`, `v1.0.0` (unprefixed, debian only), `v1.0.0-alpine`

### Platform-Specific Version Overrides

You can override configuration per platform in the version manifest:

```nuon
{
  "default": "v1.0.0",
  "versions": [
    {
      "name": "v1.0.0",
      "latest": true,

      // Platform-specific overrides
      "platforms": {
        "debian": {
          "build_args": {
            "DEBIAN_SPECIFIC": "value"
          }
        },
        "alpine": {
          "build_args": {
            "ALPINE_SPECIFIC": "value"
          }
        }
      }
    }
  ]
}
```

### Top-Level Platform Defaults

When multiple platforms share the same configuration values, you can use the optional `defaults` field in `platforms.nuon` to reduce repetition. Defaults are deep-merged into each platform's config.

**Example: Reducing Repetition**

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

**How Platform Defaults Work:**

1. **Defaults** are deep-merged into each platform's config
2. **Platform configs** take precedence over defaults
3. Each platform must still define its own `name` and `dockerfile` (these cannot be in defaults)

**Note:** Platform defaults cannot include `sources` (version control - define in versions.nuon overrides only) or `tag` in external_images (version control - define in versions.nuon overrides).

**See Also:** [Platform Manifest Schema Reference](../reference/platform-manifest-schema.md#top-level-defaults) for complete defaults documentation.

## Tag Generation

**Note:** The formulas below show tag names only. The service name is prefixed separately to create full image references (e.g., `service-name:tag-name`).

### Single-Platform (No platforms.nuon)

**Tag Generation Formula (tag names only):**

- Final tag names = `[name]` + (if `latest: true` then `["latest"]`) + `tags`
- Example: `name: "v1.0.0"`, `latest: true`, `tags: ["v1.0", "v1"]` -> Tag names: `["v1.0.0", "latest", "v1.0", "v1"]`
- Full image references: `my-service:v1.0.0`, `my-service:latest` (if latest: true)

### Multi-Platform

**Tag Generation Formula (tag names only):**

**For default platform:**

- `[name-platform]` + `[name]` (unprefixed) + (if `latest: true` then `["latest-platform"]` + `["latest"]` (unprefixed)) + `[tag-platform for each tag]` + `[tag]` (unprefixed for each tag)

**For other platforms:**

- `[name-platform]` + (if `latest: true` then `["latest-platform"]`) + `[tag-platform for each tag]`

**Summary:**

- Default platform gets both platform-suffixed and unprefixed versions of all tags (version name + latest + custom tags)
- Other platforms only get platform-suffixed tags
- Unprefixed tags always point to the default platform

### Example

```text
Version: v1.0.0, Platforms: [debian, alpine], Default: debian, latest: true, tags: ["v1.0", "v1"]

Tags generated:

Default platform (debian):
  - my-service:v1.0.0-debian    (name + default platform)
  - my-service:v1.0.0           (unprefixed name, points to debian)
  - my-service:latest-debian    (latest + default platform)
  - my-service:latest           (unprefixed latest, points to default platform: debian)
  - my-service:v1.0-debian      (custom tag + default platform)
  - my-service:v1.0             (unprefixed custom tag, points to debian)
  - my-service:v1-debian        (custom tag + default platform)
  - my-service:v1                (unprefixed custom tag, points to debian)

Other platforms (alpine):
  - my-service:v1.0.0-alpine    (name + alpine platform)
  - my-service:latest-alpine    (latest + alpine platform)
  - my-service:v1.0-alpine      (custom tag + alpine platform)
  - my-service:v1-alpine        (custom tag + alpine platform)
```

#### Custom Tags in Multi-Platform Builds

Custom tags receive platform suffixes for all platforms, and unprefixed versions for the default platform:

```nuon
// In versions.nuon
{
  "name": "v1.0.0",
  "tags": ["stable", "prod"]
}

// Generated tags (multi-platform, default: debian):
// Default platform (debian):
// - my-service:v1.0.0-debian
// - my-service:v1.0.0           (unprefixed)
// - my-service:stable-debian
// - my-service:stable           (unprefixed)
// - my-service:prod-debian
// - my-service:prod              (unprefixed)
// Other platforms (alpine):
// - my-service:v1.0.0-alpine
// - my-service:stable-alpine
// - my-service:prod-alpine
```

## Dependency Resolution

### Platform Inheritance

Dependencies automatically inherit the platform from the parent service:

```nuon
// Service A (multi-platform: debian, alpine)
{
  "dependencies": {
    "service_b": {
      "build_arg": "SERVICE_B_IMAGE"
      // Inherits platform from A
    }
  }
}

// When building A with debian: uses service_b:latest-debian
// When building A with alpine: uses service_b:latest-alpine
```

### Explicit Platform Override

You can specify exact versions with platform suffixes:

```nuon
{
  "dependencies": {
    "service_b": {
      "version": "v1.0.0-debian",  // Always uses debian variant
      "build_arg": "SERVICE_B_IMAGE"
    }
  }
}
```

### Using Single-Platform Dependencies

When a multi-platform service depends on a single-platform service (a service without `platforms.nuon`), the dependency can be used across all parent platforms. This is useful when the dependency's binaries are compatible with all platforms of the parent service.

#### Without `single_platform` Flag

By default, single-platform dependencies are allowed with an informational message:

```nuon
// Parent: multi-platform service (production, development)
// Dependency: gaia (single-platform, Debian-based)
{
  "dependencies": {
    "gaia": {
      "version": "master"
    }
  }
}
```

Result: `gaia:master` is used for both `production` and `development` platforms
Message: `Info: Multi-platform service depends on single-platform service 'gaia'...`

#### With `single_platform` Flag

To suppress the informational message and make intent explicit, use `single_platform: true`:

```nuon
{
  "dependencies": {
    "gaia": {
      "version": "master",
      "single_platform": true  // Suppresses informational message
    }
  }
}
```

Result: `gaia:master` used for all platforms, no message

#### When to Use `single_platform: true`

Use `single_platform: true` when:

- The dependency is intentionally single-platform and compatible with all parent platforms
- You want to suppress the informational message
- You want to make the intent explicit in the configuration

**Note:** If a dependency version has a platform suffix (e.g., `"v1.0.0-debian"`), the suffix takes precedence over `single_platform: true` (with a warning).

## CLI Reference

### New Flags

#### `--platform <string>`

Filter builds to a specific platform (requires platforms.nuon):

```bash
# Build only debian variant
nu scripts/build.nu --service my-service --version v1.0.0 --platform debian

# Build all debian versions
nu scripts/build.nu --service my-service --all-versions --platform debian
```

### Version Suffix Detection

**IMPORTANT: Platform suffixes are ONLY valid when `platforms.nuon` exists.** If your service doesn't have a platforms manifest, using a platform suffix (e.g., `--version v1.0.0-debian`) will result in a validation error.

You can specify platforms inline with version names:

```bash
# Build only v1.0.0-debian (requires platforms.nuon)
nu scripts/build.nu --service my-service --version v1.0.0-debian

# Build multiple platform-specific versions
nu scripts/build.nu --service my-service --versions "v1.0.0-debian,v1.0.0-alpine"
```

**Rules:**

- **Requires `platforms.nuon`**: Platform suffixes are only valid for multi-platform services
- Suffix format: `-<platform-name>`
- Suffix must match a platform in platforms.nuon
- Cannot have double dashes: `v1.0.0--debian` is invalid
- Cannot end with dash: `v1.0.0-` is invalid
- If service has no platforms.nuon, suffix will be rejected with error: "Platform suffix 'X' specified but service has no platforms manifest"

### Error Handling

- If suffix detection fails (invalid format), the version name is used as-is without platform filtering
- Example: `--version v1.0.0-invalid` (invalid platform) -> treated as base version `v1.0.0-invalid` (may fail if not in manifest)
- If suffix is valid but platform doesn't exist in manifest, build fails with clear error
- If suffix detection succeeds, platform is used for filtering during version expansion

### Conflicts

#### `--platform` vs Version Suffix

```bash
# WRONG ERROR: Conflict
nu scripts/build.nu --service my-service --version v1.0.0-debian --platform alpine

# CORRECT CORRECT: Use one or the other
nu scripts/build.nu --service my-service --version v1.0.0-debian
nu scripts/build.nu --service my-service --version v1.0.0 --platform debian
```

## Matrix Generation

CI matrix output now includes `platform` field:

### Single-Platform

```json
{
  "include": [
    {
      "version": "v1.0.0",
      "platform": "", // Empty string for single-platform services
      "latest": true
    }
  ]
}
```

### Multi-Platform (Matrix Format)

```json
{
  "include": [
    {
      "version": "v1.0.0",
      "platform": "debian", // Platform name for multi-platform services
      "latest": true
    },
    {
      "version": "v1.0.0",
      "platform": "alpine", // Platform name for multi-platform services
      "latest": false
    }
  ]
}
```

### Platform Field Format

- Empty string (`""`) = single-platform service (no `platforms.nuon` exists)
- Non-empty string = multi-platform service, platform name to pass to `--platform` flag
- Never `null` - always a string (empty or platform name)

### Usage in GitHub Actions

```yaml
strategy:
  matrix: ${{ fromJson(needs.setup.outputs.matrix) }}
steps:
  - name: Build
    run: |
      if [ -z "${{ matrix.platform }}" ]; then
        # Single-platform: no --platform flag needed
        nu scripts/build.nu --service $SERVICE --version ${{ matrix.version }}
      else
        # Multi-platform: pass --platform flag
        nu scripts/build.nu --service $SERVICE --version ${{ matrix.version }} --platform ${{ matrix.platform }}
      fi
```

## Validation

### Platform Manifest Validation

```bash
nu scripts/build.nu --service my-service --version v1.0.0
```

Validates:

- Required fields: `default`, `platforms`
- Default platform exists in platforms list
- Platform names are unique
- Platform names match format rules
- Each platform has required `name` and `dockerfile` fields

### Version Manifest Validation (Two-Phase)

#### Phase 1: Base Names (Before Expansion)

- Version names don't end with platform suffixes
- No duplicate version names
- Only one version has `latest: true`
- Custom tags don't include version names or "latest"

#### Phase 2: Expanded Tags (After Expansion)

- Composite uniqueness: `{name, platform}` pairs are unique
- Tag uniqueness per platform
- No tag collisions within same platform

### Example Error

```text
Error: Version name 'v1.0.0-debian' ends with platform suffix '-debian'.
Version names should not include platform suffixes (they are added automatically during expansion)
```

## Migration Guide

### From Single-Platform to Multi-Platform

#### Step 1: Identify Platform-Specific Code

Review your Dockerfile for platform-specific logic:

- Base image selection
- Package manager commands (apt vs apk)
- File paths differences
- Runtime dependencies

#### Step 2: Create Platform Dockerfiles

Split your Dockerfile into platform-specific versions:

```text
Dockerfile          -> Dockerfile.debian
                    -> Dockerfile.alpine
```

#### Step 3: Create platforms.nuon

```nuon
{
  "default": "debian",  // Choose your primary platform
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "Dockerfile.debian"
    },
    {
      "name": "alpine",
      "dockerfile": "Dockerfile.alpine"
    }
  ]
}
```

#### Step 4: Extract Platform-Specific Config

Move platform-specific configuration from `services/{service-name}.nuon` to `platforms.nuon`:

#### Before (services/my-service.nuon)

```nuon
{
  "name": "my-service",
  "dockerfile": "Dockerfile",
  "build_args": {
    "BASE_IMAGE": "debian:12"  // Platform-specific
  }
}
```

#### After

##### services/my-service.nuon (base)

```nuon
{
  "name": "my-service"
  // Remove dockerfile - defined per-platform
  // Remove platform-specific build_args
}
```

#### platforms.nuon

```nuon
{
  "default": "debian",
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "Dockerfile.debian",
      "build_args": {
        "BASE_IMAGE": "debian:12"
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

#### Step 5: Test Both Platforms

```bash
# Test debian (default)
nu scripts/build.nu --service my-service --version v1.0.0 --platform debian

# Test alpine
nu scripts/build.nu --service my-service --version v1.0.0 --platform alpine

# Test full expansion
nu scripts/build.nu --service my-service --version v1.0.0
```

#### Step 6: Update Dependencies

If other services depend on yours, they'll automatically inherit the platform. Test dependent services to ensure they work with both platforms.

### Backward Compatibility

**Single-platform services work unchanged:**

- No platforms.nuon = single-platform behavior
- All existing commands work identically
- No migration required unless you want multi-platform support

## Breaking Changes

### Function Signatures

These functions have new signatures (for internal use only):

1. **`resolve-version-name`**: Returns `{base_name, detected_platform}` record
2. **`filter-versions`**: Returns `{versions, detected_platforms}` record
3. **`validate-version-manifest`**: Accepts optional `platforms` parameter
4. **Matrix generation**: Always includes `platform` field in output

### Matrix Format

#### Breaking Change

CI matrix now includes `platform` field in every entry.

##### Before (Matrix Format)

```json
{ "include": [{ "version": "v1.0.0", "latest": true }] }
```

##### After (Matrix Format)

```json
{ "include": [{ "version": "v1.0.0", "platform": "", "latest": true }] }
```

#### Migration

Update CI workflows to handle `platform` field:

- Empty string (`""`) = single-platform
- Non-empty = multi-platform, pass to `--platform` flag

## Best Practices

### Reducing Repetition

- Use `defaults` in `platforms.nuon` when multiple platforms share configuration
- Extract common values (external_images, dependencies, build_args) to defaults
- Keep platform-specific values (dockerfile, name) in individual platform configs
- Use `defaults` in `versions.nuon` when multiple versions share configuration

### 1. Choose Meaningful Platform Names

```nuon
// GOOD - Clear, descriptive
{ "name": "debian" }
{ "name": "alpine" }
{ "name": "ubuntu-jammy" }

// BAD - Too generic or confusing
{ "name": "base" }
{ "name": "v1" }
{ "name": "default" }
```

### 2. Keep Base Config Platform-Agnostic

Put only truly common configuration in `services/{service-name}.nuon`:

```nuon
// services/my-service.nuon - platform-agnostic
{
  "name": "my-service",
  "context": ".",
  "labels": {
    "app.name": "my-service"
  }
}

// platforms.nuon - platform-specific
{
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "Dockerfile.debian",  // Platform-specific
      "build_args": { ... }               // Platform-specific
    }
  ]
}
```

### 3. Test All Platforms

Always test all platforms before release:

```bash
# Test each platform individually
for platform in debian alpine; do
  nu scripts/build.nu --service my-service --version v1.0.0 --platform $platform
done

# Test full expansion
nu scripts/build.nu --service my-service --version v1.0.0
```

### 4. Document Platform Differences

Add comments to your platforms.nuon explaining why each platform exists:

```nuon
{
  "default": "debian",
  "platforms": [
    {
      // Standard Debian-based image for most deployments
      "name": "debian",
      "dockerfile": "Dockerfile.debian"
    },
    {
      // Minimal Alpine image for size-constrained environments
      "name": "alpine",
      "dockerfile": "Dockerfile.alpine"
    }
  ]
}
```

### 5. Use Default Platform for Production

The `default` platform gets the unprefixed `latest` tag, so choose your production platform as default:

```nuon
{
  "default": "debian",  // Production standard
  "platforms": [
    { "name": "debian", ... },    // Gets :latest
    { "name": "alpine", ... }     // Gets :latest-alpine
  ]
}
```

## Troubleshooting

### Error: "Version name ends with platform suffix"

#### Problem: Version Name Ends with Platform Suffix

```text
Error: Version name 'v1.0.0-debian' ends with platform suffix '-debian'.
```

**Solution:** Version names should not include platform suffixes. Use plain names:

```nuon
// WRONG
{ "name": "v1.0.0-debian" }

// CORRECT
{ "name": "v1.0.0" }
```

The platform suffix is added automatically during expansion.

### Error: "Platform not found in manifest"

#### Problem: Platform Not Found in Manifest

```bash
nu scripts/build.nu --service my-service --version v1.0.0-alpine
# Error: Platform 'alpine' not found in platforms manifest
```

**Solution:** The platform doesn't exist in your platforms.nuon. Either:

1. Add the platform to platforms.nuon
2. Remove the suffix: `--version v1.0.0`
3. Check for typos in platform name

### Error: "Multi-platform service depends on single-platform"

#### Problem: Multi-Platform Depends on Single-Platform

```text
Error: Service 'app' (multi-platform) depends on 'lib' (single-platform).
```

#### Solution

Choose one:

1. **Add platforms.nuon to dependency:**

   Create platforms.nuon for the dependency service.

2. **Use explicit platform suffix:**

   ```nuon
   {
     "dependencies": {
       "lib": {
         "version": "v1.0.0-debian",
         "build_arg": "LIB_IMAGE"
       }
     }
   }
   ```

### Warning: "Base config has platform-specific fields"

#### Problem: Base Config Has Platform-Specific Fields

```text
Warning: Base config has 'build_args' field but platforms manifest exists.
Consider moving to platform-specific config in platforms.nuon
```

**Solution:** This is just a suggestion for better organization. Move platform-specific config to platforms.nuon:

```text
// Move FROM services/{service-name}.nuon TO platforms.nuon
"build_args": { ... }
"external_images": { ... }
"sources": { ... }
"dependencies": { ... }
"labels": { ... }
```

## Examples

### Example 1: Simple Multi-Platform Service

#### services/nginx/nginx.nuon

```nuon
{
  "name": "nginx",
  "context": "services/nginx"
}
```

#### services/nginx/platforms.nuon

```nuon
{
  "default": "debian",
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "Dockerfile.debian",
      "build_args": {
        "BASE_IMAGE": "debian:12-slim"
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

#### Build Commands

```bash
# All platforms
nu scripts/build.nu --service nginx --version v1.0.0

# Debian only
nu scripts/build.nu --service nginx --version v1.0.0 --platform debian

# Alpine with custom tag
nu scripts/build.nu --service nginx --version v1.0.0-alpine
```

### Example 2: Platform-Specific Dependencies

#### services/app/platforms.nuon (Example 2)

```nuon
{
  "default": "debian",
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "Dockerfile.debian",
      "dependencies": {
        "common_lib": {
          "version": "v1.0.0-debian",
          "build_arg": "COMMON_LIB_IMAGE"
        }
      }
    },
    {
      "name": "alpine",
      "dockerfile": "Dockerfile.alpine",
      "dependencies": {
        "common_lib": {
          "version": "v1.0.0-alpine",
          "build_arg": "COMMON_LIB_IMAGE"
        }
      }
    }
  ]
}
```

### Example 3: Version-Specific Platform Overrides

#### services/api/versions.nuon

```nuon
{
  "default": "v2.0.0",
  "versions": [
    {
      "name": "v2.0.0",
      "latest": true,
      // v2 uses different args per platform
      "platforms": {
        "debian": {
          "build_args": {
            "FEATURE_FLAG": "enabled"
          }
        },
        "alpine": {
          "build_args": {
            "FEATURE_FLAG": "disabled"  // Not supported on alpine yet
          }
        }
      }
    },
    {
      "name": "v1.0.0"
      // v1 uses same config for all platforms
    }
  ]
}
```

### Example 4: Complex Multi-Platform with Version-Specific Dependencies

#### Use Case

Service with multiple versions, each requiring different dependency versions per platform.

#### services/app/app.nuon

```nuon
{
  "name": "app",
  "context": "services/app",
  "dependencies": {
    "base-service": {
      "build_arg": "BASE_SERVICE_IMAGE"
      // Version inherited from parent or specified in overrides
    },
    "common-tools": {
      "build_arg": "COMMON_TOOLS_IMAGE"
    }
  }
}
```

#### services/app/platforms.nuon (Example 4)

```nuon
{
  "default": "debian",
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "Dockerfile.debian"
    },
    {
      "name": "alpine",
      "dockerfile": "Dockerfile.alpine"
    }
  ]
}
```

#### services/app/versions.nuon (Example 4)

```nuon
{
  "default": "v2.0.0",
  "versions": [
    {
      "name": "v2.0.0",
      "latest": true,
      "overrides": {
        // Global: applies to all platforms
        "sources": {
          "app": {"ref": "v2.0.0"}
        },
        // Platform-specific: different dependencies per platform
        "platforms": {
          "debian": {
            "dependencies": {
              "base-service": {
                "version": "v2.0.0-debian",  // Explicit platform-specific version
                "build_arg": "BASE_SERVICE_IMAGE"
              },
              "common-tools": {
                "version": "v1.5.0-debian",  // Different version for debian
                "build_arg": "COMMON_TOOLS_IMAGE"
              }
            }
          },
          "alpine": {
            "dependencies": {
              "base-service": {
                "version": "v2.0.0-alpine",  // Explicit platform-specific version
                "build_arg": "BASE_SERVICE_IMAGE"
              },
              "common-tools": {
                // No explicit version - inherits v2.0.0 from parent and platform from build
                "build_arg": "COMMON_TOOLS_IMAGE"
              }
            }
          }
        }
      }
    },
    {
      "name": "v1.0.0",
      "overrides": {
        "sources": {
          "app": {"ref": "v1.0.0"}
        },
        // v1.0.0 uses same dependencies for all platforms
        "dependencies": {
          "base-service": {
            "version": "v1.0.0",  // Inherits platform automatically
            "build_arg": "BASE_SERVICE_IMAGE"
          }
        }
      }
    }
  ]
}
```

**Build behavior:**

- Building `v2.0.0-debian`: Uses `base-service:v2.0.0-debian` and `common-tools:v1.5.0-debian`
- Building `v2.0.0-alpine`: Uses `base-service:v2.0.0-alpine` and `common-tools:v2.0.0-alpine` (inherited)
- Building `v1.0.0-debian`: Uses `base-service:v1.0.0-debian` (inherits platform)
- Building `v1.0.0-alpine`: Uses `base-service:v1.0.0-alpine` (inherits platform)

## See Also

- [Platform Manifest Schema Reference](../reference/platform-manifest-schema.md) - Complete schema documentation
- [Build System](../concepts/build-system.md) - Configuration merging and tag generation
- [Multi-Version Builds Guide](multi-version-builds.md) - Version management with platforms
- [CLI Reference](../reference/cli-reference.md) - Complete CLI documentation
- [Schema Files](../../schemas/platforms.nuon) - Authoritative schema definition
