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

# Service Setup Guide

## Overview

Step-by-step guide for creating and configuring new services in the DockyPody build system.

## Basic Service Setup

### 1. Create Service Directory

```bash
mkdir -p services/my-service
```

### 2. Create Service Configuration

Create `services/my-service.nuon`:

```nuon
{
  "name": "my-service",
  "context": "services/my-service",
  "dockerfile": "services/my-service/Dockerfile",
  "sources": {
    "my_source": {
      "url": "https://github.com/example/my_source",
      "ref": "v1.0.0"
    }
  },
  "external_images": {
    "build": {
      "name": "golang",
      "build_arg": "BASE_BUILD_IMAGE"
    },
    "runtime": {
      "name": "debian",
      "build_arg": "BASE_RUNTIME_IMAGE"
    }
  }
}
```

### 3. Create Version Manifest

**CRITICAL: All services MUST have version manifests.** This is a required file - the build system will fail without it. Create `services/my-service/versions.nuon`:

```nuon
{
  "default": "v1.0.0",
  "versions": [
    {
      "name": "v1.0.0",
      "latest": true,
      "overrides": {
        "sources": {
          "my_source": {"ref": "v1.0.0"}
        },
        "external_images": {
          "build": {"tag": "1.25-trixie"},
          "runtime": {"tag": "trixie-slim"}
        }
      }
    }
  ]
}
```

### 4. Create Dockerfile

Create `services/my-service/Dockerfile`:

```dockerfile
ARG BASE_BUILD_IMAGE="golang:1.25-trixie"
ARG BASE_RUNTIME_IMAGE="debian:trixie-slim"

ARG MY_SOURCE_URL="https://github.com/example/my_source"
ARG MY_SOURCE_REF="v1.0.0"
ARG MY_SOURCE_REF_KIND=""

FROM ${BASE_BUILD_IMAGE} AS build

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu \
    --mode git \
    --url "${MY_SOURCE_URL}" \
    --ref "${MY_SOURCE_REF}" \
    --ref-kind "${MY_SOURCE_REF_KIND}" \
    --dest /src/my_source

WORKDIR /src/my_source
# ... build steps ...

FROM ${BASE_RUNTIME_IMAGE}
# ... runtime steps ...
```

These ARG defaults are only fallbacks for direct Dockerfile invocation.
DockyPody injects the authoritative image tags from `versions.nuon` during
normal builds.

### 5. Build the Service

```bash
nu scripts/dockypody.nu build --service my-service
```

## Service with Dependency

### Example: `cernbox-revad` Service (Multi-Platform + Dependencies)

**Base config: `services/cernbox-revad.nuon`**

```nuon
{
  "name": "cernbox-revad",
  "context": "services/cernbox-revad"
}
```

**Platforms: `services/cernbox-revad/platforms.nuon`**

```nuon
{
  "default": "production",
  "defaults": {
    "external_images": {
      "build": {
        "name": "golang",
        "build_arg": "BASE_BUILD_IMAGE"
      }
    },
    "dependencies": {
      "common-tools": {
        "service": "common-tools",
        "build_arg": "COMMON_TOOLS_IMAGE"
      },
      "gaia": {
        "service": "gaia",
        "build_arg": "GAIA_IMAGE"
      },
      "revad-base": {
        "service": "revad-base",
        "build_arg": "REVAD_BASE_IMAGE"
      }
    }
  },
  "platforms": [
    {
      "name": "production",
      "dockerfile": "services/cernbox-revad/Dockerfile.production"
    },
    {
      "name": "development",
      "dockerfile": "services/cernbox-revad/Dockerfile.development"
    }
  ]
}
```

**Manifest: `services/cernbox-revad/versions.nuon`**

```nuon
{
  "default": "master",
  "defaults": {
    "external_images": {
      "build": {
        "tag": "1.25-trixie"
      }
    },
    "dependencies": {
      "common-tools": {
        "version": "v1.0.0-debian"
      },
      "gaia": {
        "version": "master",
        "single_platform": true
      }
    }
  },
  "versions": [
    {
      "name": "master",
      "latest": true,
      "overrides": {
        "platforms": {
          "production": {
            "dependencies": {
              "revad-base": {
                "version": "master-production"
              }
            }
          },
          "development": {
            "dependencies": {
              "revad-base": {
                "version": "master-development"
              }
            }
          }
        }
      }
    }
  ]
}
```

**Dockerfile:**

