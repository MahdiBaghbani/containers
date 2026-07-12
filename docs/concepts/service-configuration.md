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

Each service is discovered from:

- `services/{name}.nuon` - base service metadata and config when no platform
  manifest is used
- `services/{name}/versions.nuon` - required version manifest
- `services/{name}/platforms.nuon` - optional platform manifest with one or
  more platform entries

The base config in `services/{name}.nuon` defines:

- Service metadata (name, context, dockerfile, tls)
- Source repositories to build from (only when the service does not use
  `platforms.nuon`)
- External base images (not built by us) - infrastructure only (name, no tag)
- Dependencies (internal service dependencies) - infrastructure only (service, build_arg, no version)
- Build arguments
- Labels

**CRITICAL**: When `platforms.nuon` exists, base config can **ONLY** contain:
`name`, `context`, `labels`, `tls`, and `ssh` (metadata). All other fields are
forbidden and must be moved to `platforms.nuon` (infrastructure) or
`versions.nuon` (versions).

## Dockerfile Requirement

- **Required** when the service does not use `platforms.nuon`
- **Ignored/Replaced** if the service uses `platforms.nuon` - even a
  one-platform manifest replaces the base `dockerfile` field with the
  per-platform dockerfile entries from the platform manifest

## Versioning

**CRITICAL REQUIREMENT: All services MUST have version manifests**
(`services/{name}/versions.nuon`).

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

- **Single-platform**: Sources are allowed in base config, but they are not
  required there. They may live entirely in `versions.nuon` defaults or
  overrides if the merged config is still complete.
- **Multi-platform**: Sources are **FORBIDDEN** in base config and
  `platforms.nuon`, and must live in `versions.nuon` defaults or overrides.

**Single-platform example:**

```nuon
// services/my-service.nuon
{
  "sources": {
    "revad": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.3"
      // Auto-generates: REVAD_REF, REVAD_URL, REVAD_REF_KIND (+ optional REVAD_SHA)
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

// services/my-service/versions.nuon (sources defined here)
{
  "default": "v1.0.0",
  "versions": [
    {
      "name": "v1.0.0",
      "overrides": {
        "sources": {
          "reva": {
            "url": "https://github.com/cs3org/reva",
            "ref": "v3.3.3"
          }
        }
      }
    }
  ]
}
```

### Local Folder Sources (Development Only)

For local development, you can use local filesystem directories as sources instead of Git repositories. This allows you to test changes without committing and pushing to Git.

**CRITICAL RESTRICTIONS:**

- **Development only** - Local sources are **REJECTED** in CI/production builds
- **Mutually exclusive** - A source cannot have both `path` and `url`/`ref` fields
- **Path validation** - Paths must exist, be directories, and stay within the
  repository root or a sibling `repos/` workspace parent when this repo itself
  lives under `repos/`

**Configuration:**

Local sources use the `path` field instead of `url`/`ref`:

```nuon
{
  "sources": {
    "reva": {
      "path": "../reva"  // Relative to repository root
      // Auto-generates: REVA_PATH, REVA_MODE="local", REVA_REF_KIND="local"
    }
  }
}
```

**Path Resolution:**

- **Relative paths** - Resolved relative to repository root
- **Absolute paths** - Allowed when they still resolve inside the repository
  root or a sibling `repos/` workspace parent when this repo itself lives under
  `repos/`
- **Validation** - Paths are validated to ensure they exist, are directories,
  and stay within one of those allowed roots

**Example - Local Development:**

```nuon
// services/my-service.nuon
{
  "sources": {
    "reva": {
      "path": "../reva"  // Local development directory
    }
  }
}
```

**Example - Off-Git Local Plane (opencloudmesh-go):**

For developer-only path overrides, use the off-git local plane instead of
committing a tracked version.

