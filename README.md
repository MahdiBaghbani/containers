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
Open Cloud Mesh Containers
===============

This repository hosts scripts and resources to build and publish container images for OCM services using separate workflows for GitHub Actions and Forgejo Actions.

Open Cloud Mesh Containers is based on a build system called DockyPody.

Workflows
---------

- GitHub: `.github/workflows/build-containers.yml`
- Forgejo: `.forgejo/workflows/build-containers.yml`

Scripts (Nushell)
-----------------

### Build Command

```bash
nu scripts/build.nu --service <service-name> [options]
```

**New Features:**

- **Build all services:** `--all-services` to build all discovered services in dependency order
- **Cache busting:** `--cache-bust <value>` or `--no-cache`
- **Auto-build dependencies:** Enabled by default (use `--no-auto-build-deps` to disable)
- **Build order:** `--show-build-order` to display without building
- **Continue-on-failure:** Default for multi-version builds (use `--fail-fast` to break early)

### Version Management Flags

All version-related flags for building services:

```bash
# Build default version from manifest
nu scripts/build.nu --service revad-base

# Build specific version
nu scripts/build.nu --service revad-base --version v1.29.0

# Build all versions from manifest
nu scripts/build.nu --service revad-base --all-versions

# Build specific versions (comma-separated)
nu scripts/build.nu --service revad-base --versions v1.29.0,v1.28.0

# Build only versions marked as latest
nu scripts/build.nu --service revad-base --latest-only

# Generate CI matrix JSON
nu scripts/build.nu --service revad-base --matrix-json
```

**Flag Distinction:**

- `--version <string>` - Build a single specific version
- `--versions <string>` - Build multiple versions (comma-separated list)
- `--all-versions` - Build all versions in manifest
- `--latest-only` - Build only versions with `latest: true`

See [docs/guides/multi-version-builds.md](docs/guides/multi-version-builds.md) for details on version manifests.

### Build All Services

```bash
# Build all services with default versions
nu scripts/build.nu --all-services

# Build all services, all versions
nu scripts/build.nu --all-services --all-versions

# Build all services for specific platform
nu scripts/build.nu --all-services --platform debian

# Show build order for all services
nu scripts/build.nu --all-services --show-build-order

# Generate CI matrix for all services
nu scripts/build.nu --all-services --matrix-json
```

**Features:**

- Discovers all services automatically
- Constructs global dependency graph with deduplication
- Builds in topological order (dependencies first)
- Continue-on-failure by default (use `--fail-fast` to stop on first error)
- Services without version manifests are skipped with a warning

