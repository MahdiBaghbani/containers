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

# Dependency Management

## Overview

Dependency management handles how services depend on other services, how versions are resolved, and how dependency images are located and validated. **By default, missing dependencies are automatically built.** This document explains the dependency resolution system and auto-build behavior. For examples of services with dependencies, see the [Service Setup Guide](../guides/service-setup.md).

## Dependency Declaration

Dependencies are declared in the `dependencies` section of service configs:

### Simple Case: Dependency key matches service name

```nuon
{
  "dependencies": {
    "revad-base": {
      "version": "v3.3.3",  // Optional: explicit version pin
      "build_arg": "REVAD_BASE_IMAGE"  // Required: build argument name
    }
  }
}
```

### Advanced Case: Multiple dependencies from same service with different versions

This pattern is useful when you need different platform variants (e.g., debian vs alpine) of the same service in a single build:

```nuon
{
  "dependencies": {
    "common-tools-builder": {
      "service": "common-tools",  // Optional: service name (defaults to dependency key if omitted)
      "version": "v1.0.0-debian",  // Different version/platform variant
      "build_arg": "COMMON_TOOLS_BUILDER_IMAGE"  // Required: must be unique
    },
    "common-tools-runtime": {
      "service": "common-tools",  // Same service, different version
      "version": "v1.0.0-alpine",  // Different platform variant
      "build_arg": "COMMON_TOOLS_RUNTIME_IMAGE"  // Required: must be unique
    }
  }
}
```

### Key Points

- Dependencies are **internal services** only (built within this repo)
- External base images go in `external_images` section (for build/runtime stages)
- **Dependency keys are identifiers** - they can be any name and don't need to match the service name
- **`service` field is optional** - if omitted, the dependency key is used as the service name
- **Multiple dependencies can reference the same service** with different versions/platform variants
- Each dependency maps to a specific build argument in the Dockerfile
- **`build_arg` must be unique** across all dependencies in a service config
- `version` is optional - if omitted, version is auto-resolved (see Version Resolution)

## Build Argument Mapping

Dependencies are injected as build arguments with explicit names:

- Dependency key: `revad-base` -> Build arg: `REVAD_BASE_IMAGE`
- Dependency key: `common-tools-builder` -> Build arg: `COMMON_TOOLS_BUILDER_IMAGE`
- This allows multiple dependencies with clear, descriptive names, even when they reference the same service

## Dockerfile Requirements

Dockerfiles must declare the build arg with a sensible default:

```dockerfile
ARG REVAD_BASE_IMAGE="revad-base:latest"
FROM ${REVAD_BASE_IMAGE}
```

### Default value serves as fallback

- Works when building Dockerfile directly (without build script)
- Will be overridden by build script during automated builds

## Version Resolution

### Service Version Resolution

The service's version is determined by the **version manifest** (required):

1. **`--version` CLI flag** - Use specific version from manifest
2. **Manifest `default` field** - If no --version specified
3. **Error if not found** - Build fails if version not in manifest

### Dependency Version Resolution

Dependencies resolve their version in this priority order:

1. **Explicit version** in dependency config: `"version": "v3.3.3"` -> always use this
   - If explicit version includes platform suffix (e.g., `"v1.0.0-debian"`), it's used as-is
   - If explicit version lacks platform suffix and parent is multi-platform, platform is inherited (see Platform Inheritance below)
2. **Parent service version**: Inherit from parent if no explicit version (with platform inheritance for multi-platform services)
   - Base version name is inherited (e.g., `v3.3.3`)
   - Platform suffix is automatically inherited if parent is multi-platform
3. **Error**: If no version can be determined, build fails with clear error message

## Platform Inheritance

**When a multi-platform service depends on another service, the dependency automatically inherits the parent's platform.**

### How It Works

1. **Parent is multi-platform** (has `platforms.nuon`)
2. **Dependency version resolution:**
   - If explicit version has platform suffix: Use as-is (e.g., `"version": "v1.0.0-debian"`)
   - If explicit version lacks platform suffix: Inherit platform from parent (e.g., `"version": "v1.0.0"` + parent platform `debian` -> `v1.0.0-debian`)
   - If no explicit version: Inherit both version and platform from parent

### Examples

#### Example 1: Platform inheritance with explicit version (no suffix)

```nuon
// Parent: multi-platform service building "v2.0.0-debian"
{
  "dependencies": {
    "base-service": {
      "version": "v1.0.0",  // No platform suffix
      "build_arg": "BASE_SERVICE_IMAGE"
    }
  }
}
```

Result: `base-service:v1.0.0-debian` (platform inherited from parent)

#### Example 2: Platform inheritance without explicit version