**Prerequisites:** `--plane local` hard-errors when `.dockypody.local/` does
not exist. Create the service mirror directory and place the fragment there
(git-ignored; do not commit). If the mirror directory exists, it must contain
`versions.nuon` (an empty mirror directory hard-errors). See
[`examples/opencloudmesh-go/README.md`](../../examples/opencloudmesh-go/README.md)
for the full setup sequence.

```bash
mkdir -p .dockypody.local/services/opencloudmesh-go
```

Save the fragment as
`.dockypody.local/services/opencloudmesh-go/versions.nuon`:

Use the same JSONC-style rules here as tracked manifests: quoted keys, quoted
string values, and normal object entries in `"versions"`. Do not save compact
NUON table output such as:

```nuon
{versions: [[name, latest, overrides]; [dev, false, {sources: {ocm_go: {path: "../opencloudmesh-go"}}}]]}
```

Use this JSONC-style form instead:

```nuon
{
  "versions": [
    {
      "name": "dev",
      "latest": false,
      "overrides": {
        "sources": {
          "ocm_go": {
            "path": "../opencloudmesh-go"
          }
        }
      }
    }
  ]
}
```

Build with:

```bash
nu scripts/dockypody.nu build --plane local --service opencloudmesh-go --version dev
```

The local plane merges this fragment with the tracked manifest. Local versions
may add new names or fully replace a same-named tracked version. Source ids
must already exist in the tracked manifest (`ocm_go` here).

**Example - Environment Variable Override:**

You can override local source paths using environment variables:

```bash
export REVA_PATH="/path/to/local/reva"
nu scripts/dockypody.nu build --service my-service
```

**Where to Define Local Sources:**

Local sources can be defined in the same locations as Git sources:

- **Base config** (services without `platforms.nuon` only)
- **`versions.nuon.defaults`** (default configuration for all versions)
- **`versions.nuon` version overrides** (version-specific paths)
- **`versions.nuon` platform override blocks** (platform-specific paths)

**Important Notes:**

- Local sources are automatically copied to `.build-sources/{source_key}/` in the build context
- Build args use paths relative to the build context root (e.g., `.build-sources/reva/`)
- Local sources do not generate SHA build args (no Git repository to extract from)
- Local sources do not generate source revision labels (no Git metadata available)
- Cache busting for services with only local sources uses random UUID (always-bust behavior)

**When to Use Local vs Git Sources:**

- **Use local sources** for:

  - Local development and testing
  - Iterative development without committing changes
  - Testing uncommitted modifications

- **Use Git sources** for:
  - CI/production builds
  - Reproducible builds
  - Version tracking and labels

## Source Build Arguments Convention

Source repositories automatically generate build arguments using a convention-based system. The build system creates build args from source keys without requiring explicit `build_arg` fields.

The build arguments generated depend on the source type:

- **Git sources** (using `url`/`ref` fields) generate: `{SOURCE_KEY}_REF`,
  `{SOURCE_KEY}_URL`, `{SOURCE_KEY}_REF_KIND`, and optionally
  `{SOURCE_KEY}_SHA` (label metadata)
- **Local sources** (using `path` field) generate: `{SOURCE_KEY}_PATH`,
  `{SOURCE_KEY}_MODE`, and `{SOURCE_KEY}_REF_KIND="local"`

Dockerfiles should use the shared `clone-source.nu` helper (see
[Source Build Args Convention](../source-build-args.md)) and pass
`{SOURCE_KEY}_REF_KIND` so branch/tag refs and full 40-hex SHAs clone
correctly.

### Naming Convention

