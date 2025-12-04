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
# CLI Reference

## Overview

Complete reference for all CLI commands and flags used in the DockyPody build system.

## Build Command

```bash
nu scripts/build.nu --service <service-name> [options]
```

## Service Selection Flags

### `--service <string>` (default: "cernbox-web")

Build a specific service:

```bash
nu scripts/build.nu --service revad-base
```

### `--all-services`

Build all discovered services in dependency order:

```bash
nu scripts/build.nu --all-services
```

Discovers all services in the `services/` directory, resolves dependencies, computes the global build order, and builds all services in topological order.

**Flag Conflicts:**

- Mutually exclusive with `--service` (explicit service selection)
- Mutually exclusive with `--version` (use `--latest-only` or `--all-versions` instead)
- Mutually exclusive with `--versions` (use `--latest-only` or `--all-versions` instead)

**Compatible with:**

- `--all-versions` - Build all versions of all services
- `--latest-only` - Build only latest versions of all services
- `--platform` - Filter builds to a specific platform (skips services without that platform)
- `--push`, `--latest`, `--extra-tag` - Apply to all target services
- `--push-deps`, `--tag-deps` - Apply to dependencies of all services
- `--cache-bust`, `--no-cache` - Apply to all services
- `--fail-fast` - Stop on first failure
- `--show-build-order` - Show merged build order and exit
- `--matrix-json` - Generate CI matrix for all services (respects version and platform flags)

**Behavior:**

- Services without version manifests are skipped with a warning
- Services without the specified `--platform` are skipped
- Default version is built unless `--all-versions` or `--latest-only` is specified
- Dependency graph is constructed per-service and merged with deduplication
- Continue-on-failure is default (use `--fail-fast` to stop on first error)

**Examples:**

```bash
# Build all services with default versions
nu scripts/build.nu --all-services

# Build all services, all versions
nu scripts/build.nu --all-services --all-versions

# Build only latest versions of all services
nu scripts/build.nu --all-services --latest-only

# Build all services for debian platform only
nu scripts/build.nu --all-services --platform debian

# Generate CI matrix for all services
nu scripts/build.nu --all-services --matrix-json

# Show build order without building
nu scripts/build.nu --all-services --show-build-order
```

## Version Flags

### `--version <string>`

Build a specific version from the manifest:

```bash
nu scripts/build.nu --service revad-base --version v3.3.3
```

### `--all-versions`

Build all versions defined in the manifest:

```bash
nu scripts/build.nu --service revad-base --all-versions
```

### `--latest-only`

Build only versions marked with `latest: true`:

```bash
nu scripts/build.nu --service revad-base --latest-only
```

### `--versions <string>`

Build multiple specific versions (comma-separated list):

```bash
nu scripts/build.nu --service revad-base --versions v1.29.0,v1.28.0
```

**Note:** `--version` (singular) for single version, `--versions` (plural) for multiple versions.

## Platform Flags

### `--platform <string>`

Filter builds to a specific platform (requires `platforms.nuon`):

```bash
# Build only debian variant
nu scripts/build.nu --service my-service --version v1.0.0 --platform debian

# Build all debian versions
nu scripts/build.nu --service my-service --all-versions --platform debian
```

### Platform Suffix in Version

You can specify platforms inline with version names:

```bash
# Build only v1.0.0-debian
nu scripts/build.nu --service my-service --version v1.0.0-debian

# Build multiple platform-specific versions
nu scripts/build.nu --service my-service --versions "v1.0.0-debian,v1.0.0-alpine"
```

**Rules:**

- Suffix format: `-<platform-name>`
- Suffix must match a platform in `platforms.nuon`
- Cannot have double dashes: `v1.0.0--debian` is invalid
- Cannot end with dash: `v1.0.0-` is invalid

**Conflicts:**

- ERROR: `--version v1.0.0-debian --platform alpine` (conflict)
- CORRECT: Use one or the other

## CI Matrix Generation

### `--matrix-json`

Output GitHub Actions matrix JSON:

```bash
nu scripts/build.nu --service revad-base --matrix-json
```

**Output format:**

#### Single-Platform

```json
{
  "include": [
    {
      "version": "v1.0.0",
      "platform": "",
      "latest": true
    }
  ]
}
```

#### Multi-Platform

```json
{
  "include": [
    {
      "version": "v1.0.0",
      "platform": "debian",
      "latest": true
    },
    {
      "version": "v1.0.0",
      "platform": "alpine",
      "latest": false
    }
  ]
}
```

