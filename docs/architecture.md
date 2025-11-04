# Container Build System Architecture

## Overview

This document describes the architecture of the Open Cloud Mesh container build system, including dependency management, version resolution, and build orchestration.

## Core Concepts

### Service Configuration (`.nuon` files)

Each service has a configuration file in `services/{service-name}.nuon` that defines:
- Service metadata (name, context, dockerfile)
- Source repositories to build from
- External base images (not built by us)
- Dependencies (internal service dependencies)
- Build arguments
- Labels

### Versioning

Service versions are determined by:
1. **Version manifests** (`services/{service}/versions.nuon`) - For multi-version builds
2. **Git metadata** - For single-version builds (tags/branches)
3. **CLI overrides** - Using `--tag` or `--source-version` flags

## Dependency Management

### Dependency Declaration

Dependencies are declared in the `dependencies` section of service configs:

```nuon
{
  "dependencies": {
    "reva-base": {
      "service": "reva-base",
      "build_arg": "REVA_BASE_IMAGE",
      "tag": "latest"  // Optional: explicit version or "latest" for auto-resolve
    }
  }
}
```

**Key Points:**
- Dependencies are **internal services** only (built within this repo)
- External base images go in `base_images` section (for build/runtime stages)
- Each dependency maps to a specific build argument in the Dockerfile
- `tag` is optional - if omitted, version is auto-resolved (see Version Resolution)

### Build Argument Mapping

Dependencies are injected as build arguments with explicit names:
- Dependency name: `reva-base` → Build arg: `REVA_BASE_IMAGE`
- This allows multiple dependencies with clear, descriptive names

### Dockerfile Requirements

Dockerfiles must declare the build arg with a sensible default:

```dockerfile
ARG REVA_BASE_IMAGE="reva-base:latest"
FROM ${REVA_BASE_IMAGE}
```

**Default value serves as fallback:**
- Works when building Dockerfile directly (without build script)
- Will be overridden by build script during automated builds

## Version Resolution

### Service Version Resolution

The service's version is determined by:

1. **Version manifest** - If `versions.nuon` exists, version comes from manifest
2. **CLI overrides** - `--tag` or `--source-version` flags take precedence
3. **Git metadata** - Use git tag/branch/commit SHA from repository

### Dependency Version Resolution

Dependencies resolve their version in this priority order:

1. **Explicit version** in dependency config: `"version": "v3.3.2"` → always use this
2. **`--source-version` override**: Propagates to dependencies without explicit version
3. **Parent service version**: Inherit from parent if no explicit version
4. **Error**: If no version can be determined, build fails with clear error message

### Image Reference Construction

**Local builds:**
- Format: `{service}:{tag}`
- Example: `reva-base:v3.3.2`

**CI builds:**
- Format: `{registry}/{path}/{service}:{tag}`
- Example: `ghcr.io/open-cloud-mesh/containers/reva-base:v3.3.2`
- Both GHCR and Forgejo registries are used

## Build Argument Injection Priority

When injecting build arguments, priority order is:

1. **Dependency resolution** (highest priority)
   - Resolved dependency images always override
2. **Environment variables**
   - `REVA_BASE_IMAGE=...` from env
3. **Config `build_args` section**
   - `build_args: { REVA_BASE_IMAGE: "..." }`
4. **Dockerfile default** (lowest priority)
   - `ARG REVA_BASE_IMAGE="reva-base:latest"`

## CLI Parameters

### `--source-version`

Override the source version used for building and tagging:

**Component strategy services:**
```bash
nu scripts/build.nu --service reva-base --source-version v4.0.0
```
- Overrides `repos.reva_branch` from `v3.3.2` to `v4.0.0`
- Builds from `v4.0.0` branch/tag
- Tags output as `v4.0.0` (component version resolution)

**Repository strategy services:**
```bash
nu scripts/build.nu --service cernbox-reva --source-version v2
```
- Overrides repository tag to `v2`
- Tags output as `v2`
- Propagates to dependencies (e.g., `reva-base:v2`)

**Version propagation:**
- `--source-version` propagates to all dependencies without explicit tags
- Explicit dependency tags always take precedence

### `--tag`

Override the final output tag (separate from source version):

```bash
nu scripts/build.nu --service reva-base --source-version v4.0.0 --tag v4.0.0-dev
```
- Builds from `v4.0.0` source (from `--source-version`)
- Tags output as `v4.0.0-dev` (from `--tag`)

## Dependency Existence Check

Before building, the system checks if dependency images exist:

**Local builds:**
- Checks local Docker images: `docker images {service}:{tag}`
- Fails with error if missing

**CI builds:**
- Assumes dependencies are pre-built (earlier in workflow)
- Checks remote registries via `docker manifest inspect`
- Fails with error if missing

**Error message:**
```
Error: Dependency image 'reva-base:v2' not found.
Please build it first: nu scripts/build.nu --service reva-base --source-version v2
```

## Example: Component Strategy with Dependency

### `reva-base.nuon` (Component Strategy)
```nuon
{
  "name": "reva-base",
  "version_strategy": "component",
  "version_source": {
    "component": "reva_branch"
  },
  "repos": {
    "reva_branch": "v3.3.2"
  },
  "base_images": {
    "build": "golang:1.25-trixie",
    "runtime": "debian:trixie-slim"
  }
}
```

**Build output tags:**
- Primary: `reva-base:v3.3.2` (from component version)
- Latest: `reva-base:latest` (always tagged for component strategy)

### `cernbox-reva.nuon` (Repository Strategy with Dependency)
```nuon
{
  "name": "cernbox-reva",
  "version_strategy": "repository",
  "dependencies": {
    "reva-base": {
      "service": "reva-base",
      "build_arg": "REVA_BASE_IMAGE"
      // No explicit tag - auto-resolves
    }
  }
}
```

