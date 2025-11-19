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
# Build System

## Overview

The DockyPody build system orchestrates the container image build process, handling configuration merging, build argument injection, and build execution.

## Build Argument Injection Priority

When injecting build arguments, the build system applies them in this order (later steps override earlier ones):

1. **Base arguments** (COMMIT_SHA, VERSION)
2. **Source arguments** (auto-generated from `sources` section: `{SOURCE_KEY}_REF`, `{SOURCE_KEY}_URL`)
3. **External image arguments** (from `external_images` section)
4. **Config `build_args` section** (from service config)
5. **Environment variables** (can override config values for testing/debugging)
   - Environment variables can override config values (sources, external images, config `build_args`)
   - Example: `export REVAD_REF="custom"` overrides the auto-generated `REVAD_REF` from sources config
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

**Note:** Dependencies have the highest priority for dependency-related build arguments and will override environment variables. TLS arguments are added after dependencies but use a separate namespace (TLS_*) and don't conflict with dependency build args.

### Environment Variable Override Behavior

| Build Arg Type | Can Be Overridden by Env Var? | Reason |
|----------------|-------------------------------|--------|
| Source args (auto-generated) | **YES** | `REVAD_REF`, `REVAD_URL` can be overridden for testing |
| External image args | **YES** | `BASE_BUILD_IMAGE` can be overridden for testing |
| Config `build_args` | **YES** | `CUSTOM_ARG` can be overridden for testing |
| **Dependency args** | **NO** | Dependencies are system-managed and authoritative |
| **TLS args** | **NO** | TLS args use separate namespace (TLS_*) |

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
      "version": "v3.3.2",
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

**Final Build Arg Value:** `REVAD_BASE_IMAGE="revad-base:v3.3.2"`

#### Explanation

1. Dockerfile default: `revad-base:latest` (lowest priority, ignored)
2. Config `build_args`: `revad-base:custom` (overridden by env)
3. Environment variable: `revad-base:env-override` (overridden by dependency - dependencies win)
4. Dependency resolution: `revad-base:v3.3.2` (highest priority - wins, overrides env var)

The dependency resolution step constructs the image reference from the resolved dependency version (`v3.3.2`) and overrides all previous values, including environment variables.

## Cache Busting

The build system supports deterministic cache invalidation through the `CACHEBUST` build argument.

### Default Behavior (Per-Service)

By default, each service computes its own cache bust value using this fallback chain:

1. **Services with sources:** SHA256 hash of all source refs (first 16 characters)
   - Source keys are sorted before hashing for consistency
   - Example: `reva:v3.3.2,nushell:0.108.0` → `a1b2c3d4e5f6g7h8`
2. **Services without sources:** Git commit SHA (as-is, full SHA)
3. **Local builds (no Git):** `"local"`

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
4. Per-service computation (fallback chain: sources hash → Git SHA → "local")

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
ARG SOURCE_REF="v3.3.2"
RUN --mount=type=cache,id=service-source-git-${CACHEBUST:-${SOURCE_REF}},target=/cache,sharing=shared \
    git clone --branch "${SOURCE_REF}" ${SOURCE_URL} /cache
```

When CACHEBUST changes (SHA change, ref change, or manual override), Docker uses a new cache mount, ensuring fresh content after force-pushes. Build system always provides non-empty CACHEBUST value. CACHEBUST is computed as SHA256 hash of all source SHAs/refs (first 16 characters), using hybrid approach: SHA if available from extraction, ref if SHA extraction fails.

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
nu scripts/build.nu --service cernbox-web --show-build-order
```

## Automatic Dependency Building

By default, the build system automatically builds missing dependencies.

### Default Behavior

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

## Continue-on-Failure Mode

The build system supports continue-on-failure for multi-version builds.

### Default Behavior

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
  - revad-base:v3.3.2
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
- Example: `Failed to build dependency 'revad-base:v3.3.2' while building 'cernbox-web:v1.0.0'`
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
├── build.nu                    # Main entrypoint
└── lib/
    ├── meta.nu                 # Build context detection
    ├── manifest.nu             # Version manifest loading
    ├── matrix.nu               # CI matrix generation
    ├── dependencies.nu         # Dependency resolution
    ├── buildx.nu               # Docker buildx wrapper
    └── registry/
        ├── registry-info.nu    # Registry path construction
        └── registry.nu         # Registry authentication
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
  ↓
Platform Config (from platforms.nuon)
  ↓
Global Version Overrides (from versions.nuon)
  ↓
Platform-Specific Version Overrides (from versions.nuon)
  ↓
Final Config
```

### Merge Rules

1. **Dockerfile**: Replaced entirely (platform config wins)
2. **Records**: Deep-merged recursively (nested records merged, keys combined)
3. **Lists, strings, numbers**: Replaced entirely (platform config wins, same as dockerfile)

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

## See Also

- [Service Configuration](service-configuration.md) - How service configs are structured
- [Dependency Management](dependency-management.md) - How dependencies are resolved
- [TLS Management](tls-management.md) - How TLS certificates are handled
- [Multi-Platform Builds Guide](../guides/multi-platform-builds.md) - Platform configuration details
- [CLI Reference](../reference/cli-reference.md) - Complete CLI documentation