See [docs/reference/cli-reference.md](docs/reference/cli-reference.md#all-services) for complete documentation.

### Multi-Platform Builds

```bash
# Build all platforms for a version (requires platforms.nuon)
nu scripts/build.nu --service my-service --version v1.0.0

# Build specific platform only
nu scripts/build.nu --service my-service --version v1.0.0 --platform debian

# Build with platform suffix
nu scripts/build.nu --service my-service --version v1.0.0-alpine
```

See [docs/guides/multi-platform-builds.md](docs/guides/multi-platform-builds.md) for details on multi-platform builds.

### Library Modules (`scripts/lib/`)

**Core Libraries:**

- `lib/common.nu` – Common utilities (path helpers, find-duplicates, require-ca, error handling, record utilities)
- `lib/constants.nu` – Build system constants (platforms, tags, labels, error messages, defaults)
- `lib/meta.nu` – Derive build type, tags, platforms from git/CI
- `lib/services.nu` – Service discovery and management

**Build System:**

- `lib/build-config.nu` – Build configuration parsing (bool flags, list flags, env overrides, build args processing)
- `lib/build-ops.nu` – Build operations (config loading, tag generation, label generation, TLS context management)
- `lib/buildx.nu` – Setup buildx and perform builds
- `lib/dependencies.nu` – Resolve internal service dependencies

**Versioning:**

- `lib/manifest.nu` – Load and merge version manifests
- `lib/platforms.nu` – Multi-platform build support and configuration merging
- `lib/matrix.nu` – Generate CI build matrices
- `lib/validate.nu` – Validate service configs and manifests

**TLS Management:**

- `lib/tls-validation.nu` – TLS certificate validation and CA synchronization

**Registry:**

- `lib/registry/registry-info.nu` – Parse git origin to derive registry paths
- `lib/registry/registry.nu` – Login to GHCR and Forgejo registries

### Testing

```bash
# Run all test suites
nu scripts/test.nu

# Run specific test suite
nu scripts/test.nu --suite manifests
nu scripts/test.nu --suite services
nu scripts/test.nu --suite tls

# Run with verbose output
nu scripts/test.nu --verbose
```

Tests are designed for development and debugging.

TLS Certificate Management
--------------------------

The build system implements selective TLS certificate copying for smaller, more secure images.

```bash
# Generate shared CA
nu scripts/tls/generate-ca.nu

# Generate all service certificates
nu scripts/tls/generate-all-certs.nu
```

Each service config can declare TLS requirements. During build, only the CA and service-specific certificate are copied into the image (not all certificates).

See [docs/concepts/tls-management.md](docs/concepts/tls-management.md) for complete TLS documentation.

Service Configuration
---------------------

Services are defined in `services/{service-name}.nuon`:

```nuon
{
  "name": "revad-base",
  "context": "services/revad-base",
  "dockerfile": "services/revad-base/Dockerfile",
  
  "sources": {
    "revad": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.2"
      // Auto-generates build args: REVAD_REF and REVAD_URL
    }
  },
  
  "external_images": {
    "build": {
      "image": "golang:1.25-trixie",
      "build_arg": "BASE_BUILD_IMAGE"
    }
  },
  
  "dependencies": {
    "revad-base": {
      "version": "v3.3.2",
      "build_arg": "REVAD_BASE_IMAGE"
    }
  }
}
```

**Source Build Args Convention:**

- Source keys must be lowercase alphanumeric with underscores
- Build args are auto-generated: `{SOURCE_KEY}_REF` and `{SOURCE_KEY}_URL`
- Example: `"nushell"` → `NUSHELL_REF` and `NUSHELL_URL`

See [docs/concepts/build-system.md](docs/concepts/build-system.md) and [docs/concepts/service-configuration.md](docs/concepts/service-configuration.md) for complete documentation.

For multi-version builds, you can create `services/{service-name}/versions.nuon`. Check [docs/guides/multi-version-builds.md](docs/guides/multi-version-builds.md) for examples.

Build System Enhancements
-------------------------

### Cache Busting

Deterministic cache invalidation via source refs hash:

```bash
# Per-service cache bust (default)
nu scripts/build.nu --service cernbox-web

# Global override
nu scripts/build.nu --service cernbox-web --cache-bust "abc123"

# Force full rebuild
nu scripts/build.nu --service cernbox-web --no-cache
```

### Automatic Dependency Building

Dependencies are automatically built if missing (default):

```bash
# Auto-build dependencies
nu scripts/build.nu --service cernbox-web

# Disable auto-build
nu scripts/build.nu --service cernbox-web --no-auto-build-deps

# Push dependencies
nu scripts/build.nu --service cernbox-web --push-deps

# Tag dependencies
nu scripts/build.nu --service cernbox-web --latest --tag-deps
```

### Build Order Resolution

View build order without building:

```bash
nu scripts/build.nu --service cernbox-web --show-build-order
```

### Continue-on-Failure

Multi-version builds continue on failure by default:

```bash
# Continue on failure (default)
nu scripts/build.nu --service revad-base --all-versions

# Fail fast
nu scripts/build.nu --service revad-base --all-versions --fail-fast
```

See [docs/concepts/build-system.md](docs/concepts/build-system.md) for complete documentation.

Conventions
-----------

- Release builds: multi-arch (linux/amd64, linux/arm64)
- Dev/Stage builds: linux/amd64 only, triggered by commit messages containing `(dev-build)` or `(stage-build)` (or `[dev-build]`, `[stage-build]`)
- Registries: GHCR (`ghcr.io`) and Forgejo (domain from git origin)
