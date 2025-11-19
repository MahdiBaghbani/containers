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
# Source Build Args Convention

## Overview

This document describes the convention-based system for source repository build arguments in the DockyPody build system.

## The Solution

**Convention-based auto-generation** of build arguments from source keys.

### Naming Convention

| Element | Pattern | Example |
|---------|---------|---------|
| **Source key** | `^[a-z0-9_]+$` (lowercase, alphanumeric + underscores) | `nushell`, `web_extensions` |
| **REF build arg** | `{SOURCE_KEY}_REF` (uppercase) | `NUSHELL_REF`, `WEB_EXTENSIONS_REF` |
| **URL build arg** | `{SOURCE_KEY}_URL` (uppercase) | `NUSHELL_URL`, `WEB_EXTENSIONS_URL` |
| **SHA build arg** | `{SOURCE_KEY}_SHA` (uppercase) | `NUSHELL_SHA`, `WEB_EXTENSIONS_SHA` |

### Configuration Format

**Service Config (`services/{service}.nuon`):**

```nuon
{
  "sources": {
    "revad": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.2"
      // Generates: REVAD_REF="v3.3.2" and REVAD_URL="https://github.com/cs3org/reva"
    },
    "nushell": {
      "url": "https://github.com/nushell/nushell",
      "ref": "0.108.0"
      // Generates: NUSHELL_REF="0.108.0" and NUSHELL_URL="https://github.com/nushell/nushell"
    },
    "web_extensions": {
      "url": "https://github.com/cernbox/web-extensions",
      "ref": "main"
      // Generates: WEB_EXTENSIONS_REF="main" and WEB_EXTENSIONS_URL="https://github.com/cernbox/web-extensions"
    }
  }
}
```

**Dockerfile:**

```dockerfile
# Auto-generated from config by build script
ARG REVAD_URL="https://github.com/cs3org/reva"
ARG REVAD_REF="v3.3.2"

RUN git clone \
    --branch ${REVAD_REF} \
    ${REVAD_URL} \
    /revad-git
```

## Rules

### Source Key Naming

1. **MUST** be lowercase
2. **MUST** contain only alphanumeric characters and underscores
3. **MUST** match regex: `^[a-z0-9_]+$`
4. **SHOULD** be descriptive and full (no abbreviations)

#### Valid

- `revad` CORRECT
- `nushell` CORRECT
- `web_extensions` CORRECT
- `upx` CORRECT

#### Invalid

- `Reva` WRONG (uppercase)
- `nu` WRONG (ambiguous abbreviation - use `nushell`)
- `web-extensions` WRONG (hyphen not allowed)
- `Web Extensions` WRONG (space not allowed)

### Build Arg Generation

The build script automatically generates three build arguments per source:

1. **`{SOURCE_KEY}_REF`** - The version/branch/tag reference
2. **`{SOURCE_KEY}_URL`** - The repository URL
3. **`{SOURCE_KEY}_SHA`** - The short commit SHA (7 characters) extracted from the ref

#### Example

```text
Source key: "web_extensions"
  ↓
Generates: WEB_EXTENSIONS_REF, WEB_EXTENSIONS_URL, and WEB_EXTENSIONS_SHA
```

### Dockerfile Requirements

Dockerfiles MUST declare both ARGs with sensible defaults:

```dockerfile
# Example: For source key "revad", declare REVAD_URL and REVAD_REF
ARG REVAD_URL="https://github.com/cs3org/reva"
ARG REVAD_REF="v3.3.2"

RUN git clone --branch ${REVAD_REF} ${REVAD_URL} /destination
```

**Pattern:** For any source key `{source_key}`, declare `{SOURCE_KEY}_URL` and `{SOURCE_KEY}_REF` (uppercase).

### Cache Mount IDs

When using cache mounts for git clones, include CACHEBUST in the mount ID:

```dockerfile
ARG CACHEBUST="default"
ARG SOURCE_REF="v3.3.2"
RUN --mount=type=cache,id=service-source-git-${CACHEBUST:-${SOURCE_REF}},target=/cache,sharing=shared \
    git clone --branch "${SOURCE_REF}" ${SOURCE_URL} /cache
```

The nested syntax `${CACHEBUST:-${SOURCE_REF}}` provides fallback safety (tested and verified working), even though the build system ensures CACHEBUST is always non-empty.

## Examples

### Example 1: Simple Source

**Config:**

```nuon
"sources": {
  "revad": {
    "url": "https://github.com/cs3org/reva",
    "ref": "v3.3.2"
  }
}
```

**Generated Build Args:**

- `REVAD_REF=v3.3.2`
- `REVAD_URL=https://github.com/cs3org/reva`
- `REVAD_SHA=2912f0a` (extracted from tag `v3.3.2`)

**Dockerfile:**

```dockerfile
ARG REVAD_URL="https://github.com/cs3org/reva"
ARG REVAD_REF="v3.3.2"

RUN git clone --branch ${REVAD_REF} ${REVAD_URL} /revad-git
```

### Example 2: Source with Underscores

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
- `WEB_EXTENSIONS_SHA=abc1234` (extracted from branch `main`)

**Dockerfile:**

