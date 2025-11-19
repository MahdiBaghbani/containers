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
# Service Configuration

## Overview

Service configurations define how services are built, what sources they use, what dependencies they have, and how they're versioned. This document covers the structure and requirements for service configuration files. For step-by-step setup instructions, see the [Service Setup Guide](../guides/service-setup.md).

## Service Configuration Files (`.nuon` files)

**JSONC Compatibility Requirement (STRICT)**: All `.nuon` files MUST be valid JSONC (JSON with Comments) for syntax highlighting support. This means:

- **All keys MUST be quoted strings** (e.g., `"name"` not `name`)
- Trailing commas are allowed (JSONC feature)
- Comments are allowed (both `//` and `/* */` styles)
- All string values MUST be quoted

This requirement ensures compatibility with editors that use JSONC syntax highlighting for `.nuon` files. While NUON supports bare keys, JSONC does not, so quoted keys are required for proper syntax highlighting.

Each service has a configuration file in `services/{service-name}.nuon` that defines:

- Service metadata (name, context, dockerfile, tls)
- Source repositories to build from (single-platform only)
- External base images (not built by us) - infrastructure only (name, no tag)
- Dependencies (internal service dependencies) - infrastructure only (service, build_arg, no version)
- Build arguments
- Labels

**CRITICAL**: When `platforms.nuon` exists, base config can **ONLY** contain: `name`, `context`, `tls`. All other fields are forbidden and must be moved to `platforms.nuon` (infrastructure) or `versions.nuon` (versions).

## Dockerfile Requirement

- **Required** if the service is single-platform (no `platforms.nuon` exists)
- **Ignored/Replaced** if the service is multi-platform (has `platforms.nuon`) - each platform defines its own dockerfile in the platforms manifest, and the base config `dockerfile` field is completely replaced by platform-specific dockerfiles

## Versioning

**CRITICAL REQUIREMENT: All services MUST have version manifests** (`services/{service}/versions.nuon`).

The build system requires a version manifest for every service. Without it, builds will fail with a clear error message. This is not optional - it's a core requirement of the build system.

Service versions are specified in the manifest and selected via:

1. **`--version` flag** - Build specific version from manifest
2. **`--all-versions` flag** - Build all versions in manifest
3. **Default version** - If no flag provided, uses `default` from manifest

For complete details on version management, see the [Multi-Version Builds Guide](../guides/multi-version-builds.md).

## Configuration Structure

### Source Repositories

Source repositories are defined in the `sources` section and auto-generate build arguments.

**CRITICAL**: Source location depends on service type:

- **Single-platform**: Sources are **REQUIRED** in base config (versions.nuon can override, but base must have as fallback)
- **Multi-platform**: Sources are **FORBIDDEN** in base config (must be in versions.nuon overrides only)

**Single-platform example:**

```nuon
// services/my-service.nuon
{
  "sources": {
    "revad": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.2"
      // Auto-generates: REVAD_REF, REVAD_URL, and REVAD_SHA
    }
  }
}
```

**Multi-platform example:**

```nuon
// services/my-service.nuon (sources FORBIDDEN)
{
  "name": "my-service",
  "context": "services/my-service"
}

// services/my-service/versions.nuon (sources REQUIRED here)
{
  "overrides": {
    "sources": {
      "reva": {
        "url": "https://github.com/cs3org/reva",
        "ref": "v3.3.2"
      }
    }
  }
}
```

For complete details on source build args convention, see [Source Build Args](../source-build-args.md).

### External Images

External Docker images (not built by us) use separated `name` and `tag` fields. The `tag` field is **FORBIDDEN** in base config and must be defined in `versions.nuon` overrides.

**Single-platform example:**

```nuon
// services/my-service.nuon
{
  "external_images": {
    "build": {
      "name": "golang",
      "build_arg": "BASE_BUILD_IMAGE"
    }
  }
}

// services/my-service/versions.nuon
{
  "overrides": {
    "external_images": {
      "build": {
        "tag": "1.25-trixie"
      }
    }
  }
}
```

**Multi-platform example:**

```nuon
// services/my-service/platforms.nuon
{
  "platforms": [{
    "name": "debian",
    "external_images": {
      "build": {
        "name": "golang",
        "build_arg": "BASE_BUILD_IMAGE"
      }
    }
  }]
}

// services/my-service/versions.nuon
{
  "overrides": {
    "external_images": {
      "build": {
        "tag": "1.25-trixie"
      }
    }
  }
}
```

**Key rules:**

- `name` field: Infrastructure - defined in base config (single-platform) or platforms.nuon (multi-platform)
- `tag` field: Version control - **ALWAYS** defined in versions.nuon overrides (never in base config or platforms.nuon)
- `image` field: **FORBIDDEN** (legacy - use `name` instead)
- Tag can include digest: `"1.25-trixie@sha256:abc123..."` (digest is optional suffix to tag)

### Dependencies

Internal service dependencies are defined in the `dependencies` section. The `version` field is **FORBIDDEN** in base config and platforms.nuon - it must be defined in `versions.nuon` overrides.

**Single-platform example:**

