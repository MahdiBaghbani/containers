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
# Getting Started

## Overview

Quick start guide for building container images with the DockyPody build system.

## Prerequisites

- Nushell 0.80 or later (`nu --version`)
- GNU Make
- OpenSSL
- Docker Engine

## Quick Start

### 1. Generate TLS Certificates (First Time Only)

```bash
make tls all
```

This generates:

- Shared CA certificate
- Service certificates for all services

### 2. Build a Service

```bash
# Build default version
nu scripts/build.nu --service revad-base

# Build specific version
nu scripts/build.nu --service revad-base --version v3.3.2

# Build all versions
nu scripts/build.nu --service revad-base --all-versions
```

### 3. Build All Services

```bash
make build
```

## Common Commands

### Version Management

```bash
# Build all versions from manifest
nu scripts/build.nu --service revad-base --all-versions

# Build specific versions
nu scripts/build.nu --service revad-base --versions v1.29.0,v1.28.0

# Build latest-marked only
nu scripts/build.nu --service revad-base --latest-only

# Generate CI matrix
nu scripts/build.nu --service revad-base --matrix-json
```

### Multi-Platform Builds

```bash
# Build all platforms for a version (requires platforms.nuon)
nu scripts/build.nu --service my-service --version v1.0.0

# Build specific platform only
nu scripts/build.nu --service my-service --version v1.0.0 --platform debian

# Build with platform suffix
nu scripts/build.nu --service my-service --version v1.0.0-alpine
```

## Next Steps

- [Service Setup Guide](service-setup.md) - Creating new services
- [Service Configuration](../concepts/service-configuration.md) - Understanding service configs
- [Multi-Version Builds Guide](multi-version-builds.md) - Version management
- [Multi-Platform Builds Guide](multi-platform-builds.md) - Platform variants
- [Nushell Development Guide](nushell-development.md) - If working on build scripts

## See Also

- [Service Configuration](../concepts/service-configuration.md) - Service config concepts
- [Build System](../concepts/build-system.md) - Build system architecture
- [CLI Reference](../reference/cli-reference.md) - Complete CLI documentation