```dockerfile
ARG WEB_EXTENSIONS_URL="https://github.com/cernbox/web-extensions"
ARG WEB_EXTENSIONS_REF="main"

RUN git clone --branch ${WEB_EXTENSIONS_REF} ${WEB_EXTENSIONS_URL} /web-extensions
```

### Example 3: Multiple Sources

**Config:**

```nuon
"sources": {
  "revad": {
    "url": "https://github.com/cs3org/reva",
    "ref": "v3.3.2"
  },
  "nushell": {
    "url": "https://github.com/nushell/nushell",
    "ref": "0.108.0"
  },
  "upx": {
    "url": "https://github.com/upx/upx",
    "ref": "v5.0.2"
  }
}
```

**Generated Build Args:**

- `REVAD_REF=v3.3.2`, `REVAD_URL=https://github.com/cs3org/reva`, `REVAD_SHA=2912f0a`
- `NUSHELL_REF=0.108.0`, `NUSHELL_URL=https://github.com/nushell/nushell`, `NUSHELL_SHA=da141be`
- `UPX_REF=v5.0.2`, `UPX_URL=https://github.com/upx/upx`, `UPX_SHA=1234567`

## Version Overrides

Version manifests can override source refs:

**Manifest (`services/revad-base/versions.nuon`):**

```nuon
{
  "versions": [
    {
      "name": "v3.3.2",
      "overrides": {
        "sources": {
          "revad": {
            "ref": "v3.3.2"  // Override ref only, URL stays from base config
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

## Environment Variable Overrides

Build args can be overridden via environment variables:

```bash
# Override the ref
export REVAD_REF="v4.0.0"
nu scripts/build.nu --service revad-base

# Override the URL (e.g., for fork testing)
export REVAD_URL="https://github.com/myorg/reva"
export REVAD_REF="my-feature-branch"
nu scripts/build.nu --service revad-base
```

## Validation

The build system validates source keys during service configuration loading (before build starts):

### When Validation Occurs

- Validation runs when loading service configuration files
- Build fails immediately if validation errors are found
- Validation is blocking - no build proceeds with invalid source keys

### Validation Rules

1. Source key MUST match `^[a-z0-9_]+$` (lowercase alphanumeric with underscores only)
2. `build_arg` field is FORBIDDEN (auto-generated, cannot be specified manually)
3. `url` field is REQUIRED (must be present and non-empty)
4. `ref` field is REQUIRED (must be present and non-empty)

### Error Examples

```text
Error: Source key 'Nu' must be lowercase alphanumeric with underscores only (pattern: ^[a-z0-9_]+$)

Error: Source 'reva' has FORBIDDEN 'build_arg' field. Build args are auto-generated from source key.

Error: Source 'reva' missing required field 'url'

Error: Source 'reva' missing required field 'ref'
```

### Validation Location

- Validation is performed in `scripts/lib/validate.nu` (see `validate-service-config` function)
- All services are validated before any builds start
- For implementation details, see: `scripts/lib/validate.nu:534-630`

## Benefits

### 1. Predictability

Given a source key, you can always predict the build arg names:

- `revad` -> `REVAD_REF` and `REVAD_URL`
- `web_extensions` -> `WEB_EXTENSIONS_REF` and `WEB_EXTENSIONS_URL`

### 2. Single Source of Truth

URLs are defined once in the config, not duplicated in Dockerfiles.

### 3. Discoverability

Grep for `NUSHELL_REF` -> find `nushell` source easily.

### 4. Consistency

All sources follow the same pattern: `{NAME}_REF` and `{NAME}_URL`.

### 5. Less Boilerplate

No need to specify `build_arg` in every source definition.

### 6. Impossible to Violate

Validation ensures the convention is followed everywhere.

## Troubleshooting

### Error: "Source key must be lowercase alphanumeric with underscores only"

**Problem:** Source key contains invalid characters.

**Solution:** Rename the source key:

```nuon
// Bad
"Nu-shell": { ... }  // Uppercase and hyphen

// Good
"nushell": { ... }
```

### Error: "Source has FORBIDDEN 'build_arg' field"

**Problem:** Config contains `build_arg` field which is not allowed.

**Solution:** Remove the `build_arg` field:

```nuon
// Bad
"revad": {
  "url": "...",
  "ref": "v3.3.2",
  "build_arg": "REVAD_BRANCH"  // ERROR Remove this
}

// Good
"revad": {
  "url": "...",
  "ref": "v3.3.2"
}
```

### Build fails: "ARG not found"

**Problem:** Dockerfile uses old ARG names.

**Solution:** Update Dockerfile to use new naming:

```dockerfile
# Bad
ARG REVAD_BRANCH="v3.3.2"
RUN git clone --branch ${REVAD_BRANCH} ...

# Good
ARG REVAD_REF="v3.3.2"
RUN git clone --branch ${REVAD_REF} ...
```

## See Also

- [Service Configuration](concepts/service-configuration.md) - Service config concepts
- [Build System](concepts/build-system.md) - Build system architecture
- [Multi-Version Builds Guide](guides/multi-version-builds.md) - Version management guide
- [Config Schema Reference](reference/config-schema.md) - Configuration schema reference
- [Schema Files](../schemas/service.nuon) - Authoritative schema definition

---

**Version:** 1.0
