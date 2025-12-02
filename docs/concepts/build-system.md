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

# Build System

## Overview

The DockyPody build system orchestrates the container image build process, handling configuration merging, build argument injection, and build execution.

## Build Argument Injection Priority

When injecting build arguments, the build system applies them in this order (later steps override earlier ones):

1. **Base arguments** (COMMIT_SHA, VERSION)
   - `COMMIT_SHA`: The DockyPody repository commit that performed the build (or `"local"` for local builds)
   - `VERSION`: The service version from the version manifest (e.g., `"v1.0.0"`, `"v1.0.0-debian"`)
2. **Source arguments** (auto-generated from `sources` section)
   - **Git sources**: `{SOURCE_KEY}_REF`, `{SOURCE_KEY}_URL`, `{SOURCE_KEY}_SHA`
   - **Local sources**: `{SOURCE_KEY}_PATH`, `{SOURCE_KEY}_MODE`
3. **External image arguments** (from `external_images` section)
4. **Config `build_args` section** (from service config)
5. **Environment variables** (can override config values for testing/debugging)
   - Environment variables can override config values (sources, external images, config `build_args`)
   - Example: `export REVAD_REF="custom"` overrides the auto-generated `REVAD_REF` from sources config
   - Example: `export REVA_PATH="/custom/path"` overrides the local source path from config
   - Example: `export BASE_BUILD_IMAGE="custom"` overrides the external image from config
   - **Important:** Environment variables CANNOT override dependency values (dependencies are applied after this step)
6. **Dependency resolution** (HIGHEST PRIORITY - overrides environment variables)
   - Resolved dependency images always override previous values for dependency build args (e.g., `REVAD_BASE_IMAGE`)
   - Dependencies are system-managed and authoritative - they override any previous values, including environment variables
   - This ensures reproducible builds and prevents accidental overrides
7. **TLS arguments** (TLS_ENABLED, TLS_CERT_NAME, TLS_CA_NAME)
   - Added last but use unique names that don't conflict with dependency build args
   - These are system-managed arguments and should not be overridden
8. **CACHEBUST argument** (cache invalidation)
   - Computed per-service or global override
   - Optional in Dockerfiles (user-controlled)

**Dockerfile defaults** (lowest priority - only used if build arg not provided):

- `ARG REVAD_BASE_IMAGE="revad-base:latest"` - Used only if the build script doesn't provide this arg

**Note:** Dependencies have the highest priority for dependency-related build arguments and will override environment variables. TLS arguments are added after dependencies but use a separate namespace (TLS\_\*) and don't conflict with dependency build args.

### Environment Variable Override Behavior

| Build Arg Type               | Can Be Overridden by Env Var? | Reason                                                 |
| ---------------------------- | ----------------------------- | ------------------------------------------------------ |
| Source args (auto-generated) | **YES**                       | `REVAD_REF`, `REVAD_URL` can be overridden for testing |
| External image args          | **YES**                       | `BASE_BUILD_IMAGE` can be overridden for testing       |
| Config `build_args`          | **YES**                       | `CUSTOM_ARG` can be overridden for testing             |
| **Dependency args**          | **NO**                        | Dependencies are system-managed and authoritative      |
| **TLS args**                 | **NO**                        | TLS args use separate namespace (TLS\_\*)              |

### Summary

- Environment variables can override config values (sources, external images, config `build_args`)
- **Environment variables CANNOT override dependency values** - dependencies are applied after env vars and will override them
- **Environment variables CANNOT override TLS arguments** - TLS args use a separate namespace
- Use environment variable overrides for testing, debugging, or temporary overrides of config values only

### Build Argument Priority Example

**Scenario:** Service `cernbox-revad` depends on `revad-base`, with various build arg sources:

#### Service Config

```nuon
{
  "dependencies": {
    "revad-base": {
      "version": "v3.3.3",
      "build_arg": "REVAD_BASE_IMAGE"
    }
  },
  "build_args": {
    "REVAD_BASE_IMAGE": "revad-base:custom"
  }
}
```

#### Environment Variable

