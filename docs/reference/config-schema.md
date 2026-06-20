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

# Service Configuration Schema

## Overview

Complete reference for the service configuration schema (`.nuon` files).

## Schema Location

Service configurations are stored as `.nuon` files in the `services/`
directory:

- `services/{name}.nuon` - Base service configuration
- `services/{name}/versions.nuon` - Required version manifest
- `services/{name}/platforms.nuon` - Optional platform manifest with one or
  more platform entries

DockyPody also auto-injects `org.opencloudmesh.service=<service name>` at
build time, so you do not need to duplicate that label in each manifest.

For the authoritative schema file, see
[`schemas/service.nuon`](../../schemas/service.nuon).

## Local-Plane Root (Off-Git)

DockyPody supports a `--plane local` mode on `build` and `validate`. In this
release, the local plane is a **root presence contract** only: it does not
change service discovery, topology resolution, or source materialization.

**Tracked plane (default):** Service configurations are discovered from
tracked manifests under `services/` as documented in [Schema
Location](#schema-location).

**Local plane:** Activates the off-git local plane root at
`.dockypody.local/` at the repository root. Pass `--plane local` on `build`
or `validate`; the default is `--plane tracked`.

**Root presence rules:**

- `--plane local` hard-errors when `.dockypody.local/` does not exist.
- An empty `.dockypody.local/` directory alone is valid.
- An optional `.dockypody.local/services/` directory with zero service
  mirrors is also valid.

**What local plane does not do in this release:**

- Service discovery still uses tracked `services/*.nuon` only. Contents of
  `.dockypody.local/services/` are not used for discovery.
- No local topology or source-materialization contract is defined yet beyond
  root presence.

For CLI details, see [`--plane` in the CLI
reference](cli-reference.md#config-plane-flag).

## JSONC Compatibility Requirement

**CRITICAL**: All `.nuon` files MUST be valid JSONC (JSON with Comments) for syntax highlighting support.

**Requirements:**

- **All keys MUST be quoted strings** (e.g., `"name"` not `name`)
- Trailing commas are allowed (JSONC feature)
- Comments are allowed (both `//` and `/* */` styles)
- All string values MUST be quoted

## Source Build Args (Auto-Generated)

**`sources`** - Source repositories with auto-generated build args:

**CRITICAL**: Source location depends on service type:

- **Without `platforms.nuon`**: Sources are allowed in base config, but they
  are not required there. They may live entirely in `versions.nuon` defaults
  or overrides if the merged config is still complete.
- **Services using `platforms.nuon`**: Sources are **FORBIDDEN** in base config
  and must live in `versions.nuon` defaults or overrides.

### Single-Platform Example

```nuon
// services/my-service.nuon
{
  "sources": {
    "reva": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.3"
    }
  }
}

// services/my-service/versions.nuon (optional override)
{
  "overrides": {
    "sources": {
      "reva": {
        "ref": "v3.3.3-custom"
      }
    }
  }
}
```

### Example: Service Using `platforms.nuon`

```nuon
// services/my-service.nuon (sources FORBIDDEN here)
{
  "name": "my-service",
  "context": "services/my-service"
}

// services/my-service/versions.nuon (sources defined here)
{
  "overrides": {
    "sources": {
      "reva": {
        "url": "https://github.com/cs3org/reva",
        "ref": "v3.3.3"
      }
    }
  }
}
```

### Source Types

Sources can be either **Git repositories** or **local folders** (development only):

#### Git Sources

Git sources use `url` and `ref` fields:

```nuon
{
  "sources": {
    "reva": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.3"
    }
  }
}
```

**Build args generated:** `{SOURCE_KEY}_REF`, `{SOURCE_KEY}_URL`, `{SOURCE_KEY}_SHA`

#### Local Sources (Development Only)

Local sources use `path` field (mutually exclusive with `url`/`ref`):

```nuon
{
  "sources": {
    "reva": {
      "path": "../reva"  // Relative to repository root
    }
  }
}
```

**Build args generated:** `{SOURCE_KEY}_PATH`, `{SOURCE_KEY}_MODE="local"`

**CRITICAL RESTRICTIONS:**

- **Development only** - Local sources are **REJECTED** in CI/production builds
- **Mutually exclusive** - Cannot have both `path` and `url`/`ref` fields
- **Path validation** - Paths must exist, be directories, and stay within the
  repository root, or within a sibling `repos/` workspace parent when this repo
  itself lives under `repos/`
- **No SHA generation** - Local sources do not generate `{SOURCE_KEY}_SHA`
  build args

**Path Resolution:**

- **Relative paths** - Resolved relative to repository root
- **Absolute paths** - Allowed when they still resolve inside the repository
  root or the sibling `repos/` workspace parent described above
- **Environment variable override** - Can override using `{SOURCE_KEY}_PATH`
  env var

For complete details, see [Source Build Arguments Convention](../concepts/service-configuration.md#source-build-arguments-convention).

### Naming Convention

- Source key must be lowercase alphanumeric with underscores: `^[a-z0-9_]+$`
- Build args are auto-generated based on source type:
  - Git sources: `{SOURCE_KEY}_REF`, `{SOURCE_KEY}_URL`, `{SOURCE_KEY}_SHA`
  - Local sources: `{SOURCE_KEY}_PATH`, `{SOURCE_KEY}_MODE`
- Example: `"web_extensions"` (Git) -> `WEB_EXTENSIONS_REF`, `WEB_EXTENSIONS_URL`, `WEB_EXTENSIONS_SHA`
- Example: `"reva"` (local) -> `REVA_PATH`, `REVA_MODE="local"`

## External Images

**`external_images`** - External Docker images (not built by us):

**CRITICAL**: External images use separated `name` and `tag` fields. The `tag` field is **FORBIDDEN** in base config and must be defined in `versions.nuon` overrides.

### Services Without `platforms.nuon`

For services without `platforms.nuon`, define `name` in base config and `tag`
in version overrides:

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
  "versions": [{
    "name": "v1.0.0",
    "overrides": {
      "external_images": {
        "build": {
          "tag": "1.25-trixie"
        }
      }
    }
  }]
}
```

### Services Using `platforms.nuon`

For services using `platforms.nuon`, define `name` there and `tag` in version
overrides:

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
  "versions": [{
    "name": "v1.0.0",
    "overrides": {
      "external_images": {
        "build": {
          "tag": "1.25-trixie"
        }
      }
    }
  }]
}
```

### Validation Rules

- Each `external_images` entry MUST include `name` and `build_arg` fields
- `tag` field is **FORBIDDEN** in base config and `platforms.nuon` (must be in `versions.nuon` overrides)
- `image` field is **FORBIDDEN** (legacy - use `name` instead)
- Without `platforms.nuon`: `name` required in base config
- With `platforms.nuon`: `name` required in `platforms.nuon`
- `tag` is **ALWAYS** required in `versions.nuon` overrides (no base fallback)
- Tag can include digest: `"1.25-trixie@sha256:abc123..."` (digest is optional suffix to tag)
- Validation occurs during service configuration loading (before build starts)
- Build fails immediately if validation errors are found

### Error Examples

```text
Service 'my-service': external_images.build.tag: Field forbidden. Define in versions.nuon overrides.
Merged config: external_images.build: Missing required field 'tag'. Define in versions.nuon overrides.external_images.build.tag.
```

## Dependencies

**`dependencies`** - Internal services (built by us):

**CRITICAL**: The `version` field is **FORBIDDEN** in base config and `platforms.nuon`. Version must be defined in `versions.nuon` overrides.

### Dependencies: Services Without `platforms.nuon`

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
  "versions": [{
    "name": "v1.0.0",
    "overrides": {
      "dependencies": {
        "revad-base": {
          "version": "v3.3.3"
        }
      }
    }
  }]
}
```

### Dependencies: Services Using `platforms.nuon`

```nuon
// services/my-service/platforms.nuon
{
  "platforms": [{
    "name": "debian",
    "dependencies": {
      "common-tools": {
        "service": "common-tools",
        "build_arg": "COMMON_TOOLS_IMAGE"
      }
    }
  }]
}

// services/my-service/versions.nuon
{
  "versions": [{
    "name": "v1.0.0",
    "overrides": {
      "dependencies": {
        "common-tools": {
          "version": "v1.0.0-debian"
        },
        "gaia": {
          "version": "master",
          "single_platform": true  // Optional: Dependency is single-platform, use same version for all parent platforms
        }
      }
    }
  }]
}
```

### The `single_platform` Field

**`single_platform`** - Optional boolean field in dependency configs (version control only):

- **Location**: `versions.nuon` overrides only (forbidden in base config and `platforms.nuon`)
- **Purpose**: Explicitly mark that a dependency is single-platform and should use the same version across all parent platforms
- **Behavior**:
  - `single_platform: true` - Suppresses informational message when using single-platform dependency
  - `single_platform: false` - Treated as not set (only `true` has meaning)
- **Precedence**: Platform suffix in version always takes precedence over `single_platform` flag

**Example:**

```nuon
{
  "dependencies": {
    "gaia": {
      "version": "master",
      "single_platform": true  // Suppresses "Info:" message
    }
  }
}
```

### Dependencies: Validation Rules

- Each dependency MUST include `build_arg` field
- `version` field is **FORBIDDEN** in base config and `platforms.nuon` (must be in `versions.nuon` overrides)
- `single_platform` field is **FORBIDDEN** in base config and `platforms.nuon` (must be in `versions.nuon` overrides)
- `single_platform` must be boolean if present
- Without `platforms.nuon`: dependencies defined in base config with
  `service` and `build_arg`
- With `platforms.nuon`: dependencies defined in `platforms.nuon` with
  `service` and `build_arg`
- Version is **ALWAYS** defined in `versions.nuon` overrides (never in base config or platforms.nuon)

For complete details on dependency resolution, see [Dependency Management](../concepts/dependency-management.md).

## Base Config Restrictions

**CRITICAL**: When `platforms.nuon` exists, base config can **ONLY** contain: `name`, `context`, `tls`, `ssh`, `labels` (all metadata).

All other fields (`dockerfile`, `external_images`, `sources`, `dependencies`, `build_args`) are **FORBIDDEN** in base config when `platforms.nuon` exists.

**Note:** Labels are Docker image metadata (like TLS), not infrastructure or version control, so they are allowed in base config even when `platforms.nuon` exists.

**Error example:**

```text
Service 'my-service': external_images.build: Field forbidden when platforms.nuon exists. Move to platforms.nuon (infrastructure) or versions.nuon (versions).
```

## Complete Schema Example (Single-Platform)

```nuon
// services/my-service.nuon
{
  "name": "service-name",
  "context": "services/service-name",
  "dockerfile": "services/service-name/Dockerfile",

  "sources": {
    "reva": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.3"
    }
  },

  "external_images": {
    "build": {
      "name": "golang",
      "build_arg": "BASE_BUILD_IMAGE"
    }
  },

  "dependencies": {
    "revad-base": {
      "build_arg": "REVAD_BASE_IMAGE"
    }
  },

  "build_args": {
    "CUSTOM_ARG": "value"
  },

  "labels": {
    "org.opencontainers.image.title": "Service Name"
  },

  "tls": {
    "enabled": true,
    "mode": "ca-and-cert",
    "cert_name": "service",
    "instances": 1,
    "domain_suffix": "docker",
    "sans": ["DNS:service.docker"]
  },

  "ssh": {
    "enabled": true,
    "mode": "server",
    "default_user": "root",
    "port": 22,
    "listen": "0.0.0.0"
  }
}