| Element                | Pattern                                                | Example                               |
| ---------------------- | ------------------------------------------------------ | ------------------------------------- |
| **Source key**         | `^[a-z0-9_]+$` (lowercase, alphanumeric + underscores) | `nushell`, `web_extensions`           |
| **REF build arg**      | `{SOURCE_KEY}_REF` (uppercase, Git only)               | `NUSHELL_REF`, `WEB_EXTENSIONS_REF`   |
| **URL build arg**      | `{SOURCE_KEY}_URL` (uppercase, Git only)               | `NUSHELL_URL`, `WEB_EXTENSIONS_URL`   |
| **REF_KIND build arg** | `{SOURCE_KEY}_REF_KIND` (`ref`, `sha`, or `local`)     | `NUSHELL_REF_KIND`, `REVA_REF_KIND`   |
| **SHA build arg**      | `{SOURCE_KEY}_SHA` (optional metadata, Git only)       | `NUSHELL_SHA`, `WEB_EXTENSIONS_SHA`   |
| **PATH build arg**     | `{SOURCE_KEY}_PATH` (uppercase, local only)            | `NUSHELL_PATH`, `WEB_EXTENSIONS_PATH` |
| **MODE build arg**     | `{SOURCE_KEY}_MODE` (uppercase, local only)            | `NUSHELL_MODE`, `WEB_EXTENSIONS_MODE` |

### Build Argument Generation

#### Git Sources

For Git sources (using `url`/`ref` fields), the build script automatically
generates clone-driving build arguments:

1. **`{SOURCE_KEY}_REF`** - The git ref: branch, tag, or full 40-hex SHA
2. **`{SOURCE_KEY}_URL`** - The repository URL
3. **`{SOURCE_KEY}_REF_KIND`** - `ref` or `sha` (classified from `_REF`;
   recomputed after env overrides)
4. **`{SOURCE_KEY}_SHA`** - Optional short commit SHA for labels. Does not
   drive clone behavior.

**Example:**

```text
Source key: "web_extensions" (Git source)
  ->
Generates: WEB_EXTENSIONS_REF, WEB_EXTENSIONS_URL, WEB_EXTENSIONS_REF_KIND
(+ optional WEB_EXTENSIONS_SHA)
```

#### Local Sources

For local sources (using `path` field), the build script automatically
generates three build arguments:

1. **`{SOURCE_KEY}_PATH`** - The path to the source directory (relative to
   build context root, e.g., `.build-sources/reva/`)
2. **`{SOURCE_KEY}_MODE`** - Always set to `"local"` to indicate local source
   mode
3. **`{SOURCE_KEY}_REF_KIND`** - Always set to `"local"`

**Example:**

```text
Source key: "reva" (local source with path="../reva")
  ->
Generates: REVA_PATH=".build-sources/reva/", REVA_MODE="local",
REVA_REF_KIND="local"
```

**Note:** Local sources do not generate SHA build args (no Git repository to
extract from).

### Source Key Naming Rules

1. **MUST** be lowercase
2. **MUST** contain only alphanumeric characters and underscores
3. **MUST** match regex: `^[a-z0-9_]+$`
4. **SHOULD** be descriptive and full (no abbreviations)

#### Valid Examples

- `revad` CORRECT
- `nushell` CORRECT
- `web_extensions` CORRECT
- `upx` CORRECT

#### Invalid Examples

- `Reva` WRONG (uppercase)
- `nu` WRONG (ambiguous abbreviation - use `nushell`)
- `web-extensions` WRONG (hyphen not allowed)
- `Web Extensions` WRONG (space not allowed)

### Dockerfile Requirements

Dockerfiles MUST declare ARGs with sensible defaults and fetch sources through
`clone-source.nu`:

```dockerfile
# Example: For source key "revad"
ARG REVAD_URL="https://github.com/cs3org/reva"
ARG REVAD_REF="v3.3.3"
ARG REVAD_REF_KIND=""
ARG REVAD_PATH=""
ARG REVAD_MODE=""

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

**Pattern:** For any source key `{source_key}`, declare `{SOURCE_KEY}_URL`,
`{SOURCE_KEY}_REF`, and `{SOURCE_KEY}_REF_KIND` (uppercase), plus local
args when dual-mode is needed.

### Clone compatibility validation

`validate` checks merged/effective configs. Full-SHA `ref` values wired into
active Dockerfile lines require `clone-source.nu` with `*_REF_KIND` (or an
explicit SHA fetch path). Legacy `git clone --branch` for SHA refs fails
validation.

### Cache Mount IDs

When using cache mounts with `clone-source.nu`, include CACHEBUST in the
mount ID:

```dockerfile
ARG CACHEBUST="default"
ARG SOURCE_REF="v3.3.3"
ARG SOURCE_REF_KIND=""
RUN --mount=type=cache,id=service-source-git-${CACHEBUST:-${SOURCE_REF}},target=/cache,sharing=shared \
    nu /tmp/clone-source.nu \
    --mode git \
    --url "${SOURCE_URL}" \
    --ref "${SOURCE_REF}" \
    --ref-kind "${SOURCE_REF_KIND}" \
    --cache-dir /cache \
    --dest /work
```

The nested syntax `${CACHEBUST:-${SOURCE_REF}}` provides fallback safety
(tested and verified working), even though the build system ensures CACHEBUST
is always non-empty.

### Examples

#### Example 1: Simple Source

**Config:**

```nuon
"sources": {
  "revad": {
    "url": "https://github.com/cs3org/reva",
    "ref": "v3.3.3"
  }
}
```

**Generated Build Args:**

- `REVAD_REF=v3.3.3`
- `REVAD_URL=https://github.com/cs3org/reva`
- `REVAD_REF_KIND=ref`
- `REVAD_SHA=2912f0a` (optional label metadata)

**Dockerfile:**

```dockerfile
ARG REVAD_URL="https://github.com/cs3org/reva"
ARG REVAD_REF="v3.3.3"
ARG REVAD_REF_KIND=""

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu \
    --mode git \
    --url "${REVAD_URL}" \
    --ref "${REVAD_REF}" \
    --ref-kind "${REVAD_REF_KIND}" \
    --dest /revad-git
```

#### Example 2: Source with Underscores

**Config:**

```nuon
"sources": {
  "web_extensions": {
    "url": "https://github.com/cernbox/web-extensions",
    "ref": "main"
  }
}
```

**Generated Build Args:**

- `WEB_EXTENSIONS_REF=main`
- `WEB_EXTENSIONS_URL=https://github.com/cernbox/web-extensions`
- `WEB_EXTENSIONS_REF_KIND=ref`
- `WEB_EXTENSIONS_SHA=abc1234` (optional label metadata)

**Dockerfile:**

```dockerfile
ARG WEB_EXTENSIONS_URL="https://github.com/cernbox/web-extensions"
ARG WEB_EXTENSIONS_REF="main"
ARG WEB_EXTENSIONS_REF_KIND=""

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu \
    --mode git \
    --url "${WEB_EXTENSIONS_URL}" \
    --ref "${WEB_EXTENSIONS_REF}" \
    --ref-kind "${WEB_EXTENSIONS_REF_KIND}" \
    --dest /web-extensions
```

#### Example 3: Multiple Sources

**Config:**

```nuon
"sources": {
  "revad": {
    "url": "https://github.com/cs3org/reva",
    "ref": "v3.3.3"
  },
  "nushell": {
    "url": "https://github.com/nushell/nushell",
    "ref": "0.113.1"
  },
  "upx": {
    "url": "https://github.com/upx/upx",
    "ref": "v5.0.2"
  }
}
```

**Generated Build Args:**

- `REVAD_REF=v3.3.3`, `REVAD_URL=...`, `REVAD_REF_KIND=ref` (+ optional SHA)
- `NUSHELL_REF=0.113.1`, `NUSHELL_URL=...`, `NUSHELL_REF_KIND=ref` (+ optional SHA)
- `UPX_REF=v5.0.2`, `UPX_URL=...`, `UPX_REF_KIND=ref` (+ optional SHA)

### Version Overrides

Version manifests can override source refs:

**Manifest (`services/revad-base/versions.nuon`):**

