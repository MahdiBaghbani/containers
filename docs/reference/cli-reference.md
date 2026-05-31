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

## Unified CLI: dockypody

The `dockypody.nu` script is the canonical entry point for the DockyPody build system. It provides a unified interface to all build, test, validation, TLS, and CI operations.

### Basic Usage

```bash
# Show top-level help
nu scripts/dockypody.nu help

# Build commands
nu scripts/dockypody.nu build --service gaia
nu scripts/dockypody.nu build --all-services --show-build-order

# Test commands
nu scripts/dockypody.nu test --suite defaults
nu scripts/dockypody.nu test --suite all --verbose

# TLS commands
nu scripts/dockypody.nu tls ca
nu scripts/dockypody.nu tls certs
nu scripts/dockypody.nu tls clean
nu scripts/dockypody.nu tls clean --service-ca-only

# SSH commands
nu scripts/dockypody.nu ssh key
nu scripts/dockypody.nu ssh key --force

# CI commands (--target is mandatory for workflow; cache-shard helpers are
# legacy/manual)
nu scripts/dockypody.nu ci list-deps --service nextcloud
nu scripts/dockypody.nu ci workflow --target all --dry-run
nu scripts/dockypody.nu ci images --service nextcloud
# Legacy/manual maintenance only; shipped workflows use artifact shards instead
nu scripts/dockypody.nu ci merge-cache-shards --service svc --ref r --sha s
nu scripts/dockypody.nu ci ghcr-purge --dry-run
# --max-deletes is a global budget across all services in the run
nu scripts/dockypody.nu ci ghcr-purge --dry-run=false --max-deletes=200
# Force-wipe is allowed only for a single service and only with --dry-run=false
nu scripts/dockypody.nu ci ghcr-purge --service nextcloud --dry-run=false --max-deletes=200 --force
# Optional partial-success policy: tolerate live delete failures and continue
nu scripts/dockypody.nu ci ghcr-purge --service nextcloud --dry-run=false --partial-success

# Validate commands
nu scripts/dockypody.nu validate --all-services
nu scripts/dockypody.nu validate --service gaia
nu scripts/dockypody.nu validate --service gaia --manifests-only

# Docs commands
nu scripts/dockypody.nu docs lint
nu scripts/dockypody.nu docs lint --fix
```

### Available Subcommands

| Subcommand | Description | Domain CLI |
| ---------- | ----------- | ---------- |
| `build` | Build container images | `build/cli.nu [build-cli]` |
| `test` | Run test suites (`--suite`, `--verbose`) | `test/cli.nu [test-cli]` |
| `validate` | Validate service configurations | `validate/cli.nu [validate-cli]` |
| `tls ca` | Generate CA certificate | `tls/cli.nu [tls-cli]` |
| `tls certs` | Generate service certificates | `tls/cli.nu [tls-cli]` |
| `tls clean` | Remove TLS artifacts | `tls/cli.nu [tls-cli]` |
| `ssh key` | Generate SSH keypair | `ssh/cli.nu [ssh-cli]` |
| `ci list-deps` | List dependency services | `ci/cli.nu [ci-cli]` |
| `ci load-deps` | Load dependency tarballs | `ci/cli.nu [ci-cli]` |
| `ci load-owner` | Load owner tarballs | `ci/cli.nu [ci-cli]` |
| `ci save-owner` | Save owner tarballs | `ci/cli.nu [ci-cli]` |
| `ci prepare-node-deps` | Download/load dep shards from run artifacts (CI) | `ci/cli.nu [ci-cli]` |
| `ci workflow` | Write CI workflow YAML (--target ..., --dry-run) | `ci/cli.nu [ci-cli]` |
| `ci images` | List canonical image references | `ci/cli.nu [ci-cli]` |
| `ci login-registry` | Log into default container registry | `ci/cli.nu [ci-cli]` |
| `ci merge-cache-shards` | Legacy/manual cache-shard merge helper; not used by generated artifact workflows | `ci/cli.nu [ci-cli]` |
| `ci cleanup-cache-shards` | Legacy/manual cache-shard cleanup helper; not used by generated artifact workflows | `ci/cli.nu [ci-cli]` |
| `ci ghcr-purge` | Purge stale GHCR package versions (SSOT-based) | `ci/cli.nu [ci-cli]` |
| `docs lint` | Lint documentation files | `docs/cli.nu [docs-cli]` |

### CLI Architecture

`dockypody.nu` acts as a thin router that delegates to domain-specific CLI entrypoints:

- Each domain under `scripts/lib/` exposes a `<domain>-cli` function in `cli.nu`
- The router parses top-level commands and flags, then calls the appropriate domain CLI
- Domain CLIs handle subcommand routing and flag processing internally
- This pattern enables clean separation of concerns and testable domain logic