```nuon
// services/my-service.nuon
{
  "dependencies": {
    "revad-base": {
      "build_arg": "REVAD_BASE_IMAGE"
    }
  }
}

// services/my-service/versions.nuon
{
  "overrides": {
    "dependencies": {
      "revad-base": {
        "version": "v3.3.2"
      }
    }
  }
}
```

For complete details, see [Dependency Management](dependency-management.md).

## Base Config Restrictions

**CRITICAL**: When `platforms.nuon` exists, base config can **ONLY** contain: `name`, `context`, `tls`, `labels` (all metadata).

All other fields (`dockerfile`, `external_images`, `sources`, `dependencies`, `build_args`) are **FORBIDDEN** in base config when `platforms.nuon` exists. These fields must be moved to:

- `platforms.nuon` - For infrastructure (name, build_arg, service, dockerfile)
- `versions.nuon` - For version control (tag, version, url, ref)

**Error example:**

```text
Service 'my-service': external_images.build: Field forbidden when platforms.nuon exists. Move to platforms.nuon (infrastructure) or versions.nuon (versions).
```

## Labels Configuration

Labels are Docker image metadata (OCI labels), similar to TLS configuration. They are **allowed in base config** even when `platforms.nuon` exists.

**Where labels can be defined:**

- **Base config** - Common labels for all platforms (allowed even when `platforms.nuon` exists)
- **platforms.nuon** - Platform-specific labels (deep-merged with base labels)
- **versions.nuon** - Version-specific label overrides (deep-merged with base/platform labels)

**Example:**

```nuon
// services/my-service.nuon (base config)
{
  "name": "my-service",
  "context": "services/my-service",
  "labels": {
    "org.opencontainers.image.title": "My Service",
    "org.opencontainers.image.description": "Service description"
  }
}

// services/my-service/platforms.nuon (platform-specific)
{
  "platforms": [{
    "name": "debian",
    "labels": {
      "org.opencontainers.image.base.name": "debian:trixie-slim"
    }
  }]
}
```

### Source Revision Labels

The build system automatically generates source revision labels for each source repository defined in the service configuration. These labels track the exact commit SHA used for each source, enabling precise version tracking and reproducibility.

#### Auto-Generated Labels

For each source, two labels are automatically generated:

1. **OCI Standard Label**: `org.opencontainers.image.source.{source_key}.revision`
2. **Custom Label**: `org.opencloudmesh.source.{source_key}.revision`

**Example:**

```nuon
// services/my-service.nuon
{
  "sources": {
    "reva": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.2"
    },
    "nushell": {
      "url": "https://github.com/nushell/nushell",
      "ref": "0.108.0"
    }
  }
}
```

**Generated Labels:**

- `org.opencontainers.image.source.reva.revision=2912f0a` (extracted from tag `v3.3.2`)
- `org.opencloudmesh.source.reva.revision=2912f0a`
- `org.opencloudmesh.source.reva.ref=v3.3.2`
- `org.opencloudmesh.source.reva.url=https://github.com/cs3org/reva`
- `org.opencontainers.image.source.nushell.revision=da141be` (extracted from tag `0.108.0`)
- `org.opencloudmesh.source.nushell.revision=da141be`
- `org.opencloudmesh.source.nushell.ref=0.108.0`
- `org.opencloudmesh.source.nushell.url=https://github.com/nushell/nushell`

#### Missing SHA Handling

When SHA extraction fails (network error, git unavailable, invalid ref), labels include a `missing:` prefix:

- `org.opencontainers.image.source.reva.revision=missing:v3.3.2`
- `org.opencloudmesh.source.reva.revision=missing:v3.3.2`

This clearly indicates that SHA extraction failed and the ref value is used instead.

#### User Label Overrides

You can override auto-generated source revision labels by defining them manually in your service configuration:

```nuon
{
  "sources": {
    "reva": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.2"
    }
  },
  "labels": {
    "org.opencontainers.image.source.reva.revision": "custom-sha-value"
  }
}
```

**Warning Behavior:**

When a user-defined label conflicts with an auto-generated source revision label, the build system:

1. Prints a warning message indicating the conflict
2. Uses the user-defined value (user labels take precedence)
3. Continues the build normally

**Warning Example:**

```text
WARNING: [my-service] User-defined label 'org.opencontainers.image.source.reva.revision' overrides generated source revision label. Using user value: custom-sha-value
```

#### Label Format

- **SHA Value**: 7-character hexadecimal string (e.g., `2912f0a`)
- **Missing SHA**: `missing:{ref}` format (e.g., `missing:v3.3.2`)
- **Source Key**: Lowercase alphanumeric with underscores (matches source key from config)

For complete details on SHA extraction and caching, see [Source Build Args](../source-build-args.md#sha-extraction).

## TLS Configuration

TLS configuration is **ONLY** allowed in base config. It is **FORBIDDEN** in `platforms.nuon` and `versions.nuon`.

TLS config is considered metadata (not infrastructure or version control), so it stays in base config even when `platforms.nuon` exists.

## See Also

- [Dependency Management](dependency-management.md) - How dependencies work and are resolved
- [Build System](build-system.md) - How the build system processes configurations
- [Multi-Version Builds Guide](../guides/multi-version-builds.md) - Version manifest details
- [Source Build Args](../source-build-args.md) - Source build argument naming convention
- [Config Schema Reference](../reference/config-schema.md) - Complete schema documentation