```nuon
{
  "versions": [
    {
      "name": "v3.3.3",
      "overrides": {
        "sources": {
          "revad": {
            "ref": "v3.3.3"  // Override ref only, URL stays from base config
          }
        }
      }
    },
    {
      "name": "edge",
      "overrides": {
        "sources": {
          "revad": {
            "ref": "main"  // Build from main branch
          }
        }
      }
    }
  ]
}
```

**Source Merging Behavior:**

Source overrides in version manifests use **type-aware merging**:

- **Git sources (url/ref)**: Support field-level merging. Partial overrides (only `ref` or only `url`) preserve the missing field from defaults. Complete overrides (both `url` and `ref`) replace the entire source.
- **Local sources (path)**: Always replace entirely (path is a single field).
- **Type switches**: When switching between Git and local sources, the override completely replaces the default (no merging of incompatible fields).

#### Example: Partial Git Source Override

```nuon
{
  "default": "master",
  "defaults": {
    "sources": {
      "reva": {
        "url": "https://github.com/cs3org/reva",
        "ref": "v3.3.3"
      }
    }
  },
  "versions": [
    {
      "name": "master",
      "overrides": {
        "sources": {
          "reva": {
            "ref": "master"  // Only ref - url preserved from defaults
          }
        }
      }
    }
  ]
}
// Result: reva has {url: "https://github.com/cs3org/reva", ref: "master"}
```

#### Example: Path Source Override (Type Switch)

```nuon
{
  "default": "dev-path",
  "defaults": {
    "sources": {
      "gaia": {
        "url": "https://github.com/example/gaia",
        "ref": "v1.0.0"
      }
    }
  },
  "versions": [
    {
      "name": "dev-path",
      "overrides": {
        "sources": {
          "gaia": {
            "path": ".repos/gaia"  // Type switch - completely replaces default
          }
        }
      }
    }
  ]
}
```

**Result:** The `dev-path` version has `sources.gaia` with only
`{path: ".repos/gaia"}` - the `url` and `ref` fields from defaults are
removed, not merged.

**Important:** Sources from defaults that are **not** in overrides are preserved. Only source keys explicitly defined in overrides are replaced.

### Environment Variable Overrides

Build args can be overridden via environment variables:

```bash
# Override the ref
export REVAD_REF="v4.0.0"
nu scripts/dockypody.nu build --service revad-base

# Override the URL (e.g., for fork testing)
export REVAD_URL="https://github.com/myorg/reva"
export REVAD_REF="my-feature-branch"
nu scripts/dockypody.nu build --service revad-base
```

### Validation

The build system validates source keys during service configuration loading (before build starts):

#### When Validation Occurs

- Validation runs when loading service configuration files
- Build fails immediately if validation errors are found
- Validation is blocking - no build proceeds with invalid source keys

#### Validation Rules

1. Source key MUST match `^[a-z0-9_]+$` (lowercase alphanumeric with underscores only)
2. `build_arg` field is FORBIDDEN (auto-generated, cannot be specified manually)
3. Each source is either Git or local (mutually exclusive):
   - **Git sources**: `url` and `ref` are REQUIRED (both present and non-empty)
   - **Local sources**: `path` is REQUIRED (present, non-empty, valid directory)
   - `path` and `url`/`ref` cannot both be set on the same source

#### Error Examples

```text
Error: Source key 'Nu' must be lowercase alphanumeric with underscores only (pattern: ^[a-z0-9_]+$)

Error: Source 'reva' has FORBIDDEN 'build_arg' field. Build args are auto-generated from source key.

Error: Source 'reva' missing required field 'url'

Error: Source 'reva' missing required field 'ref'

Error: Source 'reva': Cannot have both 'path' and 'url'/'ref' fields. They are mutually exclusive.
```

#### Validation Location

- Validation is performed in `scripts/lib/validate/core.nu` (see
  `validate-service-config` and `validate-source-entries`)
