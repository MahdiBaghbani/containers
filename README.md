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

# Open Cloud Mesh Containers

This repository hosts scripts and resources to build and publish container images for OCM services using DockyPody, a Nushell-based build system.

## Quick Start

1. **Generate TLS certificates:**

   ```bash
   make tls all
   ```

2. **Build a service:**

   ```bash
   nu scripts/build.nu --service <service-name>
   ```

For complete setup instructions, see [Getting Started Guide](docs/guides/getting-started.md).

## Key Features

- **Multi-platform builds** - Build for multiple architectures (linux/amd64, linux/arm64)
- **Version management** - Build multiple versions from manifests with automatic tagging
- **Dependency resolution** - Automatic dependency building with correct build order
- **Cache optimization** - Deterministic cache busting for efficient rebuilds
- **TLS management** - Selective certificate copying for secure, minimal images

See [Build System](docs/concepts/build-system.md) for complete feature documentation.

## Documentation

### For New Users

- [Getting Started](docs/guides/getting-started.md) - Quick start tutorial
- [Service Configuration](docs/concepts/service-configuration.md) - Understanding service configs

### For Developers

- [Nushell Development Guide](docs/guides/nushell-development.md) - Essential before editing scripts
- [Build System](docs/concepts/build-system.md) - Build system architecture

### For Service Authors

- [Service Setup Guide](docs/guides/service-setup.md) - Creating new services
- [Multi-Version Builds](docs/guides/multi-version-builds.md) - Version management
- [Multi-Platform Builds](docs/guides/multi-platform-builds.md) - Platform variants

### Reference Documentation

- [CLI Reference](docs/reference/cli-reference.md) - Complete CLI documentation
- [Config Schema](docs/reference/config-schema.md) - Service configuration schema
- [Version Manifest Schema](docs/reference/version-manifest-schema.md) - Version manifest schema
- [Platform Manifest Schema](docs/reference/platform-manifest-schema.md) - Platform manifest schema

See [Documentation Index](docs/index.md) for complete documentation listing.

## Service Configuration

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
    }
  }
}
```

See [Service Configuration](docs/concepts/service-configuration.md) for complete documentation.

## Workflows

CI/CD workflows are available for GitHub Actions and Forgejo Actions:

- GitHub: `.github/workflows/build-containers.yml`
- Forgejo: `.forgejo/workflows/build-containers.yml`

See [CI/CD Workflows](docs/guides/ci-cd.md) for workflow documentation (pending).

## Conventions

- Release builds: multi-arch (linux/amd64, linux/arm64)
- Dev/Stage builds: linux/amd64 only, triggered by commit messages containing `(dev-build)` or `(stage-build)`
- Registries: GHCR (`ghcr.io`) and Forgejo (domain from git origin)