```nuon
// Parent: multi-platform service building "v2.0.0-debian"
{
  "dependencies": {
    "base-service": {
      // No version specified
      "build_arg": "BASE_SERVICE_IMAGE"
    }
  }
}
```

Result: `base-service:v2.0.0-debian` (both version and platform inherited)

#### Example 3: Explicit version with platform suffix (no inheritance)

```nuon
{
  "dependencies": {
    "base-service": {
      "version": "v1.0.0-debian",  // Explicit suffix
      "build_arg": "BASE_SERVICE_IMAGE"
    }
  }
}
```

Result: `base-service:v1.0.0-debian` (used as-is, no inheritance)

### Warnings and Errors

#### Warning: If explicit version lacks platform suffix and parent is multi-platform

```text
Warning: Dependency 'dep-key' version 'v1.0.0' lacks platform suffix, inheriting 'debian' from parent
```

#### Info: If dependency doesn't support platforms (no `platforms.nuon`) but parent is multi-platform

```text
Info: Multi-platform service depends on single-platform service 'base-service'.
Dependency 'base-service' will use version 'v1.0.0' for all platforms.
If this is intentional, consider adding 'single_platform: true' to suppress this message.
```

**Note:** Single-platform dependencies are now allowed. The same dependency version will be used for all parent platforms. If this is intentional, add `single_platform: true` to suppress the informational message.

#### Solutions

1. Add `single_platform: true` to suppress the informational message (recommended if intentional)
2. Create `platforms.nuon` for the dependency to make it multi-platform, OR
3. Use explicit version with platform suffix: `"version": "v1.0.0-debian"` (if dependency has platforms)

For complete details on multi-platform builds and platform inheritance, see the [Multi-Platform Builds Guide](../guides/multi-platform-builds.md).

**Note:** Dependencies do not fall back to their own manifest's default version. They must either have an explicit version or inherit from the parent service version.

## Single-Platform Dependencies

When a multi-platform service depends on a single-platform service (a service without `platforms.nuon`), the dependency can be used across all parent platforms. This is useful when the dependency's binaries are compatible with all platforms of the parent service.

### The `single_platform` Flag

To explicitly mark a dependency as single-platform and suppress the informational message, use the `single_platform: true` flag:

```nuon
// versions.nuon overrides
{
  "dependencies": {
    "gaia": {
      "version": "master",
      "single_platform": true  // Suppresses informational message
    }
  }
}
```

### Behavior

1. **Without `single_platform` flag**: Single-platform dependencies are allowed with an informational message
2. **With `single_platform: true`**: No informational message is shown (intent is explicit)
3. **Platform suffix precedence**: If a version has a platform suffix (e.g., `"v1.0.0-debian"`), it takes precedence over `single_platform: true` (with a warning)

### Examples

#### Example 1: Single-platform dependency without flag

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

Result: `gaia:master` used for both `production` and `development` platforms
Message: `Info: Multi-platform service depends on single-platform service 'gaia'...`

#### Example 2: Single-platform dependency with flag

```nuon
{
  "dependencies": {
    "gaia": {
      "version": "master",
      "single_platform": true
    }
  }
}
```

Result: `gaia:master` used for both platforms, no message

#### Example 3: Conflicting config (platform suffix + flag)

```nuon
{
  "dependencies": {
    "base-service": {
      "version": "v1.0.0-debian",  // Has platform suffix
      "single_platform": true        // Flag is ignored
    }
  }
}
```

Result: `base-service:v1.0.0-debian` (suffix takes precedence)
Message: `Warning: Dependency has both platform suffix... and single_platform: true. Platform suffix takes precedence...`

### Image Reference Construction

#### Local Builds

- Format: `{service}:{tag}`
- Example: `revad-base:v3.3.3`

#### CI Builds

- Format: `{registry}/{path}/{service}:{tag}`
- Example: `ghcr.io/open-cloud-mesh/containers/revad-base:v3.3.3`
- Both GHCR and Forgejo registries are used

## Dependency Existence Check

Before building, the system checks if dependency images exist:

### Local Builds (Existence Check)