- All services are validated before any builds start
- For implementation details, see: `scripts/lib/validate/core.nu:51-119`

### Benefits

#### 1. Predictability

Given a source key, you can always predict the build arg names:

- Git `revad` -> `REVAD_REF`, `REVAD_URL`, `REVAD_REF_KIND` (+ optional
  `REVAD_SHA`)
- Git `web_extensions` -> `WEB_EXTENSIONS_REF`, `WEB_EXTENSIONS_URL`,
  `WEB_EXTENSIONS_REF_KIND` (+ optional `WEB_EXTENSIONS_SHA`)
- Local `reva` -> `REVA_PATH`, `REVA_MODE="local"`, `REVA_REF_KIND="local"`

#### 2. Single Source of Truth

URLs are defined once in the config, not duplicated in Dockerfiles.

#### 3. Discoverability

Grep for `NUSHELL_REF` -> find `nushell` source easily.

#### 4. Consistency

Git sources share `{NAME}_REF`, `{NAME}_URL`, `{NAME}_REF_KIND`, and optional
`{NAME}_SHA`. Local sources share `{NAME}_PATH`, `{NAME}_MODE="local"`, and
`{NAME}_REF_KIND="local"`.

#### 5. Less Boilerplate

No need to specify `build_arg` in every source definition.

#### 6. Impossible to Violate

Validation ensures the convention is followed everywhere.

### Troubleshooting

#### Error: "Source key must be lowercase alphanumeric with underscores only"

**Problem:** Source key contains invalid characters.

**Solution:** Rename the source key:

```nuon
// Bad
"Nu-shell": { ... }  // Uppercase and hyphen

// Good
"nushell": { ... }
```

#### Error: "Source has FORBIDDEN 'build_arg' field"

**Problem:** Config contains `build_arg` field which is not allowed.

**Solution:** Remove the `build_arg` field:

```nuon
// Bad
"revad": {
  "url": "...",
  "ref": "v3.3.3",
  "build_arg": "REVAD_BRANCH"  // ERROR Remove this
}

// Good
"revad": {
  "url": "...",
  "ref": "v3.3.3"
}
```

#### Build fails: "ARG not found"

**Problem:** Dockerfile uses old ARG names.

**Solution:** Update Dockerfile to use current naming and `clone-source.nu`:

```dockerfile
# Bad (legacy)
ARG REVAD_BRANCH="v3.3.3"
RUN git clone --branch ${REVAD_BRANCH} ...

# Good
ARG REVAD_REF="v3.3.3"
ARG REVAD_REF_KIND=""
COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
RUN nu /tmp/clone-source.nu --mode git --url "${REVAD_URL}" \
    --ref "${REVAD_REF}" --ref-kind "${REVAD_REF_KIND}" --dest /revad-git
```

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

**Key rules:**

- `name` field: Infrastructure - defined in base config when the service does
  not use `platforms.nuon`, or in `platforms.nuon` when it does
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

For complete details, see [Dependency Management](dependency-management.md).

## Base Config Restrictions

**CRITICAL**: When `platforms.nuon` exists, base config can **ONLY**
contain: `name`, `context`, `tls`, `ssh`, `labels` (all metadata).

All other fields (`dockerfile`, `external_images`, `sources`, `dependencies`, `build_args`) are **FORBIDDEN** in base config when `platforms.nuon` exists. These fields must be moved to:

- `platforms.nuon` - For infrastructure (name, build_arg, service, dockerfile, external_images, dependencies)
- `versions.nuon` - For version control (tag, version, sources, url, ref)

`sources` are **FORBIDDEN** in `platforms.nuon` (use `versions.nuon` defaults or overrides).

**Error example:**

```text
Service 'my-service': external_images.build: Field forbidden when platforms.nuon exists. Move to platforms.nuon (infrastructure) or versions.nuon (versions).
```

## Labels Configuration