### Help routing

DockyPody owns the positional `help` contract:

- Top level: `nu scripts/dockypody.nu help`
- Single-command CLIs: `nu scripts/dockypody.nu build help`,
  `nu scripts/dockypody.nu test help`,
  `nu scripts/dockypody.nu validate help`
- Routed domains: `nu scripts/dockypody.nu tls help`,
  `nu scripts/dockypody.nu ssh help`,
  `nu scripts/dockypody.nu ci help`,
  `nu scripts/dockypody.nu docs help`

Nushell intercepts `--help` and `-h` before `dockypody.nu`'s `main` body runs,
so those flag forms are Nushell help, not DockyPody-owned command help.

### Router flags snapshot

All flags below live on `scripts/dockypody.nu` `main`. Each handler reads only its
subset; unrelated flags remain parsed but unused for that invocation.

Build-related: `--service`, `--all-services`, `--push`, `--latest`,
`--extra-tag`, `--provenance`, `--version`, `--all-versions`, `--versions`,
`--latest-only`, `--platform`, `--matrix-json`, `--progress`, `--cache-bust`,
`--no-cache`, `--show-build-order`, `--dep-cache`, `--push-deps`, `--tag-deps`,
`--fail-fast`, `--pull`, `--cache-match`, `--disk-monitor`,
`--prune-cache-mounts`.

Test: `--suite`, `--verbose`.

Validate: `--service`, `--all-services`, `--manifests-only`.

TLS: `--service` (comma-separated service names passed to clean), `--filter`
(comma list for cert generation subset), `--service-ca-only`, `--skip-shared-ca`,
`--keep-empty-dirs`, `--dry-run`, `--force`, `--verbose`.

SSH: `--force`.

CI (shared fields): `--service`, `--version`, `--platform`,
`--dependencies` (comma list), `--target`, `--ref`, `--sha`, `--transitive`,
`--debug`, `--dry-run`, `--max-deletes`, `--force`,
`--partial-success`.

Docs: `--fix`.

## Non-build commands (reference)