**Scenario 1: Default build**
```bash
nu scripts/build.nu --service cernbox-reva
```
- Service version: Repository tag (e.g., `main-abc123-dev`)
- Dependency resolves to: `reva-base:v3.3.2` (dependency's component version)

**Scenario 2: With source version**
```bash
nu scripts/build.nu --service cernbox-reva --source-version v2
```
- Service version: `v2` (from `--source-version`)
- Dependency resolves to: `reva-base:v2` (matches parent version)
- Build arg: `REVA_BASE_IMAGE=reva-base:v2`

### `cernbox-reva/Dockerfile`
```dockerfile
ARG REVA_BASE_IMAGE="reva-base:latest"
FROM ${REVA_BASE_IMAGE}

COPY ./configs/cernbox /configs/revad
# ... rest of Dockerfile
```

## Component Strategy Service with Dependency

### `cernbox-reva.nuon` (Component Strategy)
```nuon
{
  "name": "cernbox-reva",
  "version_strategy": "component",
  "version_component": "cernbox_version",
  "version_binding": "image_tag",
  "repos": {
    "cernbox_version": "v1"  // Default fallback
  },
  "dependencies": {
    "reva-base": {
      "service": "reva-base",
      "build_arg": "REVA_BASE_IMAGE"
      // No explicit tag - matches component version
    }
  }
}
```

**Scenario 1: Default build**
```bash
nu scripts/build.nu --service cernbox-reva
```
- Component version: `v1` (from `repos.cernbox_version`)
- Image tag: `cernbox-reva:v1`
- Dependency resolves to: `reva-base:v1` (matches component version)

**Scenario 2: With --tag**
```bash
nu scripts/build.nu --service cernbox-reva --tag v2
```
- Component version: `v2` (from `--tag` when `version_binding = "image_tag"`)
- Image tag: `cernbox-reva:v2`
- Dependency resolves to: `reva-base:v2` (matches component version)

**Scenario 3: With --source-version**
```bash
nu scripts/build.nu --service cernbox-reva --source-version v2
```
- Component version: `v2` (from `--source-version`)
- Image tag: `cernbox-reva:v2`
- Dependency resolves to: `reva-base:v2` (matches component version)

**Scenario 4: Override both**
```bash
nu scripts/build.nu --service cernbox-reva --source-version v2 --tag v2-custom
```
- Component version: `v2` (from `--source-version`, takes precedence)
- Image tag: `cernbox-reva:v2-custom` (from `--tag`)
- Dependency resolves to: `reva-base:v2` (matches component version, not tag)

## Build Script Flow

1. **Load service config** (`services/{service}.nuon`)
2. **Parse CLI parameters** (`--source-version`, `--tag`, etc.)
3. **Resolve service version** (using version strategy + overrides)
4. **Resolve dependencies**:
   - For each dependency in `dependencies` section:
     - Resolve tag (priority order above)
     - Construct image reference (local vs CI)
     - Check existence (fail if missing)
     - Prepare build arg injection
5. **Prepare build arguments**:
   - Base args (COMMIT_SHA, VERSION)
   - Dependency images (from step 4)
   - Component repo values (REVA_BRANCH, etc.)
   - Apply priority order (dependency > env > config > default)
6. **Build labels** (from config + git metadata)
7. **Execute build** (via buildx)

## File Structure

```
scripts/
├── build.nu                    # Main entrypoint
└── lib/
    ├── meta.nu                 # Build context detection
    ├── version.nu              # Version resolution
    ├── tags.nu                 # Tag computation
    ├── dependencies.nu         # Dependency resolution (NEW)
    ├── buildx.nu               # Docker buildx wrapper
    └── registry/
        ├── registry-info.nu    # Registry path construction
        └── registry.nu         # Registry authentication
```

## Error Handling

**Dependency missing:**
- Check fails during dependency resolution
- Clear error message with build command suggestion
- Build aborts before starting

**Invalid service config:**
- Dependency service doesn't exist → error
- Build arg not found in Dockerfile → warning (Docker will fail)
- Circular dependencies → detection and error

## Version Resolution Examples Summary

| Parent Strategy | Parent Version | Dependency Tag | Resolved Dependency | Reason |
|----------------|----------------|----------------|---------------------|--------|
| Repository | `v2` (from `--source-version`) | Not specified | `reva-base:v2` | Matches parent version |
| Repository | `main-abc123-dev` | Not specified | `reva-base:v3.3.2` | Dependency's component version |
| Component | `v1` (from component) | Not specified | `reva-base:v1` | Matches parent component version |
| Component | `v2` (from `--tag` when `version_binding=image_tag`) | Not specified | `reva-base:v2` | Matches parent component version |
| Any | Any | `v3.3.2` (explicit) | `reva-base:v3.3.2` | Explicit tag always wins |

## Version Manifests (Multi-Version Builds)

**NEW FEATURE:** Services can now support multiple versions through version manifests.

### Location
`services/{service-name}/versions.nuon`

### Purpose
Build multiple versions of the same service (e.g., Reva v1.29 and v1.28) from a single service definition, replacing legacy bash-based multi-version scripts.

### Schema

```nuon
{
  "default": "v1.29.0",           # Default version when no --version specified
  "versions": [
    {
      "name": "v1.29.0",           # Version identifier
      "latest": true,               # Tag as "latest"
      "tags": ["v1.29.0", "v1.29", "latest"],  # Image tags
      "overrides": {                # Override any base config field
        "sources": {
          "reva": { "ref": "v1.29.0" }
        },
        "build_args": { ... },
        "external_images": { ... }
      }
    }
  ]
}
```

### Multi-Version CLI Commands

```bash
# Build all versions
nu scripts/build.nu --service reva-base --all-versions

# Build specific versions
nu scripts/build.nu --service reva-base --versions v1.29.0,v1.28.0

# Build latest-marked only
nu scripts/build.nu --service reva-base --latest-only

# Generate CI matrix
nu scripts/build.nu --service reva-base --matrix-json
```

### CI Integration

```yaml
jobs:
  matrix:
    outputs:
      matrix: ${{ steps.gen.outputs.matrix }}
    steps:
      - run: nu scripts/build.nu --service reva-base --matrix-json
  
  build:
    strategy:
      matrix: ${{ fromJson(needs.matrix.outputs.matrix) }}
    steps:
      - run: nu scripts/build.nu --service reva-base --version ${{ matrix.version }}
```

**📖 Complete Guide:** [docs/version-manifests.md](version-manifests.md)

---

## Simplified Service Config Schema (NEW)

### New Fields (Recommended)

**`sources`** - Source repositories with explicit build arg mapping:
```nuon
"sources": {
  "reva": {
    "url": "https://github.com/cs3org/reva",
    "ref": "v3.3.2",
    "build_arg": "REVA_BRANCH"  # Explicit mapping!
  }
}
```

**`external_images`** - External Docker images (not built by us):
```nuon
"external_images": {
  "build": {
    "image": "golang:1.25-trixie",
    "build_arg": "BASE_BUILD_IMAGE"  # Explicit mapping!
  },
  "runtime": {
    "image": "debian:trixie-slim",
    "build_arg": "BASE_RUNTIME_IMAGE"
  }
}
```

**`dependencies`** - Internal services (built by us):
```nuon
"dependencies": {
  "reva-base": {
    "version": "v3.3.2",  # Optional: pin to version
    "build_arg": "REVA_BASE_IMAGE"
  }
}
```

### Benefits
- **Explicit** - Build args clearly mapped, no guessing
- **Self-Documenting** - Purpose of each field is clear
- **Separation of Concerns** - Sources vs external images vs dependencies

---

**Last Updated:** 2025-11-03
**Version:** 2.0