Labels are Docker image metadata (OCI labels), similar to TLS
configuration. They are **allowed in base config** even when
`platforms.nuon` exists.

DockyPody also auto-injects `org.opencloudmesh.service=<service name>` at
build time. You do not need to duplicate that label in every manifest unless
you want an explicit local override.

**Where labels can be defined:**

- **Base config** - Common labels for all platforms (allowed even when
  `platforms.nuon` exists)
- **platforms.nuon** - Platform-specific labels (deep-merged with base labels)
- **versions.nuon** - Version-specific label overrides (deep-merged with
  base/platform labels)

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
      "ref": "v3.3.3"
    },
    "nushell": {
      "url": "https://github.com/nushell/nushell",
      "ref": "0.113.1"
    }
  }
}
```

**Generated Labels:**

- `org.opencontainers.image.source.reva.revision=2912f0a` (extracted from tag `v3.3.3`)
- `org.opencloudmesh.source.reva.revision=2912f0a`
- `org.opencloudmesh.source.reva.ref=v3.3.3`
- `org.opencloudmesh.source.reva.url=https://github.com/cs3org/reva`
- `org.opencontainers.image.source.nushell.revision=da141be` (extracted from tag `0.113.1`)
- `org.opencloudmesh.source.nushell.revision=da141be`
- `org.opencloudmesh.source.nushell.ref=0.113.1`
- `org.opencloudmesh.source.nushell.url=https://github.com/nushell/nushell`

#### Missing SHA Handling

When SHA extraction fails (network error, git unavailable, invalid ref), labels include a `missing:` prefix:

- `org.opencontainers.image.source.reva.revision=missing:v3.3.3`
- `org.opencloudmesh.source.reva.revision=missing:v3.3.3`

This clearly indicates that SHA extraction failed and the ref value is used instead.

#### User Label Overrides

You can override auto-generated source revision labels by defining them manually in your service configuration:

```nuon
{
  "sources": {
    "reva": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.3"
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
- **Missing SHA**: `missing:{ref}` format (e.g., `missing:v3.3.3`)
- **Source Key**: Lowercase alphanumeric with underscores (matches source key from config)

For complete details on SHA extraction and caching, see [Source Build Arguments Convention](#source-build-arguments-convention) above.

## TLS Configuration

TLS configuration is **ONLY** allowed in base config. It is **FORBIDDEN** in `platforms.nuon` and `versions.nuon`.

TLS config is considered metadata (not infrastructure or version control), so it stays in base config even when `platforms.nuon` exists.

## SSH Configuration

SSH configuration configures dev and E2E SSH shell access to running containers. It does NOT describe Git transport, Git signing, or OCM share protocol behavior.

Unlike TLS, SSH configuration **IS allowed** in `platforms.nuon` and `versions.nuon` for dev/prod splits.

### Example

```nuon
{
  "ssh": {
    "enabled": true,
    "mode": "server",
    "default_user": "root",
    "port": 22,
    "listen": "0.0.0.0"
  }
}
```

### Modes

- `client`: Container acts as SSH client (generates `~/.ssh/config`, copies keypair)
- `server`: Container runs sshd daemon (generates host keys, configures sshd, starts daemon)
- `client-and-server`: Both capabilities
- `disabled` (default): No SSH access

### Platform Overrides

SSH is allowed in platform configs:

```nuon
{
  "platforms": [
    {
      "name": "development",
      "ssh": { "enabled": true, "mode": "server" }
    },
    {
      "name": "production",
      "ssh": { "enabled": false, "mode": "disabled" }
    }
  ]
}
```

Version-level overrides are also allowed but should be rare and documented.

## See Also

- [Dependency Management](dependency-management.md) - How dependencies work and are resolved
- [Build System](build-system.md) - How the build system processes configurations
- [Multi-Version Builds Guide](../guides/multi-version-builds.md) - Version manifest details
- [Config Schema Reference](../reference/config-schema.md) - Complete schema documentation