The sections below summarize commands other than `build`. Build flags remain the
bulk of this file starting at [Build Command](#build-command).

### test

```bash
nu scripts/dockypody.nu test [--suite <name>] [--verbose]
```

- `--suite` names a file under `scripts/tests/<suite>.nu`. The default suite
  name `all` runs the current non-Docker bundle surfaced by
  `nu scripts/dockypody.nu test help`.
- You may pass any suite name matching a `scripts/tests/*.nu` file.
  `docker-integration` stays opt-in, is excluded from `all`, and supports two
  truthful invocation paths:
  - Routed: `DOCKYPODY_DOCKER_INTEGRATION=1 nu scripts/dockypody.nu test --suite docker-integration`
  - Direct: `nu scripts/tests/docker-integration.nu --docker`

### validate

```bash
nu scripts/dockypody.nu validate [--service <name>] [--all-services] [--manifests-only]
```

- `--all-services`: validate every discovered service (mutually exclusive with a
  single `--service`; see `validate-cli` behavior).

### tls

Subcommands: `ca`, `certs`, `clean`; positional help is
`nu scripts/dockypody.nu tls help`.

```bash
nu scripts/dockypody.nu tls ca [--force] [--verbose]
nu scripts/dockypody.nu tls certs [--filter svc1,svc2] [--verbose]
nu scripts/dockypody.nu tls clean [--service a,b] [--dry-run]
     [--skip-shared-ca] [--keep-empty-dirs] [--service-ca-only]
```

TLS library helpers like `copy-tls` are module exports only; no `tls copy`
subcommand is routed through `dockypody.nu`.

- `tls ca --force` regenerates the shared CA even if it already exists. After a
  forced CA regeneration, regenerate service certificates with
  `nu scripts/dockypody.nu tls certs`.
- `--filter` applies to `tls certs` only.
- `--service`, `--dry-run`, `--skip-shared-ca`, `--keep-empty-dirs`, and
  `--service-ca-only` apply to `tls clean` only.

### ssh

Subcommands: `key`.

```bash
nu scripts/dockypody.nu ssh key [--force]
```

### ci

Invoke as `nu scripts/dockypody.nu ci <subcommand> [flags]`.

| Subcommand | Role | Typical flags |
| ---------- | ------ | ------------- |
| `list-deps` | Print dependency names (stdout lines) | `--service`, optional `--transitive`, `--debug` |
| `load-deps` | Load dependency tarballs from cache | `--service` |
| `load-owner` / `save-owner` | Load/save owner tarballs | `--service` |
| `prepare-node-deps` | Download shard artifacts when run in GitHub Actions | `--service`, `--version`, optional `--platform`, `--dependencies` (comma), `--debug` |
| `workflow` | Rewrite workflow files from templates | Mandatory `--target` (see targets below), `--dry-run` optional |
| `images` | Print canonical refs for caches | `--service` |
| `login-registry` | Registry login helper | `--debug` |
| `merge-cache-shards` | Legacy/manual helper for older cache-shard flows; not part of generated artifact workflows | `--service`, `--ref`, `--sha`; optional `--debug`; base dir from `DOCKYPODY_SHARD_BASE_DIR` or `/tmp/docker-images/shards` |
| `cleanup-cache-shards` | Legacy/manual helper for older cache-shard flows; not part of generated artifact workflows | `--service`, `--ref`, `--sha`; `--dry-run`, `--debug`; needs `GITHUB_TOKEN`, `GITHUB_REPOSITORY`, `gh` |
| `ghcr-purge` | Trim GHCR package versions vs SSOT | Optional `--service` (omit = all services), `--dry-run`, `--max-deletes`, `--debug`, `--force` (needs single service, no dry-run), `--partial-success` (default is strict failure on live delete errors) |

`ci workflow --target` must be exactly one of: `all`, `build`, `build-push`,
`orchestrator`, `build-service`, `image-purge`. An omitted or empty `--target`
is rejected by the routed `ci-cli` preflight before target resolution runs.

Generated workflows use `ci prepare-node-deps` plus workflow-local shard
artifacts for dependency reuse. `merge-cache-shards` and
`cleanup-cache-shards` remain available only for legacy or manual maintenance
flows.

`ci ghcr-purge` reports run totals with separate `planned`, `attempted`,
`deleted`, `failed`, `skipped`, and `charged` counts. Dry-run reports planned
candidates but charges `0` against the live delete budget. Permission-denied
version lists are soft-skipped and named explicitly in the final summary.

`--max-deletes` defaults differ by entrypoint on purpose. The public CLI
default is `0`, which means unlimited unless you pass a bound explicitly.
Bundled workflows keep bounded defaults instead: `build-push.yml` runs
`ghcr-purge` with `--max-deletes=200`, and `image-purge.yml` exposes a
`max_deletes` input that defaults to `100`.

### docs

Subcommands: `lint`.

```bash
nu scripts/dockypody.nu docs lint [--fix]
```

The routed `dockypody.nu` contract is repo-wide linting only. It always passes
an empty file list into the module API, so file discovery uses
`git ls-files --cached --others --exclude-standard` and respects
ignored/generated trees.

Autofix (`--fix`) replaces all occurrences of each forbidden pattern, rescans
the changed files, and exits successfully only when the rescan is clean.

## Build Command

```bash
nu scripts/dockypody.nu build --service <service-name> [options]
```

## Service Selection Flags

### `--service <string>`

Build a specific service. Use this when you are not targeting
`--all-services`:

```bash
nu scripts/dockypody.nu build --service revad-base
```

### `--all-services`

Build all discovered services in dependency order:

```bash
nu scripts/dockypody.nu build --all-services
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
nu scripts/dockypody.nu build --all-services

# Build all services, all versions
nu scripts/dockypody.nu build --all-services --all-versions

# Build only latest versions of all services
nu scripts/dockypody.nu build --all-services --latest-only

# Build all services for debian platform only
nu scripts/dockypody.nu build --all-services --platform debian

# Generate CI matrix for all services
nu scripts/dockypody.nu build --all-services --matrix-json

# Show build order without building
nu scripts/dockypody.nu build --all-services --show-build-order
```

## Version Flags

### `--version <string>`

Build a specific version from the manifest:

```bash
nu scripts/dockypody.nu build --service revad-base --version v3.3.3
```

### `--all-versions`

Build all versions defined in the manifest:

```bash
nu scripts/dockypody.nu build --service revad-base --all-versions
```

### `--latest-only`

Build only versions marked with `latest: true`:

```bash
nu scripts/dockypody.nu build --service revad-base --latest-only
```

### `--versions <string>`

Build multiple specific versions (comma-separated list):

```bash
nu scripts/dockypody.nu build --service revad-base --versions v1.29.0,v1.28.0
```

**Note:** `--version` (singular) for single version, `--versions` (plural) for multiple versions.

## Platform Flags

### `--platform <string>`

Filter builds to a specific platform (requires `platforms.nuon`, even if that
manifest defines only one platform):

```bash
# Build only debian variant
nu scripts/dockypody.nu build --service my-service --version v1.0.0 --platform debian

# Build all debian versions
nu scripts/dockypody.nu build --service my-service --all-versions --platform debian
```

### Platform Suffix in Version

You can specify platforms inline with version names:

```bash
# Build only v1.0.0-debian
nu scripts/dockypody.nu build --service my-service --version v1.0.0-debian

# Build multiple platform-specific versions
nu scripts/dockypody.nu build --service my-service --versions "v1.0.0-debian,v1.0.0-alpine"
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
nu scripts/dockypody.nu build --service revad-base --matrix-json
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

- Empty string (`""`) = service resolved without an explicit
  `platforms.nuon` manifest
- Non-empty string = platform name from `platforms.nuon`, even when that
  manifest contains only one platform
- Never `null` - always a string (empty or platform name)

## Cache Busting Flags

### `--cache-bust <string>`

Override cache busting for all services in the build with a custom value:

```bash
# Use custom cache bust value for all services
nu scripts/dockypody.nu build --service cernbox-web --cache-bust "abc123"
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
nu scripts/dockypody.nu build --service cernbox-web --no-cache
```

This is equivalent to `--cache-bust <random-uuid>` but more convenient for forcing full rebuilds.

**Note:** Cache busting is per-service by default. Use these flags for global overrides.

## Dependency Building Flags

### `--dep-cache <string>`

Control dependency reuse behavior for CI builds:

```bash
# Disable hash-based skip (always build deps)
nu scripts/dockypody.nu build --service cernbox-web --dep-cache=off

# Hash-based skip + auto-build on missing/stale (default for CI)
nu scripts/dockypody.nu build --service cernbox-web --dep-cache=soft

# Strict validation, fail on missing/stale (no auto-build)
nu scripts/dockypody.nu build --service cernbox-web --dep-cache=strict
```

**Modes:**

| Mode | Behavior | Use Case |
| ---- | -------- | -------- |
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
nu scripts/dockypody.nu build --service cernbox-web --push-deps

# Push both dependencies and target service
nu scripts/dockypody.nu build --service cernbox-web --push --push-deps
```

**Behavior:**

- Only affects dependencies (not target service)
- Independent of `--push` flag
- Can be used with or without `--push`

### `--tag-deps`

Tag dependencies with `--latest` and/or `--extra-tag` (independent of target service tags):

```bash
# Tag dependencies as latest
nu scripts/dockypody.nu build --service cernbox-web --latest --tag-deps

# Tag dependencies with custom tag
nu scripts/dockypody.nu build --service cernbox-web --extra-tag stable --tag-deps

# Tag both dependencies and target
nu scripts/dockypody.nu build --service cernbox-web --latest --tag-deps
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
nu scripts/dockypody.nu build --service cernbox-web --show-build-order

# Show build order for specific version
nu scripts/dockypody.nu build --service cernbox-web --show-build-order --version v1.0.0

# Show build order for all versions
nu scripts/dockypody.nu build --service cernbox-web --show-build-order --all-versions

# Show build order for specific versions
nu scripts/dockypody.nu build --service cernbox-web --show-build-order --versions v1.0.0,v1.1.0

# Show build order for latest versions only
nu scripts/dockypody.nu build --service cernbox-web --show-build-order --latest-only
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

For services using `platforms.nuon`, each version/platform combination is
displayed separately:

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
- `--platform <string>` - Filter to a platform from `platforms.nuon`

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
nu scripts/dockypody.nu build --service revad-base --all-versions --fail-fast
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
nu scripts/dockypody.nu build --service revad-base --version v3.3.3 --push
```

### `--progress <string>`

Set build progress output format:

```bash
nu scripts/dockypody.nu build --service revad-base --all-versions --progress plain
```

### `--latest <boolean>`

Control latest tag generation:

```bash
nu scripts/dockypody.nu build --service revad-base --version v1.28.0 --latest false
```

## Disk Management Flags

### `--disk-monitor <string>`

Control disk monitoring output during builds. `off` disables monitoring.
Any other non-`off` value enables the same basic disk usage snapshots.
Generated workflows currently pass `basic`.

```bash
# Enable basic disk monitoring
nu scripts/dockypody.nu build --service cernbox-web --all-versions --disk-monitor=basic

# Default: monitoring disabled
nu scripts/dockypody.nu build --service cernbox-web --all-versions --disk-monitor=off
```

**Runtime contract:**

| Value            | Behavior                                 |
| ---------------- | ---------------------------------------- |
| `off`            | No monitoring (default for local builds) |
| any non-`off`    | Emit disk usage snapshots at build phases |

**CI Default:** `basic` (enabled for all services in generated workflows)

### `--prune-cache-mounts`

Prune BuildKit cache between version builds:

```bash
# Enable cache pruning
nu scripts/dockypody.nu build --service cernbox-web --all-versions --prune-cache-mounts

# Default: pruning disabled (local builds)
nu scripts/dockypody.nu build --service cernbox-web --all-versions
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
