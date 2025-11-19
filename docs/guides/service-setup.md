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
    "my-source": {
      "url": "https://github.com/example/my-source",
      "ref": "v1.0.0"
    }
  },
  "external_images": {
    "build": {
      "image": "golang:1.25-trixie",
      "build_arg": "BASE_BUILD_IMAGE"
    },
    "runtime": {
      "image": "debian:trixie-slim",
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
          "my-source": {"ref": "v1.0.0"}
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

ARG MY_SOURCE_URL="https://github.com/example/my-source"
ARG MY_SOURCE_REF="v1.0.0"

FROM ${BASE_BUILD_IMAGE} AS build
# ... build steps ...

FROM ${BASE_RUNTIME_IMAGE}
# ... runtime steps ...
```

### 5. Build the Service

```bash
nu scripts/build.nu --service my-service
```

## Service with Dependency

### Example: `cernbox-revad` Service (Depends on revad-base)

**Config: `services/cernbox-revad.nuon`**

```nuon
{
  "name": "cernbox-revad",
  "context": "services/cernbox-revad",
  "dockerfile": "services/cernbox-revad/Dockerfile",
  "dependencies": {
    "revad-base": {
      "version": "v3.3.2",
      "build_arg": "REVAD_BASE_IMAGE"
    }
  }
}
```

**Manifest: `services/cernbox-revad/versions.nuon`**

```nuon
{
  "default": "v3.3.2",
  "versions": [
    {
      "name": "v3.3.2",
      "latest": true,
      "overrides": {
        "dependencies": {
          "revad-base": {"version": "v3.3.2"}
        }
      }
    }
  ]
}
```

**Dockerfile:**

```dockerfile
ARG REVAD_BASE_IMAGE="revad-base:latest"
FROM ${REVAD_BASE_IMAGE}

COPY ./configs/cernbox /configs/revad
# ... rest of Dockerfile
```

**Build commands:**

```bash
# Build default version
nu scripts/build.nu --service cernbox-revad

# Build specific version
nu scripts/build.nu --service cernbox-revad --version v3.3.2
```

**Dependency resolution:**

- Service version: `v3.3.2`
- Dependency resolves to: `revad-base:v3.3.2` (explicit in manifest)
- Build arg: `REVAD_BASE_IMAGE=revad-base:v3.3.2`

## Multiple Dependencies from Same Service

### Example: `cernbox-web` Service

This example demonstrates the advanced pattern of having multiple dependencies from the same service with different versions/platform variants:

**Config: `services/cernbox-web.nuon`**

```nuon
{
  "name": "cernbox-web",
  "context": "services/cernbox-web",
  "dockerfile": "services/cernbox-web/Dockerfile",
  "dependencies": {
    "common-tools-builder": {
      "service": "common-tools",
      "version": "v1.0.0-debian",
      "build_arg": "COMMON_TOOLS_BUILDER_IMAGE"
    },
    "common-tools-runtime": {
      "service": "common-tools",
      "version": "v1.0.0-alpine",
      "build_arg": "COMMON_TOOLS_RUNTIME_IMAGE"
    }
  }
}
```

**Use Case:**

- Builder stage needs Debian variant of `common-tools` (for build tools)
- Runtime stage needs Alpine variant of `common-tools` (for smaller image size)
- Both dependencies reference the same service (`common-tools`) but with different platform variants
- Each dependency maps to a unique build argument for use in different Dockerfile stages

**Dependency resolution:**

- `common-tools-builder` resolves to: `common-tools:v1.0.0-debian`
- `common-tools-runtime` resolves to: `common-tools:v1.0.0-alpine`
- Build args: `COMMON_TOOLS_BUILDER_IMAGE=common-tools:v1.0.0-debian` and `COMMON_TOOLS_RUNTIME_IMAGE=common-tools:v1.0.0-alpine`

## See Also

- [Service Configuration](../concepts/service-configuration.md) - Service config concepts
- [Dependency Management](../concepts/dependency-management.md) - Dependency resolution details
- [Multi-Version Builds Guide](multi-version-builds.md) - Version management
- [Config Schema Reference](../reference/config-schema.md) - Complete schema documentation