```dockerfile
ARG REVAD_BASE_IMAGE="revad-base:master-production"
FROM ${REVAD_BASE_IMAGE}

COPY ./configs/cernbox /configs/revad
# ... rest of Dockerfile
```

The platform Dockerfile ARG defaults are only non-authoritative fallbacks.
DockyPody injects the final dependency images from `platforms.nuon` plus
`versions.nuon` at build time.

**Build commands:**

```bash
# Build default version
nu scripts/dockypody.nu build --service cernbox-revad

# Build specific version and platform
nu scripts/dockypody.nu build --service cernbox-revad --version master --platform development
```

**Dependency resolution:**

- Service version: `master`
- Production dependency resolves to: `revad-base:master-production`
- Development dependency resolves to: `revad-base:master-development`
- `gaia` stays single-platform via `single_platform: true`, so it resolves
  without a platform suffix unless graph resolution fails

## Multiple Dependencies from Same Service

### Example: `cernbox-web` Service

This example demonstrates the advanced pattern of having multiple dependencies from the same service with different versions/platform variants:

**Base config: `services/cernbox-web.nuon`**

```nuon
{
  "name": "cernbox-web",
  "context": "services/cernbox-web",
  "labels": {
    "org.opencloudmesh.service": "cernbox-web"
  }
}
```

**Platform config: `services/cernbox-web/platforms.nuon`**

```nuon
{
  "default": "debian",
  "defaults": {
    "external_images": {
      "build": {
        "name": "node",
        "build_arg": "BASE_BUILD_IMAGE"
      },
      "runtime": {
        "name": "nginx",
        "build_arg": "BASE_RUNTIME_IMAGE"
      }
    },
    "dependencies": {
      "common-tools-builder": {
        "service": "common-tools",
        "build_arg": "COMMON_TOOLS_BUILDER_IMAGE"
      },
      "common-tools-runtime": {
        "service": "common-tools",
        "build_arg": "COMMON_TOOLS_RUNTIME_IMAGE"
      }
    }
  },
  "platforms": [
    {
      "name": "debian",
      "dockerfile": "services/cernbox-web/Dockerfile"
    }
  ]
}
```

**Version overrides:**

```nuon
{
  "default": "v1.0.0",
  "versions": [
    {
      "name": "v1.0.0",
      "latest": true,
      "overrides": {
        "dependencies": {
          "common-tools-builder": {
            "version": "v1.0.0-debian"
          },
          "common-tools-runtime": {
            "version": "v1.0.0-alpine"
          }
        }
      }
    }
  ]
}
```

**Use Case:**

- `cernbox-web` is a platformed service even though it currently exposes only one
  tracked platform
- Infrastructure fields (`dockerfile`, dependency build args, external image
  names) live in `platforms.nuon`
- Version-scoped data (source refs, dependency versions, external image tags)
  stays in `versions.nuon`
- Each dependency maps to a unique build argument for use in different Dockerfile stages

**Dependency resolution:**

- `common-tools-builder` resolves to: `common-tools:v1.0.0-debian`
- `common-tools-runtime` resolves to: `common-tools:v1.0.0-alpine`
- Build args: `COMMON_TOOLS_BUILDER_IMAGE=common-tools:v1.0.0-debian` and `COMMON_TOOLS_RUNTIME_IMAGE=common-tools:v1.0.0-alpine`

## Supporting Local Sources in Dockerfiles

For local development, Dockerfiles can support both Git sources (for CI/production) and local folder sources (for development). This dual-mode pattern allows you to test changes without committing to Git. Review the enforcement rules in [Dockerfile Development Rules](dockerfile-development.md) before editing service-specific Dockerfiles.

### Dual-Mode Dockerfile Pattern

To support both Git and local sources, declare ARGs for both modes and invoke
`clone-source.nu` once (see
[services/revad-base/Dockerfile.production](../../services/revad-base/Dockerfile.production)):

```dockerfile
# Git source args (for CI/production)
ARG REVAD_URL="https://github.com/cs3org/reva"
ARG REVAD_REF="v3.3.3"
ARG REVAD_REF_KIND=""
ARG REVAD_SHA=""

# Local source args (for development)
ARG REVAD_PATH=""
ARG REVAD_MODE=""

FROM ${BASE_BUILD_IMAGE} AS build

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu

RUN --mount=type=bind,source=${REVAD_PATH:-.},target=/src/local-revad,ro \
    --mount=type=cache,id=revad-git-${CACHEBUST:-${REVAD_REF}},target=/src/reva-git-cache,sharing=shared \
    nu /tmp/clone-source.nu \
    --mode "${REVAD_MODE:-git}" \
    --url "${REVAD_URL}" \
    --ref "${REVAD_REF}" \
    --ref-kind "${REVAD_REF_KIND}" \
    --local-dir /src/local-revad \
    --cache-dir /src/reva-git-cache \
    --dest /revad-git

WORKDIR /revad-git
# ... rest of build steps ...
```