```bash
export REVAD_BASE_IMAGE="revad-base:env-override"
```

#### Dockerfile Default

```dockerfile
ARG REVAD_BASE_IMAGE="revad-base:latest"
```

**Final Build Arg Value:** `REVAD_BASE_IMAGE="revad-base:v3.3.3"`

#### Explanation

1. Dockerfile default: `revad-base:latest` (lowest priority, ignored)
2. Config `build_args`: `revad-base:custom` (overridden by env)
3. Environment variable: `revad-base:env-override` (overridden by dependency - dependencies win)
4. Dependency resolution: `revad-base:v3.3.3` (highest priority - wins, overrides env var)

The dependency resolution step constructs the image reference from the resolved dependency version (`v3.3.3`) and overrides all previous values, including environment variables.

## Cache Busting

The build system supports deterministic cache invalidation through the `CACHEBUST` build argument.

### Default Behavior (Per-Service)

By default, each service computes its own cache bust value using this fallback chain:

1. **Services with Git sources:** SHA256 hash of all source refs/SHAs (first 16 characters)
   - Source keys are sorted before hashing for consistency
   - Only Git sources are included (local sources are filtered out)
   - Example: `reva:v3.3.3,nushell:0.108.0` -> `a1b2c3d4e5f6g7h8`
2. **Services with only local sources:** Random UUID (always-bust behavior)
   - Local sources trigger always-bust cache behavior
   - Ensures builds pick up changes in local directories
3. **Services without sources:** Git commit SHA (as-is, full SHA)
4. **Local builds (no Git):** `"local"`

### Global Override

You can override cache busting globally for all services:

- `--cache-bust <value>` - Use custom value for all services
- `--no-cache` - Generate random UUID for all services (forces full rebuild)

### Environment Variable Override

You can also set `CACHEBUST` environment variable:

```bash
export CACHEBUST="custom-value"
nu scripts/build.nu --service cernbox-web
```

**Priority order (highest to lowest):**

1. `--cache-bust` flag (global override)
2. `--no-cache` flag (generates random UUID)
3. `CACHEBUST` environment variable
4. Per-service computation (fallback chain: Git sources hash -> random UUID for local-only -> Git SHA -> "local")

**Local Source Behavior:**

- Services with **only local sources** use random UUID (always-bust behavior)
- Services with **mixed local/Git sources** use Git sources only for cache bust computation
- Local sources are explicitly filtered out before cache bust computation

### Dockerfile Usage

Dockerfiles can use `CACHEBUST` in source cloning steps:

```dockerfile
ARG CACHEBUST=""
RUN git clone --branch ${REVAD_REF} ${REVAD_URL} /revad-git
```

**Note:** `CACHEBUST` is optional in Dockerfiles. The build system always provides it, but Dockerfiles can choose to use it or ignore it.

### Cache Mount Invalidation

Cache mounts for git clones and source downloads use CACHEBUST in their mount IDs to ensure cache invalidation when sources change:

```dockerfile
ARG CACHEBUST="default"
ARG SOURCE_REF="v3.3.3"
RUN --mount=type=cache,id=service-source-git-${CACHEBUST:-${SOURCE_REF}},target=/cache,sharing=shared \
    git clone --branch "${SOURCE_REF}" ${SOURCE_URL} /cache
```

When CACHEBUST changes (SHA change, ref change, or manual override), Docker uses a new cache mount, ensuring fresh content after force-pushes. Build system always provides non-empty CACHEBUST value. CACHEBUST is computed as SHA256 hash of all source SHAs/refs (first 16 characters), using hybrid approach: SHA if available from extraction, ref if SHA extraction fails.

## Local Source Restrictions

Local folder sources (using `path` field) are restricted to development builds only.

### CI/Production Build Rejection

**CRITICAL:** Local sources are **automatically rejected** in CI/production builds.

The build system detects the build environment:

- **Local builds** (`is_local: true`): Local sources are allowed
- **CI/production builds** (`is_local: false`): Local sources are rejected with an error

**Error message:**

```text
Error: Local sources are not allowed in CI builds. Use git sources instead.
Local sources found: [reva, custom_lib]
```

