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
# MERCHANTABILITY or FITNESS FOR A PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
-->

# Docker Buildx Guide

Quick reference for Docker Buildx features used in this project.

## Cache Mounts

This project uses Docker Buildx cache mounts to speed up builds by caching git clones, package downloads, and build artifacts.

### Pattern

Cache mounts use `CACHEBUST` in mount IDs to ensure cache invalidation when sources change:

```dockerfile
ARG CACHEBUST="default"
ARG SOURCE_REF="v3.3.3"
RUN --mount=type=cache,id=service-source-git-${CACHEBUST:-${SOURCE_REF}},target=/cache,sharing=shared \
    git clone --branch "${SOURCE_REF}" ${SOURCE_URL} /cache
```

**Key points:**

- `CACHEBUST` changes when source SHAs change (detects force-pushes)
- Nested syntax `${CACHEBUST:-${SOURCE_REF}}` provides fallback safety
- Build system ensures `CACHEBUST` is always non-empty
- Cache mount IDs change when sources change, forcing fresh clones

### Cache Sharing Modes

- `sharing=shared` - Multiple builds can read/write simultaneously (git clones, downloads)
- `sharing=locked` - Exclusive access (package manager caches, go mod)

## Cache Management

### View Cache Usage

```bash
# List all builders
docker buildx ls

# View detailed cache disk usage
docker buildx du

# View cache for default builder
docker buildx du --builder default
```

### Prune Cache

**Important:** `docker buildx prune` by default only removes **reclaimable** (dangling) cache entries. Caches still referenced by recent builds are kept even if older than the filter duration.

```bash
# Remove reclaimable caches only (safe, won't break builds)
docker buildx prune

# Remove ALL caches including non-reclaimable (more aggressive)
docker buildx prune --all

# Prune reclaimable caches older than specific duration
docker buildx prune --filter "until=168h"   # Reclaimable caches older than 7 days
docker buildx prune --filter "until=24h"    # Reclaimable caches older than 1 day

# Prune ALL caches older than duration (including non-reclaimable)
docker buildx prune --all --filter "until=168h"   # All caches older than 7 days
docker buildx prune --all --filter "until=24h"   # All caches older than 1 day

# Force prune without confirmation
docker buildx prune --all --filter "until=168h" --force

# Prune with disk space limits
docker buildx prune --max-used-space 10GB
docker buildx prune --min-free-space 5GB
```

**Duration formats:**

- `168h` - 168 hours (7 days)
- `720h` - 720 hours (30 days)
- `24h` - 24 hours (1 day)
- `30m` - 30 minutes
- `3600s` - 3600 seconds (1 hour)

**Note:** Docker Buildx only supports hours (`h`), minutes (`m`), and seconds (`s`) - not days (`d`). Convert days to hours: 7 days = 168h, 30 days = 720h.

**Cache retention:**

- Caches persist until manually pruned or garbage collected
- Automatic GC may remove unused caches after ~60 days
- Use `docker buildx prune --all --filter "until=168h"` weekly to free space (7 days = 168 hours)

**Why some old caches remain after pruning:**

- `docker buildx prune` (without `--all`) only removes **reclaimable** caches
- Caches still referenced by recent builds are kept (marked as non-reclaimable)
- Use `--all` flag to remove all caches older than the filter, including non-reclaimable ones
- Cache mounts (`--mount=type=cache`) may persist independently of layer cache pruning

## Buildx Builders

### List Builders

```bash
docker buildx ls
```

### Use Default Builder

Both dev and CI use the default Buildx builder with docker driver, which shares the Docker daemon's image store.

```bash
docker buildx use default
docker buildx inspect --bootstrap
```

## Multi-Stage Builds

Services use multi-stage builds to separate build and runtime environments:

```dockerfile
FROM golang:1.25 AS build
# Build stage with build tools

FROM debian:trixie-slim AS runtime
# Runtime stage with minimal dependencies
COPY --from=build /app /app
```

**Benefits:**

- Smaller final images (only runtime dependencies)
- Better security (fewer packages in runtime)
- Faster builds (build tools cached separately)

## Build Arguments

Build arguments are injected by the build system:

```dockerfile
ARG CACHEBUST="default"
ARG REVAD_REF="v3.3.3"
ARG REVAD_URL="https://github.com/cs3org/reva"
```

**Source build args:** Auto-generated from service config (`{SOURCE_KEY}_REF`, `{SOURCE_KEY}_URL`, `{SOURCE_KEY}_SHA`)

**CACHEBUST:** Computed from source SHAs/refs, ensures cache invalidation

## Common Commands

### Build with Cache Bust

```bash
# Force cache invalidation
nu scripts/build.nu --service revad-base --cache-bust "force-rebuild"

# Disable cache entirely
nu scripts/build.nu --service revad-base --no-cache
```

### Inspect Images

```bash
# List images with creation time
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

# List images sorted by creation time (newest first)
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | sort -k4 -r

# Show full creation timestamp
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}"

# Filter images by repository
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" | grep revad-base
```

### Inspect Build Cache

```bash
# See what's cached
docker buildx du --verbose

# Check specific cache entry
docker buildx du --filter id=<cache-id>
```

### Clean Up

```bash
# Remove old caches (recommended weekly)
docker buildx prune --all --filter "until=168h"

# Aggressive cleanup
docker buildx prune --all --force
```

## Troubleshooting

### Cache Not Invalidating

If cache persists after source changes:

1. Check `CACHEBUST` value: `docker buildx du` shows cache IDs
2. Verify Dockerfile uses `${CACHEBUST:-${SOURCE_REF}}` in cache mount IDs
3. Force rebuild: `nu scripts/build.nu --service <name> --cache-bust "force"`

### Cache Taking Too Much Space

```bash
# Check current usage
docker buildx du

# Prune reclaimable caches
docker buildx prune

# Set size limits
docker buildx prune --max-used-space 5GB
```

### Build Fails with Cache Mount Error

- Verify `ARG CACHEBUST="default"` is declared before cache mount usage
- Check cache mount ID syntax: `${CACHEBUST:-${SOURCE_REF}}`
- Ensure build system passes `CACHEBUST` build arg

## See Also

- [Build System Concepts](../concepts/build-system.md) - Build system architecture
- [Cache Busting](../concepts/build-system.md#cache-busting) - CACHEBUST details
- [Source Build Arguments](../concepts/service-configuration.md#source-build-arguments-convention) - Source build argument conventions
- [System Administration Guide](system-administration.md) - ZFS and disk space management