### Pattern Explanation

1. **Declare all ARGs** - Include Git args (`_URL`, `_REF`, `_REF_KIND`,
   optional `_SHA`) and local args (`_PATH`, `_MODE`, `_REF_KIND`)
2. **Use clone-source.nu** - One helper handles local copy and git clone
   (branch/tag via `ref`, full SHA via `sha`)
3. **Bind mount local path** - Required so Docker can see `.build-sources/...`

**Why the bind mount matters:** local source directories are prepared inside the service context (for example `.build-sources/revad`). Docker build stages cannot see the host filesystem directly, so you must re-mount the prepared path inside the `RUN` step. Skipping the bind mount causes `cp` to fail with "No such file or directory," which was the root cause of recent local-source build failures.

### Example with Cache Mount

For better performance with Git sources, pass a cache directory to
`clone-source.nu`:

```dockerfile
ARG REVAD_URL="https://github.com/cs3org/reva"
ARG REVAD_REF="v3.3.3"
ARG REVAD_REF_KIND=""
ARG REVAD_PATH=""
ARG REVAD_MODE=""
ARG CACHEBUST="default"

FROM ${BASE_BUILD_IMAGE} AS build

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu

RUN --mount=type=bind,source=${REVAD_PATH:-.},target=/src/local-revad,ro \
    --mount=type=cache,id=revad-git-${CACHEBUST:-${REVAD_REF}},target=/src/reva-git-cache,sharing=shared \
    nu /tmp/clone-source.nu \
    --mode "${REVAD_MODE:-git}" \
    --url "${REVAD_URL}" \
    --ref "${REVAD_REF}" \
    --ref-kind "${REVAD_REF_KIND}" \
    --local-dir /src/local-revad \
    --cache-dir /src/reva-git-cache \
    --dest /revad-git

WORKDIR /revad-git
# ... rest of build steps ...
```

**Note:** Cache mounts are only used for Git sources. Local sources are copied
directly without cache.

### Migration from Git-Only Dockerfiles

To migrate an existing Dockerfile to support local sources:

1. **Add local source ARGs** after existing Git source ARGs:

   ```dockerfile
   ARG REVAD_PATH=""
   ARG REVAD_MODE=""
   ```

2. **Replace bare git clone with clone-source.nu** (add `_REF_KIND` ARG and
   COPY helper):

   ```dockerfile
   # Before (legacy):
   RUN git clone --branch ${REVAD_REF} ${REVAD_URL} /revad-git

   # After:
   ARG REVAD_REF_KIND=""
   COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
   RUN --mount=type=bind,source=${REVAD_PATH:-.},target=/src/local-revad,ro \
       nu /tmp/clone-source.nu \
       --mode "${REVAD_MODE:-git}" \
       --url "${REVAD_URL}" \
       --ref "${REVAD_REF}" \
       --ref-kind "${REVAD_REF_KIND}" \
       --local-dir /src/local-revad \
       --dest /revad-git
   ```

3. **Test both modes**:

   ```bash
   # Test with Git source (default)
   nu scripts/dockypody.nu build --service my-service

   # Test with local source
   export REVAD_PATH="../reva"
   nu scripts/dockypody.nu build --service my-service
   ```

### When to Use Local vs Git Sources

- **Use local sources** for:

  - Local development and testing
  - Iterative development without committing changes
  - Testing uncommitted modifications

- **Use Git sources** for:
  - CI/production builds (required - local sources are rejected)
  - Reproducible builds
  - Version tracking and labels

**Important:** Local sources are automatically rejected in CI/production builds. Always use Git sources for CI/CD pipelines.

## See Also

- [Service Configuration](../concepts/service-configuration.md) - Service config concepts
- [Dependency Management](../concepts/dependency-management.md) - Dependency resolution details
- [Multi-Version Builds Guide](multi-version-builds.md) - Version management
- [Config Schema Reference](../reference/config-schema.md) - Complete schema documentation