**Detection:**

The build system detects local sources by:

1. Checking for `path` field in source configuration
2. Checking for `{SOURCE_KEY}_PATH` environment variable

If either is present, the source is treated as local and rejected in non-local builds.

### Build Context Preparation

For local sources, the build system automatically:

1. **Validates paths** - Ensures paths exist, are directories, and are within repository root
2. **Copies to build context** - Copies local source directories to `.build-sources/{source_key}/` in the build context
3. **Resolves paths** - Build args use paths relative to build context root (e.g., `.build-sources/reva/`)

**Note:** Copied sources are left in `.build-sources/` after build for debugging (consistent with TLS helper pattern).

### SHA and Label Generation

Local sources have different behavior for metadata generation:

- **SHA extraction**: Skipped (no Git repository to extract from)
- **Source revision labels**: Not generated (no Git metadata available)
- **Cache busting**: Uses random UUID (always-bust behavior)

Only Git sources generate SHA build args and source revision labels.

## Build Order Resolution

The build system automatically resolves dependency build order using a version-aware dependency graph.

### Graph Construction

- **Nodes:** `{service, version, platform}` tuples
- **Edges:** Dependency relationships
- **Version-aware:** Each version can have different dependencies (from version overrides)
- **Platform-aware:** Platform inheritance applied during graph construction

### Topological Sort

Build order is determined using DFS-based topological sort:

1. Construct dependency graph recursively
2. Perform DFS traversal
3. Collect all cycles (if any)
4. Return build order (reverse of DFS finish order)

### Cycle Detection

If circular dependencies are detected, the build system:

- Collects ALL cycles (not just the first)
- Reports complete list of cycles
- Errors with clear message

### Display Build Order

Use `--show-build-order` flag to see build order without building:

```bash
# Single version (default)
nu scripts/build.nu --service cernbox-web --show-build-order

# All versions
nu scripts/build.nu --service cernbox-web --show-build-order --all-versions

# Specific versions
nu scripts/build.nu --service cernbox-web --show-build-order --versions v1.0.0,v1.1.0
```

**Output (single version):**

```text
=== Build Order ===

1. revad-base:v3.3.3
2. cernbox-revad:v1.0.0
3. cernbox-web:v1.0.0
```

## Automatic Dependency Building

By default, the build system automatically builds missing dependencies.

### Default Auto-Build Behavior

When building a service:

1. Build dependency graph
2. Topological sort to determine build order
3. Build each dependency in order (if missing)
4. Build target service

**Docker handles caching:** If a dependency image already exists, Docker uses it (no rebuild).

### Disable Auto-Build

Use `--no-auto-build-deps` to disable:

```bash
nu scripts/build.nu --service cernbox-web --no-auto-build-deps
```

**Behavior when disabled:**

- Dependencies are checked for existence
- Build fails if dependencies are missing (legacy behavior)

### Flag Propagation

When auto-building dependencies, flags propagate as follows:

| Flag           | Propagation                         |
| -------------- | ----------------------------------- |
| `--cache-bust` | Always propagates (global override) |
| `--no-cache`   | Always propagates (global override) |
| `--push`       | Only if `--push-deps` set           |
| `--latest`     | Only if `--tag-deps` set            |
| `--extra-tag`  | Only if `--tag-deps` set            |
| `--provenance` | Always propagates                   |
| `--progress`   | Always propagates                   |

### Re-detection of Metadata

For each dependency build:

- `info` (registry info) is re-detected
- `meta` (build metadata) is re-detected

This ensures accurate metadata for recursive builds.

## Builder Configuration

Both development and CI builds use the same Buildx builder model: docker driver with a shared Docker daemon store.

### Unified Docker Driver

- **Dev builds**: Use the default Buildx builder (docker driver)
- **CI builds**: Workflows configure Buildx with `driver: docker` via `docker/setup-buildx-action`
- **Shared store**: Images built with `--load` go to the Docker daemon, which is the same store Buildx uses

### Dev vs CI Differences

The only differences between dev and CI are:

| Aspect | Dev | CI |
|--------|-----|-----|
| Tag prefixes | Local (`service:version`) | Registry path (`ghcr.io/owner/repo/service:version`) |
| Registry push | Manual (`--push`) | Workflow-controlled |
| Remote fallback | Never (local-only) | When local image not found |

### Why Unified Driver

Previously, CI used `docker-container` driver which has a separate cache from the Docker daemon. This caused issues where images built with `--load` were not visible to subsequent builds. The unified docker driver model ensures:

- Images built earlier in a workflow are visible to later builds
- `docker pull` warms the same store Buildx uses
- Consistent behavior between dev and CI

## Pre-Pull Mode

The `--pull` flag enables pre-pulling images before the build starts. This is useful for:

- **Cache warm-up**: Pre-populate the local Docker cache with dependency images
- **Fail-fast validation**: Verify external images exist before starting lengthy builds

### Local-First Image Resolution

The build system uses **local-first** image resolution for dependencies:

1. Check if image exists in local Docker daemon
2. Only check remote registry if local check fails (CI builds only)

This approach:

- Handles `--load` builds in CI (images exist locally but not remotely)
- Reduces registry calls for faster builds
- Works correctly for both local and CI environments

### Pull Modes

The `--pull` flag accepts comma-separated values:

| Mode       | Behavior                                       | On Failure     |
| ---------- | ---------------------------------------------- | -------------- |
| `deps`     | Pre-pull internal dependency images            | Warning (non-fatal) |
| `externals`| Pre-pull external images declared in manifests | Error (fatal)  |

**Usage examples:**

```bash
# Cache warm-up for dependencies
nu scripts/build.nu --service cernbox-web --pull=deps

# Fail-fast validation for external images
nu scripts/build.nu --service idp --pull=externals

# Both modes
nu scripts/build.nu --all-services --pull=deps,externals
```

### Deps Mode (Cache Warm-Up)

When `--pull=deps` is specified:

1. Compute build order for all services/versions to be built
2. For each node in build order, compute the canonical image reference
3. Attempt `docker pull` for each unique image
4. Log success/warning for each image (failures are non-fatal)
5. Continue to build phase

**Image reference format:**

- Multi-platform services: `{service}:{version}-{platform}` (e.g., `revad-base:v3.3.3-production`)
- Single-platform services: `{service}:{version}` (e.g., `gaia:v1.0.0`)
- In CI: Full registry path (e.g., `ghcr.io/owner/repo/revad-base:v3.3.3-production`)

### Externals Mode (Fail-Fast Preflight)

When `--pull=externals` is specified:

1. Compute build order for all services/versions to be built
2. For each node, load merged config and extract `external_images`
3. Resolve each external image to its effective reference (with env var overrides)
4. Aggregate and deduplicate across all nodes
5. Attempt `docker pull` for each unique external image
6. If any fail: report all failures and exit non-zero

**External image resolution:**

- Uses same logic as `process-external-images-to-build-args`
- Applies environment variable overrides via `get-env-or-config`
- Validates exactly what the build will use

**Error output example:**

```text
ERROR: External image preflight failed

  Missing: quay.io/keycloak/keycloak:26.4.2
    Required by: idp:v26.4.2
    Error: manifest unknown

  Missing: gcr.io/distroless/static-debian12:nonroot
    Required by: revad-base:v3.3.3:production
    Error: unauthorized
```

### Pull Summary

After pre-pull operations, a summary is displayed:

```text
=== Pull Summary ===
STATUS: SUCCESS

Dependencies (cache warm-up):
  Pulled: 3
  Skipped (deduped): 2
  Failed (non-fatal): 1

External Images (preflight):
  Pulled: 2
  Skipped (deduped): 0
  Failed (fatal): 0
```

### Dry-Run Modes

The `--pull` flag is ignored when using dry-run modes:

- `--matrix-json`: Outputs CI matrix JSON without any pull operations
- `--show-build-order`: Displays build order without any pull operations

### CI Usage Recommendations

1. **Use `--pull=externals` in CI** to fail fast on missing external images
2. **Use `--pull=deps` for cache warming** when you know images exist remotely
3. **Combine modes** (`--pull=deps,externals`) for comprehensive preflight checks

