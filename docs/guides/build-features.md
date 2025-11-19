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
# Build System Features Guide

This guide covers advanced build system features: cache busting, automatic dependency building, build order resolution, and continue-on-failure mode.

## Cache Busting

### Understanding Cache Busting

Cache busting ensures Docker rebuilds layers when source dependencies change. The build system provides deterministic cache invalidation.

### Default Behavior

Each service computes its own cache bust value from source refs:

```bash
# Service with sources: reva:v3.3.2, nushell:0.108.0
# Computes: SHA256("reva:v3.3.2:nushell:0.108.0") -> first 16 chars
```

### Global Override

Override for all services in build:

```bash
# Custom value
nu scripts/build.nu --service cernbox-web --cache-bust "release-2024-01-15"

# Random UUID (force rebuild)
nu scripts/build.nu --service cernbox-web --no-cache
```

### Dockerfile Usage

```dockerfile
ARG CACHEBUST=""
RUN git clone --branch ${REVAD_REF} ${REVAD_URL} /revad-git
# CACHEBUST forces rebuild if sources change
```

## Automatic Dependency Building (Guide)

### How It Works

1. Build dependency graph
2. Topological sort determines order
3. Build each dependency sequentially
4. Docker uses cache if image exists

### Examples

```bash
# Auto-build missing dependencies
nu scripts/build.nu --service cernbox-web
# Builds: revad-base (if missing) -> cernbox-revad (if missing) -> cernbox-web

# Disable auto-build
nu scripts/build.nu --service cernbox-web --no-auto-build-deps
# Fails if dependencies missing
```

### Flag Propagation (Guide)

- `--push-deps`: Push dependencies (independent of `--push`)
- `--tag-deps`: Tag dependencies (propagates `--latest` and `--extra-tag`)

## Build Order Resolution (Guide)

### Viewing Build Order (Guide)

```bash
nu scripts/build.nu --service cernbox-web --show-build-order
```

**Output:**

```text
=== Build Order ===

1. revad-base:v3.3.2
2. cernbox-revad:v1.0.0
3. cernbox-web:v1.0.0
```

### Understanding the Graph

- Version-aware: Each version can have different dependencies
- Platform-aware: Platform inheritance applied
- Cycle detection: All cycles reported if detected

## Continue-on-Failure Mode

### Default Behavior

- **Single builds:** Fail fast
- **Multi-version builds:** Continue-on-failure

### Examples (Guide)

```bash
# Continue on failure (default for multi-version)
nu scripts/build.nu --service revad-base --all-versions
# Builds all versions, reports summary

# Fail fast
nu scripts/build.nu --service revad-base --all-versions --fail-fast
# Stops on first failure
```

### Build Summary (Guide)

Machine-parseable summary after multi-version builds:

```text
=== Build Summary ===
STATUS: PARTIAL
SUCCESS: 2
FAILED: 1
SKIPPED: 0

SUCCESS:
  - revad-base:v3.3.2
  - revad-base:v3.4.0

FAILED:
  - revad-base:v3.5.0
    Error: Build failed: ...

SKIPPED:
  - revad-base:v3.6.0
    Reason: Dependency build failed
```

## Best Practices

1. **Use per-service cache busting** for normal builds (default)
2. **Use `--no-cache`** for release builds to ensure freshness
3. **Let auto-build handle dependencies** (default behavior)
4. **Use `--show-build-order`** to debug dependency issues
5. **Review build summary** after multi-version builds


