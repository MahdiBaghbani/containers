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

### Multi-Version Builds
```bash
# Build all versions from manifest
nu scripts/build.nu --service reva-base --all-versions

# Build specific versions
nu scripts/build.nu --service reva-base --versions v1.29.0,v1.28.0

# Generate CI matrix
nu scripts/build.nu --service reva-base --matrix-json
```

See [docs/version-manifests.md](docs/version-manifests.md) for details on version manifests.

### Library Modules (`scripts/lib/`)
- `lib/meta.nu` – Derive build type, tags, platforms from git/CI
- `lib/version.nu` – Derive service version based on strategy (component/repository)
- `lib/tags.nu` – Compute image tags based on version strategy and build context
- `lib/manifest.nu` – Load and merge version manifests
- `lib/matrix.nu` – Generate CI build matrices
- `lib/validate.nu` – Validate service configs and manifests
- `lib/buildx.nu` – Setup buildx and perform builds
- `lib/dependencies.nu` – Resolve internal service dependencies
- `lib/registry/registry-info.nu` – Parse git origin to derive registry paths
- `lib/registry/registry.nu` – Login to GHCR and Forgejo registries

Service Configuration
---------------------

Services are defined in `services/{service-name}.nuon`. New simplified format:

```nuon
{
  "name": "reva-base",
  "context": "services/reva-base",
  "dockerfile": "services/reva-base/Dockerfile",
  
  "sources": {
    "reva": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.2",
      "build_arg": "REVA_BRANCH"
    }
  },
  
  "external_images": {
    "build": {
      "image": "golang:1.25-trixie",
      "build_arg": "BASE_BUILD_IMAGE"
    }
  },
  
  "dependencies": {
    "reva-base": {
      "version": "v3.3.2",
      "build_arg": "REVA_BASE_IMAGE"
    }
  }
}
```

For multi-version builds, you can create `services/{service-name}/versions.nuon`. Check [docs/version-manifests.md](docs/version-manifests.md) for examples.

Conventions
-----------
- Release builds: multi-arch (linux/amd64, linux/arm64)
- Dev/Stage builds: linux/amd64 only, triggered by commit messages containing `(dev-build)` or `(stage-build)` (or `[dev-build]`, `[stage-build]`)
- Registries: GHCR (`ghcr.io`) and Forgejo (domain from git origin)