## Continue-on-Failure Mode

The build system supports continue-on-failure for multi-version builds.

### Default Failure Handling Behavior

- **Single service builds:** Fail fast (errors propagate immediately)
- **Multi-version builds:** Continue-on-failure (collect all failures, report summary)

### Fail-Fast Flag

Use `--fail-fast` to break on first failure (multi-version builds only):

```bash
nu scripts/build.nu --service revad-base --all-versions --fail-fast
```

### Build Summary

After multi-version builds, a machine-parseable summary is displayed:

```text
=== Build Summary ===
STATUS: PARTIAL
SUCCESS: 2
FAILED: 1
SKIPPED: 0

SUCCESS:
  - revad-base:v3.3.3
  - revad-base:v3.4.0

FAILED:
  - revad-base:v3.5.0
    Error: Build failed: ...

SKIPPED:
  - revad-base:v3.6.0
    Reason: Dependency build failed
```

**Status values:**

- `SUCCESS` - All builds succeeded
- `PARTIAL` - Some builds succeeded, some failed or were skipped
- `FAILED` - All builds failed

**Exit codes:**

- `0` - All builds succeeded
- `1` - Any builds failed or were skipped

**Note:** Single-service builds do not generate summaries - they fail fast on errors. Only multi-version builds (with or without platforms) generate summaries.

### Dependency Failure Handling

When auto-building dependencies:

- **Dependency build failures cause immediate stop** (fail fast, regardless of `--fail-fast` flag)
- Error message includes context (which service was being built, which dependency failed)
- Example: `Failed to build dependency 'revad-base:v3.3.3' while building 'cernbox-web:v1.0.0'`
- The `--fail-fast` flag only applies to multi-version builds of the target service, not dependency builds

## Building All Services

The `--all-services` flag enables building all discovered services in the repository in a single command. This is the modern equivalent of the legacy `build.sh` script's hardcoded build order.

### Service Discovery

The build system automatically discovers all services by:

1. Scanning the `services/` directory for subdirectories
2. Checking for a `.nuon` configuration file for each subdirectory
3. Filtering to services with version manifests (`versions.nuon`)
4. Services without version manifests are skipped with a warning

### Version Selection

Version selection for `--all-services` works per-service:

- **Default behavior**: Build the default version of each service (specified in `versions.nuon`)
- **`--all-versions`**: Build all versions of all services
- **`--latest-only`**: Build only versions marked `latest: true` in each service's manifest
- **`--version` and `--versions` flags**: Conflict with `--all-services` (use version selection flags instead)

### Platform Filtering

The `--platform` flag filters builds to a specific platform:

- Services with multi-platform support: Build only the specified platform variant
- Services without platform support or without the specified platform: Skipped with a warning
- No platform specified: Build all platform variants (or single-platform if no platforms manifest)

### Dependency Graph Merging

For `--all-services`, the build system:

1. Constructs a dependency graph for each `service:version:platform` combination
2. Merges all graphs into a single global graph
3. Deduplicates nodes (same `service:version:platform` from multiple services)
4. Deduplicates edges (same dependency relationship from multiple services)
5. Performs global topological sort to determine build order

**Example:**

```text
Services:
  - service-a:v1.0.0 (depends on common:v1.0.0)
  - service-b:v1.0.0 (depends on common:v1.0.0)

Merged Graph:
  nodes: [common:v1.0.0, service-a:v1.0.0, service-b:v1.0.0]
  edges: [
    {from: service-a:v1.0.0, to: common:v1.0.0},
    {from: service-b:v1.0.0, to: common:v1.0.0}
  ]

Build Order: [common:v1.0.0, service-a:v1.0.0, service-b:v1.0.0]
```

The dependency `common:v1.0.0` is built only once, even though both services depend on it.

### Build Order

The global build order ensures:

1. Dependencies are built before dependents
2. Each service is built only once (deduplicated)
3. Independent services can be visualized in the build order
4. Circular dependencies are detected and reported

Use `--show-build-order` to display the merged build order without executing builds:

