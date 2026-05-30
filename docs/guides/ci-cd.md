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

This section documents the current CI/CD workflows for the DockyPody build
system.

## GitHub Actions Workflows

The shipped build workflows are generated from the current service graph by
`nu scripts/dockypody.nu ci workflow` and then committed to
`.github/workflows/`.

- **`.github/workflows/build.yml`**: Generated manual entry point for
  build-only verification
- **`.github/workflows/build-push.yml`**: Generated manual entry point for
  build-and-push runs plus post-push GHCR purge
- **`.github/workflows/build-orchestrator.yml`**: Generated reusable
  workflow that encodes service ordering and dependency fan-out
- **`.github/workflows/build-service.yml`**: Generated reusable workflow for
  one service's version/platform matrix
- **`.github/workflows/image-purge.yml`**: Generated manual GHCR purge entry
  point

These workflows are manual GitHub entry points. `build.yml`,
`build-push.yml`, and `image-purge.yml` use `workflow_dispatch`, while
`build-orchestrator.yml` and `build-service.yml` are reusable workflow
building blocks. When the service graph or workflow templates change, rerun
the generator and commit the updated files.

## Forgejo Workflows

Forgejo keeps the committed, non-generated workflows that round out the CI
story:

- **`.forgejo/workflows/validate-schemas.yml`**: Lightweight non-image
  validation. It validates schemas and manifests, runs `nu
  scripts/dockypody.nu docs lint`, and runs the `ci`, `ghcr-purge`, and
  `docs-lint` test suites.
- **`.forgejo/workflows/build-containers.yml`**: Image build workflow that
  installs the same Nushell version as GitHub and calls `nu
  scripts/dockypody.nu build ...` directly.

In other words: Forgejo handles lightweight automatic validation plus the
legacy image-build lane, while the generated GitHub workflows describe the
current build-and-purge graph.

## GHCR package retention (SSOT purge)

When you push the same tag (for example `latest`) multiple times, GHCR keeps
old package versions as untagged history. Over time this can consume
significant storage.

DockyPody supports a SSOT-based purge that deletes GHCR package versions that
are not referenced by the current `services/**/{versions,platforms}.nuon`
state.

- Manual workflow: `.github/workflows/image-purge.yml`
- Auto purge: `ghcr_purge` job inside `.github/workflows/build-push.yml`
  (runs only when `push: true` and all builds succeeded)
- CLI entrypoint: `nu scripts/dockypody.nu ci ghcr-purge`

Safety and fault tolerance:

- Manual workflow defaults to `dry_run=true`.
- Use `--max-deletes` (and the workflow input `max_deletes`) to cap
  deletions. This is a global budget across all services in the run.
- If a service's SSOT desired tag set is empty, the purge deletes only
  untagged versions by default. Use `--force` with `--service` and
  `--dry-run=false` to allow a full wipe for that single service.
- If the token cannot delete package versions (permission denied), the purge
  step should warn and skip instead of failing the build.

## Dependency Reuse in CI

Current CI uses workflow-local shard artifacts, not `actions/cache`, to
reuse dependency images between jobs. The shipped generated workflows do not
have an active `actions/cache` restore/save path.

### Artifact Flow

The generated `build-service.yml` workflow does this for each
service/version/platform node:

1. **Prepare dependency shards**: Run `nu scripts/dockypody.nu ci
   prepare-node-deps ...` for the dependency closure passed in by
   `build-orchestrator.yml`.
2. **Download and load dependency shards**: `ci prepare-node-deps` pulls the
   shard artifacts from earlier jobs in the same workflow run and loads the
   matching images into the Docker daemon.
3. **Build node**: Run `nu scripts/dockypody.nu build ...` with
   `--dep-cache=soft` and the normal CI pull settings so missing shards can
   still be rebuilt when needed.
4. **Create shard**: Package the node's image state as a shard artifact after
   the build finishes.
5. **Upload shard artifact**: Publish that shard so downstream jobs in the
   same run can download and reuse it.

Shard artifact names follow
`shard-<service>-<version>-<platform|single>`. This keeps reuse scoped to
the current workflow run and aligned with the generated service graph.

### Legacy Cache Notes

The CLI still documents `--cache-match` for legacy or custom callers, but
the generated workflows no longer compute `exact`/`fallback`/`miss` labels
through `actions/cache`, and they no longer restore or save image state with
`actions/cache` at all.

## Service Definition Hash

In CI, the build system uses service definition hashes to skip unnecessary
dependency rebuilds:

1. Each built image gets a hash label
   (`org.opencloudmesh.system.service-def-hash`)
2. Before building dependencies, the system checks if local images have
   matching hashes
3. Dependencies with matching hashes are skipped (valid cache hit)
4. Dependencies with missing or stale hashes are auto-built with a warning

See [Build System - Service Definition Hash](../concepts/build-system.md#service-definition-hash) for details.

## Unified Builder Model

Both development and CI builds use the same Docker driver model:

- **Dev builds**: Default Buildx builder (docker driver)
- **CI builds**: Buildx configured with `driver: docker` via `docker/setup-buildx-action`

This ensures consistent behavior between local and CI environments. Images
built with `--load` go to the Docker daemon store, which is shared with
Buildx.

## Related Documentation

- [Build System](../concepts/build-system.md) - Build system architecture and features
- [Dependency Management](../concepts/dependency-management.md) - Dependency resolution and hash-based reuse
- [CLI Reference](../reference/cli-reference.md) - Complete CLI documentation