- Checks local Docker images using: `docker images --format "{{.Repository}}:{{.Tag}}"` and filters for exact match
- Checks for exact tag match: `{service}:{tag}` (e.g., `revad-base:v3.3.3`)
- **Important limitations:**
  - Does NOT check image digests (e.g., `revad-base@sha256:...`)
  - Does NOT check alternative tags (e.g., if `revad-base:latest` points to `v3.3.3`, it still won't match)
  - Only exact tag match is verified: `{service}:{exact-tag}`
- **Rationale:** Exact tag matching ensures reproducible builds and prevents accidental use of wrong images. Digests and alternative tags are not checked to keep the system simple and predictable.
- Fails with error if missing

### CI Builds (Existence Check)

- Assumes dependencies are pre-built (earlier in workflow)
- Checks remote registries via `docker manifest inspect {full-registry-path}`
- Full registry path format: `{registry}/{path}/{service}:{tag}` (e.g., `ghcr.io/open-cloud-mesh/containers/revad-base:v3.3.3`)
- **Important:** Checks for exact tag match in remote registry, not digests or alternative tags
- Fails with error if missing

### Error Message

```text
Error: Dependency image 'revad-base:v3.3.3' not found.
Please build it first: nu scripts/dockypody.nu build --service revad-base --version v3.3.3
```

**Note:** For local builds, the check verifies the image exists in the local Docker daemon before proceeding. For CI builds, the check verifies the image exists in the remote registry. In both cases, only exact tag matches are checked - digests and alternative tags are not considered.

**Note:** When auto-build is enabled (default), existence checks are bypassed. The build system attempts to build missing dependencies instead of failing. If a dependency build fails, the build stops immediately (fail fast) with an error message indicating which dependency failed and which service was being built.

## Automatic Dependency Building

### Default Behavior

By default, the build system automatically builds missing dependencies:

1. **Dependency graph construction:** Builds version-aware dependency graph
2. **Topological sort:** Determines build order
3. **Sequential building:** Builds each dependency in order
4. **Docker caching:** If dependency image exists, Docker uses it (no rebuild)

### CI-Only Hash-Based Reuse

In CI builds, the build system uses service definition hashes to determine whether dependencies need rebuilding:

1. **Hash computation:** Before building, compute hashes for all nodes in the build graph
2. **Local image inspection:** For each dependency, check if a local image exists with the expected hash label
3. **Skip or rebuild:**
   - **Hash matches:** Skip the dependency build (image is valid)
   - **Hash missing/mismatched:** Image is stale, rebuild is needed

The service definition hash captures all inputs that affect the image: Dockerfile contents, sources, external images, build args, TLS config, and direct dependency hashes. See [Build System - Service Definition Hash](build-system.md#service-definition-hash) for details.

**Local builds** do not use hash-based skipping. They always proceed to `docker build` and rely on Docker's layer cache.

### Dep-Cache Modes

The `--dep-cache` flag controls CI dependency reuse behavior:

| Mode | Flag | Missing/Stale Deps | Use Case |
|------|------|-------------------|----------|
| Off | `--dep-cache=off` | Always build (no hash skip) | Forced rebuilds |
| Soft (default for CI) | `--dep-cache=soft` | Auto-build with warning | Standard CI workflows |
| Strict | `--dep-cache=strict` | Fail with error | Explicit dependency control |

**Off mode** (`--dep-cache=off`): Disables hash-based skipping. Dependencies are always built. This is the default for local builds.

**Soft mode** (`--dep-cache=soft`): If a dependency image is missing or has a stale hash, the build system auto-builds it with a warning message. This ensures builds complete even when cache restoration is incomplete. This is the default for CI builds.

**Strict mode** (`--dep-cache=strict`): If a dependency image is missing or has a stale hash, the build fails with an error. Use this when you require explicit control over dependency builds or want to fail fast on cache misses.

### Hash Label Requirement

Internal dependency images must have the `org.opencloudmesh.system.service-def-hash` label to be considered valid in CI. Images without this label (e.g., images built before this feature) are treated as stale and trigger a rebuild (soft mode) or error (strict mode).

### Disable Auto-Build

Use `--dep-cache=strict` to disable auto-building and enforce strict validation:

```bash
nu scripts/dockypody.nu build --service cernbox-web --dep-cache=strict
```

**When strict mode is enabled:**

- Dependencies are validated via service definition hash
- Build fails if dependencies are missing or have stale hashes

### Build Order Display

When auto-building, the build order is displayed:

```text
=== Building Dependencies ===
Build order:
  1. revad-base:v3.3.3
  2. cernbox-revad:v1.0.0
```

### Recursive Dependencies

Auto-build handles recursive dependencies:

- Only builds needed version x platform (not all versions)
- Recursively builds dependencies of dependencies
- Stops at existing images (Docker handles caching)

### Version and Platform Selection

For each dependency:

- Only the needed version is built (from dependency declaration)
- Only the needed platform is built (platform inheritance applied)
- Not all versions/platforms are built (efficient)

**Example:**

- Building `cernbox-web:v1.0.0-debian` requires `revad-base:v3.3.3-debian`
- Only `revad-base:v3.3.3-debian` is built (not `v3.3.3-alpine` or other versions)

## Version Resolution Examples

| Parent Version           | Dependency Config                    | Resolved Dependency        | Reason                                |
| ------------------------ | ------------------------------------ | -------------------------- | ------------------------------------- |
| `v3.3.3` (from manifest) | Explicit: `version: "v3.3.3"`        | `revad-base:v3.3.3`        | Explicit version always wins          |
| `v3.3.3` (from manifest) | Not specified                        | `revad-base:v3.3.3`        | Inherits from parent version          |
| `v2.0.0` (from manifest) | Not specified                        | `revad-base:v2.0.0`        | Inherits from parent version          |
| Any                      | Explicit: `version: "v1.0.0-debian"` | `revad-base:v1.0.0-debian` | Explicit version with platform suffix |
| Any                      | Not specified, no parent version     | **Error**                  | No version can be determined          |

### Complex Example: Multi-Platform Service with Dependency Chain

#### Scenario

Service `app` (multi-platform: debian, alpine) depends on `base-service` (multi-platform) and `common-tools` (single-platform).

#### services/app/app.nuon

```nuon
{
  "name": "app",
  "dependencies": {
    "base-service": {
      "build_arg": "BASE_SERVICE_IMAGE"
      // Inherits version and platform from parent
    },
    "common-tools": {
      "version": "v1.0.0-debian",  // Explicit platform suffix required (single-platform dependency)
      "build_arg": "COMMON_TOOLS_IMAGE"
    }
  }
}
```

#### Resolution

- Building `app:v2.0.0-debian`:
  - `base-service` resolves to `base-service:v2.0.0-debian` (inherits version + platform)
  - `common-tools` resolves to `common-tools:v1.0.0-debian` (explicit version with suffix)
- Building `app:v2.0.0-alpine`:
  - `base-service` resolves to `base-service:v2.0.0-alpine` (inherits version + platform)
  - `common-tools` resolves to `common-tools:v1.0.0-debian` (explicit version, no platform inheritance)

**Note:** Since `common-tools` is single-platform, it cannot inherit the platform from `app`. You must either:

1. Specify explicit platform suffix: `"version": "v1.0.0-debian"`
2. Create `platforms.nuon` for `common-tools` to make it multi-platform

## Troubleshooting

### Error: "Dependency image not found"

#### Problem: Dependency Image Not Found

```text
Error: Dependency image 'revad-base:v3.3.3' not found.
Please build it first: nu scripts/dockypody.nu build --service revad-base --version v3.3.3
```

#### Solution: Build Dependency First

Build the dependency service first:

```bash
# Build the dependency
nu scripts/dockypody.nu build --service revad-base --version v3.3.3

# Then build the dependent service
nu scripts/dockypody.nu build --service my-service --version v1.0.0
```

#### For Multi-Platform Builds

```text
Error: Dependency image 'revad-base:v3.3.3-debian' not found for platform 'debian'.
Please build it first: nu scripts/dockypody.nu build --service revad-base --version v3.3.3-debian
```

#### Solution: Build Dependency for Platform

Build the dependency for the specific platform:

```bash
# Build dependency for the platform
nu scripts/dockypody.nu build --service revad-base --version v3.3.3 --platform debian

# Or build all platforms
nu scripts/dockypody.nu build --service revad-base --version v3.3.3
```

### Error: "Multi-platform service depends on single-platform service"

#### Problem: Multi-Platform Depends on Single-Platform

```text
Error: Multi-platform service depends on single-platform service 'base-service'.
Dependency 'dep-key' cannot inherit platform 'debian'.
```

#### Solution: Create Platforms Manifest or Use Explicit Version

Choose one:

1. **Create platforms manifest for dependency:**

   ```bash
   # Create platforms.nuon for base-service
   services/base-service/platforms.nuon
   ```

2. **Use explicit version with platform suffix:**

   ```nuon
   {
     "dependencies": {
       "base-service": {
         "version": "v1.0.0-debian",  // Explicit platform suffix
         "build_arg": "BASE_SERVICE_IMAGE"
       }
     }
   }
   ```

### Error: "Dependency missing required field: 'build_arg'"

#### Problem: Missing build_arg Field

```text
Error: Dependency 'revad-base' missing required field: 'build_arg'
```

#### Solution: Add build_arg Field

Add the `build_arg` field to your dependency config:

```nuon
{
  "dependencies": {
    "revad-base": {
      "version": "v3.3.3",
      "build_arg": "REVAD_BASE_IMAGE"  // Required field
    }
  }
}
```

## See Also

- [Service Configuration](service-configuration.md) - How service configs are structured
- [Build System](build-system.md) - How build arguments are injected
- [Multi-Version Builds Guide](../guides/multi-version-builds.md) - Version manifest details
- [Multi-Platform Builds Guide](../guides/multi-platform-builds.md) - Platform inheritance details
- Implementation: `scripts/lib/dependencies.nu` - Dependency resolution logic