```bash
nu scripts/build.nu --all-services --show-build-order
```

### Continue-on-Failure

By default, `--all-services` uses continue-on-failure mode:

- Build all services even if some fail
- Skip dependents of failed services
- Collect all successes, failures, and skipped services
- Print comprehensive summary at the end
- Exit with error code if any failures occurred

Use `--fail-fast` to stop on the first error:

```bash
nu scripts/build.nu --all-services --fail-fast
```

### Matrix JSON Generation

The `--all-services` flag works with `--matrix-json` to generate a CI matrix for all services:

- Respects `--all-versions` and `--latest-only` flags
- Respects `--platform` flag for platform filtering
- Each entry includes a `service` field to identify which service to build
- Matrix is deduplicated (same as build order)

```bash
# Generate matrix with default versions
nu scripts/build.nu --all-services --matrix-json

# Generate matrix with all versions
nu scripts/build.nu --all-services --matrix-json --all-versions

# Generate matrix for debian platform only
nu scripts/build.nu --all-services --matrix-json --platform debian
```

### Flag Conflicts

The `--all-services` flag conflicts with:

- `--service` - Cannot specify both a single service and all services
- `--version` - Use `--latest-only` or `--all-versions` instead
- `--versions` - Use `--latest-only` or `--all-versions` instead

### Auto-Build Dependencies Behavior

When using `--all-services`:

- `--no-auto-build-deps` is implicitly enabled
- Dependencies are handled by the global build order (not per-service auto-build)
- This avoids redundant builds and ensures consistent build order

## Build Script Flow

1. **Load service config** (`services/{service}.nuon`)
2. **Load version manifest** (`services/{service}/versions.nuon` - required)
3. **Parse CLI parameters** (`--version`, `--all-versions`, etc.)
4. **Resolve service version** (from manifest)
5. **Resolve dependencies**:
   - For each dependency in `dependencies` section:
     - Resolve tag (priority order above)
     - Construct image reference (local vs CI)
     - Check existence (fail if missing)
     - Prepare build arg injection
6. **Prepare build arguments**:
   - Base args (COMMIT_SHA, VERSION)
   - Dependency images (from step 5)
   - Component repo values (REVAD_REF, etc.)
   - Apply priority order (dependency > env > config > default)
7. **Build labels** (from config + git metadata)
8. **Execute build** (via buildx)

## File Structure

```text
scripts/
- build.nu                    # Main entrypoint
- lib/
  - meta.nu                 # Build context detection
  - manifest.nu             # Version manifest loading
  - matrix.nu               # CI matrix generation
  - dependencies.nu         # Dependency resolution
  - pull.nu                 # Pre-pull orchestration (--pull flag)
  - buildx.nu               # Docker buildx wrapper
  - registry/
    - registry-info.nu    # Registry path construction
    - registry.nu         # Registry authentication
```

## Error Handling

### Dependency Missing

- Check fails during dependency resolution
- Clear error message with build command suggestion
- Build aborts before starting

### Invalid Service Config

- Dependency service doesn't exist -> error
- Build arg not found in Dockerfile -> warning (Docker will fail)
- Circular dependencies -> detection and error