// services/my-service/versions.nuon
{
  "default": "v1.0.0",
  "versions": [{
    "name": "v1.0.0",
    "latest": true,
    "overrides": {
      "external_images": {
        "build": {
          "tag": "1.25-trixie"
        }
      },
      "dependencies": {
        "revad-base": {
          "version": "v3.3.3"
        }
      }
    }
  }]
}
```

## Complete Schema Example (Service Using `platforms.nuon`)

```nuon
// services/my-service.nuon (metadata only)
{
  "name": "service-name",
  "context": "services/service-name",
  "tls": {
    "enabled": false
  },
  "ssh": {
    "enabled": false,
    "mode": "disabled"
  }
}

// services/my-service/platforms.nuon
{
  "default": "debian",
  "platforms": [{
    "name": "debian",
    "dockerfile": "services/my-service/Dockerfile.debian",
    "external_images": {
      "build": {
        "name": "golang",
        "build_arg": "BASE_BUILD_IMAGE"
      }
    },
    "dependencies": {
      "revad-base": {
        "build_arg": "REVAD_BASE_IMAGE"
      }
    }
  }]
}

// services/my-service/versions.nuon
{
  "default": "v1.0.0",
  "versions": [{
    "name": "v1.0.0",
    "latest": true,
    "overrides": {
      "sources": {
        "reva": {
          "url": "https://github.com/cs3org/reva",
          "ref": "v3.3.3"
        }
      },
      "external_images": {
        "build": {
          "tag": "1.25-trixie"
        }
      },
      "dependencies": {
        "revad-base": {
          "version": "v3.3.3"
        }
      }
    }
  }]
}
```

## Edge Case Examples

### Multiple Sources with Underscores

When using source keys with underscores, build args are generated with uppercase underscores:

```nuon
{
  "sources": {
    "web_extensions": {
      "url": "https://github.com/cernbox/web-extensions",
      "ref": "main"
    },
    "custom_lib": {
      "url": "https://github.com/example/custom-lib",
      "ref": "v2.0.0"
    }
  }
}
```

### Generated Build Args

- `WEB_EXTENSIONS_REF`, `WEB_EXTENSIONS_URL`
- `CUSTOM_LIB_REF`, `CUSTOM_LIB_URL`

### Complex Dependency Chain

Service depending on multiple services with different versions:

```nuon
// Base config
{
  "dependencies": {
    "revad-base": {
      "build_arg": "REVAD_BASE_IMAGE"
    },
    "common-tools-builder": {
      "service": "common-tools",
      "build_arg": "COMMON_TOOLS_BUILDER_IMAGE"
    },
    "common-tools-runtime": {
      "service": "common-tools",
      "build_arg": "COMMON_TOOLS_RUNTIME_IMAGE"
    }
  }
}

// versions.nuon overrides
{
  "overrides": {
    "dependencies": {
      "revad-base": {
        "version": "v3.3.3"
      },
      "common-tools-builder": {
        "version": "v1.0.0-debian"
      },
      "common-tools-runtime": {
        "version": "v1.0.0-alpine"
      }
    }
  }
}
```

### Dependency Resolution

- `revad-base` resolves to `revad-base:v3.3.3` (version from overrides)
- `common-tools-builder` resolves to `common-tools:v1.0.0-debian` (version from overrides)
- `common-tools-runtime` resolves to `common-tools:v1.0.0-alpine` (version from overrides)

## See Also

- [Service Configuration](../concepts/service-configuration.md) - Service config concepts (includes source build args convention)
- [Dependency Management](../concepts/dependency-management.md) - Dependency resolution
- [Schema File](../../schemas/service.nuon) - Authoritative schema definition