**Platform Field:**

- Empty string (`""`) = single-platform service (no `platforms.nuon` exists)
- Non-empty string = multi-platform service, platform name to pass to `--platform` flag
- Never `null` - always a string (empty or platform name)

## Cache Busting Flags

### `--cache-bust <string>`

Override cache busting for all services in the build with a custom value:

```bash
# Use custom cache bust value for all services
nu scripts/build.nu --service cernbox-web --cache-bust "abc123"
```

When set, this value applies to:

- Target service
- All dependencies (if auto-build enabled)
- All services in multi-version builds

**Default behavior:** Each service uses its own source refs hash (computed from service's sources), or Git SHA if no sources, or "local" if no Git.

### `--no-cache`

Force cache invalidation by generating a random UUID for all services:

```bash
# Force rebuild of all services (no cache)
nu scripts/build.nu --service cernbox-web --no-cache
```

This is equivalent to `--cache-bust <random-uuid>` but more convenient for forcing full rebuilds.

**Note:** Cache busting is per-service by default. Use these flags for global overrides.

## Dependency Building Flags

### `--dep-cache <string>`

Control dependency reuse behavior for CI builds:

```bash
# Disable hash-based skip (always build deps)
nu scripts/build.nu --service cernbox-web --dep-cache=off

# Hash-based skip + auto-build on missing/stale (default for CI)
nu scripts/build.nu --service cernbox-web --dep-cache=soft

# Strict validation, fail on missing/stale (no auto-build)
nu scripts/build.nu --service cernbox-web --dep-cache=strict
```

**Modes:**

| Mode | Behavior | Use Case |
|------|----------|----------|
| `off` | Always build deps, no hash skip | Local development, forced rebuilds |
| `soft` | Hash-based skip + auto-build on missing/stale | Default for CI workflows |
| `strict` | Hash validation, fail on missing/stale | Explicit dependency control |

**Defaults:**

- Local builds: `off` (always build, rely on Docker layer cache)
- CI builds: `soft` (hash-based skip + auto-build)

**Use cases:**

- `--dep-cache=off`: Force rebuild of all dependencies
- `--dep-cache=soft`: Standard CI workflow with cache reuse
- `--dep-cache=strict`: CI/CD scenarios where dependencies must be pre-built

### `--push-deps`

Push dependencies to registry (independent of `--push` flag):

```bash
# Push dependencies but not target service
nu scripts/build.nu --service cernbox-web --push-deps

# Push both dependencies and target service
nu scripts/build.nu --service cernbox-web --push --push-deps
```

**Behavior:**

- Only affects dependencies (not target service)
- Independent of `--push` flag
- Can be used with or without `--push`

### `--tag-deps`

Tag dependencies with `--latest` and/or `--extra-tag` (independent of target service tags):

```bash
# Tag dependencies as latest
nu scripts/build.nu --service cernbox-web --latest --tag-deps

# Tag dependencies with custom tag
nu scripts/build.nu --service cernbox-web --extra-tag stable --tag-deps

# Tag both dependencies and target
nu scripts/build.nu --service cernbox-web --latest --tag-deps
```

**Behavior:**

- Propagates both `--latest` and `--extra-tag` flags to dependencies
- Independent of target service tags
- The tagging system checks each dependency's version manifest to determine if tags are actually applied
- If a dependency's version manifest doesn't allow a tag (e.g., `latest: false`), the tag is not applied even if the flag is propagated
- Example: If `--tag-deps --latest` is used, but a dependency's version has `latest: false`, the `latest` tag is not applied to that dependency

## Build Control Flags

### `--show-build-order`

Display the dependency build order without actually building:

```bash
# Show build order for service (default version)
nu scripts/build.nu --service cernbox-web --show-build-order

# Show build order for specific version
nu scripts/build.nu --service cernbox-web --show-build-order --version v1.0.0

# Show build order for all versions
nu scripts/build.nu --service cernbox-web --show-build-order --all-versions

# Show build order for specific versions
nu scripts/build.nu --service cernbox-web --show-build-order --versions v1.0.0,v1.1.0

# Show build order for latest versions only
nu scripts/build.nu --service cernbox-web --show-build-order --latest-only
```

**Single-Version Output Format:**

```text
=== Build Order ===

1. revad-base:v3.3.3
2. cernbox-revad:v1.0.0
3. cernbox-web:v1.0.0
```

**Multi-Version Output Format:**

```text
=== Build Order ===

Version: v1.0.0
1. revad-base:v3.3.3
2. cernbox-revad:v1.0.0
3. cernbox-web:v1.0.0

Version: v1.1.0
1. revad-base:v3.3.3
2. cernbox-revad:v1.1.0
3. cernbox-web:v1.1.0
```

**Multi-Platform Output Format:**

For multi-platform services, each version/platform combination is displayed separately:

```text
=== Build Order ===

Version: v1.0.0 (production)
1. revad-base:v3.3.3:production
2. cernbox-revad:v1.0.0:production
3. cernbox-web:v1.0.0:production

Version: v1.0.0 (development)
1. revad-base:v3.3.3:development
2. cernbox-revad:v1.0.0:development
3. cernbox-web:v1.0.0:development
```

**Multi-Version Flags:**

- `--all-versions` - Show build order for all versions in the manifest
- `--versions <list>` - Show build order for specific versions (comma-separated)
- `--latest-only` - Show build order for versions marked `latest: true`
- `--platform <string>` - Filter to specific platform (multi-platform services only)

**Use cases:**

- Debugging dependency resolution
- Understanding build order before building
- Verifying dependency graph construction
- Auditing dependency chains across multiple versions
- Previewing build order for release planning

### `--fail-fast`

Break on first failure (only applies to multi-version builds):

```bash
# Build all versions, stop on first failure
nu scripts/build.nu --service revad-base --all-versions --fail-fast
```

**Default behavior:**

- **Single service builds:** Always fail fast (errors propagate immediately, no summary generated)
- **Multi-version builds (with or without platforms):** Continue-on-failure by default (collect all failures, report summary)
- **Dependency build failures:** Always fail fast (regardless of `--fail-fast` flag) - build stops immediately with error message

**Note:** The `--fail-fast` flag only applies to multi-version builds of the target service. Dependency build failures always cause immediate stop regardless of this flag.

**Use cases:**

- CI/CD scenarios where you want to stop immediately on failure
- Debugging specific version build issues

## Other Build Flags

### `--push`

Push built images to registry:

```bash
nu scripts/build.nu --service revad-base --version v3.3.3 --push
```

### `--progress <string>`

Set build progress output format:

```bash
nu scripts/build.nu --service revad-base --all-versions --progress plain
```

### `--latest <boolean>`

Control latest tag generation:

```bash
nu scripts/build.nu --service revad-base --version v1.28.0 --latest false
```

## Disk Management Flags

### `--disk-monitor <string>`

Control disk monitoring output during builds:

```bash
# Enable basic disk monitoring
nu scripts/build.nu --service cernbox-web --all-versions --disk-monitor=basic

# Default: monitoring disabled
nu scripts/build.nu --service cernbox-web --all-versions --disk-monitor=off
```

**Modes:**

| Mode | Behavior |
|------|----------|
| `off` | No monitoring (default for local builds) |
| `basic` | Emit disk usage snapshots at build phases |

**CI Default:** `basic` (enabled for all services in generated workflows)

### `--prune-cache-mounts`

Prune BuildKit cache between version builds:

```bash
# Enable cache pruning
nu scripts/build.nu --service cernbox-web --all-versions --prune-cache-mounts

# Default: pruning disabled (local builds)
nu scripts/build.nu --service cernbox-web --all-versions
```

**Behavior:**

- Runs `docker builder prune -f` after each version build (clears all BuildKit cache)
- Only affects multi-version builds (single-version builds have no intermediate phases)
- Preserves Docker image cache (only prunes build-time cache, not final images)
- Shows disk usage after prune to confirm the effect
- Non-fatal: failures are logged as warnings and builds continue

**What gets pruned:**

- Intermediate build layers
- Exec cache mounts (`RUN --mount=type=cache` entries)
- Source cache
- Build context cache

**What is preserved:**

- Final Docker images
- Docker layer cache for images

**Use cases:**

- CI environments with limited disk space
- Multi-version builds where build cache accumulates (e.g., `cernbox-web` with 8+ versions)
- Investigating disk exhaustion issues

**CI Default:** Enabled for all services in generated workflows (`prune_build_cache: true`)

**Local Usage:** Typically not needed (persistent Docker cache is beneficial). Enable manually when simulating CI behavior or debugging disk issues.

## See Also

- [Multi-Version Builds Guide](../guides/multi-version-builds.md) - Complete version management guide
- [Multi-Platform Builds Guide](../guides/multi-platform-builds.md) - Complete platform management guide
- [Build System](../concepts/build-system.md) - Build system architecture