## Configuration Merging (Multi-Platform) {#configuration-merging-multi-platform}

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
2. **Sources**: Per-key replacement (not deep-merge) - see [Source Replacement](#source-replacement) below
3. **Records**: Deep-merged recursively (nested records merged, keys combined)
4. **Lists, strings, numbers**: Replaced entirely (platform config wins, same as dockerfile)

### Source Merging

Source configurations use **type-aware merging** that supports partial Git source overrides while preserving type safety.

**How it works:**

- **Git sources (url/ref)**: Field-level merging with mode detection
  - **Partial override** (only `ref` or only `url`): Missing field preserved from defaults
  - **Complete override** (both `url` and `ref`): Entire source replaced (backward compatible)
- **Local sources (path)**: Always replaced entirely (path is a single field)
- **Type switches** (Git to local or vice versa): Complete replacement (no merging of incompatible types)
- Sources from defaults that are **not** in overrides are **preserved**
- This applies to both global and platform-specific source overrides

**Example: Partial Git Override**

```nuon
// Defaults
defaults: {
  sources: {
    reva: { url: "https://github.com/cs3org/reva", ref: "v3.3.3" }
  }
}

// Override (partial - only ref)
overrides: {
  sources: {
    reva: { ref: "master" }  // url preserved from defaults
  }
}

// Result: sources.reva has {url: "https://github.com/cs3org/reva", ref: "master"}
```

**Example: Type Switch (Git to Local)**

```nuon
// Defaults
defaults: {
  sources: {
    gaia: { url: "...", ref: "v1.0.0" }
  }
}

// Override (type switch)
overrides: {
  sources: {
    gaia: { path: ".repos/gaia" }  // Replaces entire source (type switch)
  }
}

// Result: sources.gaia has only {path: ".repos/gaia"} (no url/ref)
```

**Rationale:**

- Partial Git overrides reduce duplication when multiple versions share the same repository URL but different refs
- Type switches (local to Git or vice versa) require complete replacement because `path` and `url`/`ref` are mutually exclusive
- The implementation in `scripts/lib/manifest.nu` detects source types and routes to appropriate merge functions

For complete details on multi-platform builds, see the [Multi-Platform Builds Guide](../guides/multi-platform-builds.md).

## Tag Generation

**Note:** The formulas below show tag names only. The service name is prefixed separately to create full image references (e.g., `service-name:tag-name`).

### Single-Platform (No platforms.nuon)

#### Tag Generation Formula (tag names only)

- Final tag names = `[name]` + (if `latest: true` then `["latest"]`) + `tags`
- Example: `name: "v1.0.0"`, `latest: true`, `tags: ["v1.0", "v1"]` -> Tag names: `["v1.0.0", "latest", "v1.0", "v1"]`
- Full image references: `service-name:v1.0.0`, `service-name:latest`, `service-name:v1.0`, `service-name:v1`

### Multi-Platform

#### Multi-Platform Tag Generation Formula (tag names only)

**For default platform:**

- `[name-platform]` + `[name]` (unprefixed) + (if `latest: true` then `["latest-platform"]` + `["latest"]` (unprefixed)) + `[tag-platform for each tag]` + `[tag]` (unprefixed for each tag)

**For other platforms:**

- `[name-platform]` + (if `latest: true` then `["latest-platform"]`) + `[tag-platform for each tag]`

**Summary:**

- Default platform gets both platform-suffixed and unprefixed versions of all tags (version name + latest + custom tags)
- Other platforms only get platform-suffixed tags
- Unprefixed tags always point to the default platform

#### Example

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
  - my-service:v1               (unprefixed custom tag, points to debian)

Other platforms (alpine):
  - my-service:v1.0.0-alpine    (name + alpine platform)
  - my-service:latest-alpine    (latest + alpine platform)
  - my-service:v1.0-alpine      (custom tag + alpine platform)
  - my-service:v1-alpine        (custom tag + alpine platform)
```

For complete details on tag generation, see the [Multi-Platform Builds Guide](../guides/multi-platform-builds.md).

## Best Practices

1. **Use per-service cache busting** for normal builds (default) - This ensures efficient caching while detecting source changes
2. **Use `--no-cache`** for release builds to ensure freshness - Forces complete rebuilds for production releases
3. **Let auto-build handle dependencies** (default behavior) - Simplifies workflow and ensures correct build order
4. **Use `--show-build-order`** to debug dependency issues - Visualize the dependency graph before building
5. **Review build summary** after multi-version builds - Check for partial failures and skipped builds
6. **Use `--pull=externals` in CI** to fail fast on missing external images - Catches missing images before lengthy builds

## See Also

- [Service Configuration](service-configuration.md) - How service configs are structured
- [Dependency Management](dependency-management.md) - How dependencies are resolved
- [TLS Management](tls-management.md) - How TLS certificates are handled
- [Multi-Platform Builds Guide](../guides/multi-platform-builds.md) - Platform configuration details
- [CLI Reference](../reference/cli-reference.md) - Complete CLI documentation
