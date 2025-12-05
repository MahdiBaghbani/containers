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

# CI/CD Workflows

This section documents CI/CD workflows and automation for the DockyPody build system.

## GitHub Actions Workflows

The build system uses reusable GitHub Actions workflows:

- **`.github/workflows/build.yml`**: Entry point for manual builds
- **`.github/workflows/build-service.yml`**: Reusable workflow for building a single service

Builds are triggered by workflow dispatch (manual), not inferred from commits.

## Docker Image Caching

CI workflows use `actions/cache` to store and restore Docker images between runs. This speeds up builds by reusing previously built dependency images.

### Cache Key Strategy

The cache uses a commit+branch key pattern:

```yaml
key: images-{service}-{branch}-{commit}
restore-keys: |
  images-{service}-{branch}-
```

This strategy provides:

- **Exact match**: Reuse cache from the same commit on the same branch
- **Fallback match**: Reuse cache from an older commit on the same branch
- **No cross-branch pollution**: Each branch has its own cache namespace

### Cache Match Kind

The workflow determines how the cache was matched and passes this to the build script:

| Match Kind | Meaning | Typical Cause |
|------------|---------|---------------|
| `exact` | Cache key matched exactly | Same commit rebuilt |
| `fallback` | Restore key matched | New commit on existing branch |
| `miss` | No cache found | First build on a new branch |

The match kind is passed via the `--cache-match` flag:

```bash
nu scripts/dockypody.nu build --service my-service --cache-match=fallback
```

This appears in log messages when dependencies are auto-built, helping diagnose cache behavior.

### Cache Workflow Steps

The `build-service.yml` workflow:

1. **Restore cache**: Attempts to restore from exact key, then fallback keys
2. **Load images**: Loads saved images into Docker daemon (if cache hit)
3. **Determine match kind**: Computes `exact`, `fallback`, or `miss`
4. **Build service**: Runs build with `--cache-match` flag
5. **Save images**: Saves all images to cache directory
6. **Save cache**: Stores cache for future runs

## Service Definition Hash

In CI, the build system uses service definition hashes to skip unnecessary dependency rebuilds:

1. Each built image gets a hash label (`org.opencloudmesh.system.service-def-hash`)
2. Before building dependencies, the system checks if local images have matching hashes
3. Dependencies with matching hashes are skipped (valid cache hit)
4. Dependencies with missing or stale hashes are auto-built with a warning

See [Build System - Service Definition Hash](../concepts/build-system.md#service-definition-hash) for details.

## Unified Builder Model

Both development and CI builds use the same Docker driver model:

- **Dev builds**: Default Buildx builder (docker driver)
- **CI builds**: Buildx configured with `driver: docker` via `docker/setup-buildx-action`

This ensures consistent behavior between local and CI environments. Images built with `--load` go to the Docker daemon store, which is shared with Buildx.

## Related Documentation

- [Build System](../concepts/build-system.md) - Build system architecture and features
- [Dependency Management](../concepts/dependency-management.md) - Dependency resolution and hash-based reuse
- [CLI Reference](../reference/cli-reference.md) - Complete CLI documentation
