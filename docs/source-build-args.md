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

# Source Build Args Convention

## Overview

Source repositories automatically generate build arguments using a convention-based system. The build system creates build args from source keys without requiring explicit `build_arg` fields.

The build arguments generated depend on the source type:

- **Git sources** (using `url`/`ref` fields) generate: `{SOURCE_KEY}_REF`, `{SOURCE_KEY}_URL`, `{SOURCE_KEY}_SHA`
- **Local sources** (using `path` field) generate: `{SOURCE_KEY}_PATH`, `{SOURCE_KEY}_MODE`

## Source Type Detection

The build system automatically detects source type based on the presence of fields:

- **Git source**: Has `url` and `ref` fields (or `{SOURCE_KEY}_URL` env var)
- **Local source**: Has `path` field (or `{SOURCE_KEY}_PATH` env var)

**Mutual Exclusivity:** A source cannot have both `path` and `url`/`ref` fields. This is validated during configuration validation.

## Git Source Build Args

For Git sources, the build system generates three build arguments:

### Build Arguments

1. **`{SOURCE_KEY}_REF`** - The version/branch/tag reference (e.g., `v3.3.3`, `main`)
2. **`{SOURCE_KEY}_URL`** - The repository URL (e.g., `https://github.com/cs3org/reva`)
3. **`{SOURCE_KEY}_SHA`** - The short commit SHA (7 characters) extracted from the ref

### Example

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

**Generated build args:**

- `REVA_REF="v3.3.3"`
- `REVA_URL="https://github.com/cs3org/reva"`
- `REVA_SHA="a1b2c3d"` (extracted from ref)

### Dockerfile Usage

```dockerfile
ARG REVA_URL="https://github.com/cs3org/reva"
ARG REVA_REF="v3.3.3"
ARG REVA_SHA=""

RUN git clone --branch ${REVA_REF} ${REVA_URL} /reva-git
```

## Local Source Build Args

For local sources, the build system generates two build arguments:

### Local Source Build Arguments

1. **`{SOURCE_KEY}_PATH`** - The path to the source directory (relative to build context root, e.g., `.build-sources/reva/`)
2. **`{SOURCE_KEY}_MODE`** - Always set to `"local"` to indicate local source mode

### Local Source Example

```nuon
{
  "sources": {
    "reva": {
      "path": "../reva"
    }
  }
}
```

**Generated build args:**

- `REVA_PATH=".build-sources/reva/"`
- `REVA_MODE="local"`

**Note:** The path in the build arg is relative to the build context root (where the source was copied), not the original path from the config.

### Local Source Dockerfile Usage

```dockerfile
ARG REVA_PATH=""
ARG REVA_MODE=""

# Conditional logic: use local path if MODE is "local", otherwise use git clone
RUN if [ "$REVA_MODE" = "local" ]; then \
      cp -r ${REVA_PATH}* /reva-git/; \
    else \
      git clone --branch ${REVA_REF} ${REVA_URL} /reva-git; \
    fi
```

## Source Key Naming Rules

Source keys must follow these rules:

1. **MUST** be lowercase
2. **MUST** contain only alphanumeric characters and underscores
3. **MUST** match regex: `^[a-z0-9_]+$`
4. **SHOULD** be descriptive and full (no abbreviations)

### Valid Examples

- `revad` CORRECT
- `nushell` CORRECT
- `web_extensions` CORRECT
- `upx` CORRECT

### Invalid Examples

- `Reva` WRONG (uppercase)
- `nu` WRONG (ambiguous abbreviation - use `nushell`)
- `web-extensions` WRONG (hyphen not allowed)
- `Web Extensions` WRONG (space not allowed)

## Build Argument Generation Table

| Source Type | Fields Required | Build Args Generated                  | SHA Generated? |
| ----------- | --------------- | ------------------------------------- | -------------- |
| **Git**     | `url`, `ref`    | `{KEY}_REF`, `{KEY}_URL`, `{KEY}_SHA` | Yes            |
| **Local**   | `path`          | `{KEY}_PATH`, `{KEY}_MODE`            | No             |

## Environment Variable Overrides

You can override source build args using environment variables:

### Git Source Override

```bash
export REVA_REF="custom-branch"
export REVA_URL="https://github.com/custom/reva"
nu scripts/build.nu --service my-service
```

### Local Source Override

```bash
export REVA_PATH="/path/to/local/reva"
nu scripts/build.nu --service my-service
```

**Note:** When using environment variable overrides, the build system detects the source type based on which env vars are set:

- If `{SOURCE_KEY}_PATH` is set, the source is treated as local
- If `{SOURCE_KEY}_URL` is set, the source is treated as Git

## Mixed Sources

You can mix Git and local sources in the same service configuration:

```nuon
{
  "sources": {
    "reva": {
      "url": "https://github.com/cs3org/reva",
      "ref": "v3.3.3"
    },
    "custom_lib": {
      "path": "../custom-lib"
    }
  }
}
```

**Generated build args:**

- `REVA_REF`, `REVA_URL`, `REVA_SHA` (Git source)
- `CUSTOM_LIB_PATH`, `CUSTOM_LIB_MODE` (Local source)

## Dockerfile Requirements

Dockerfiles MUST declare ARGs with sensible defaults for both source types:

### Git Source ARGs

```dockerfile
ARG REVA_URL="https://github.com/cs3org/reva"
ARG REVA_REF="v3.3.3"
ARG REVA_SHA=""
```

### Local Source ARGs

```dockerfile
ARG REVA_PATH=""
ARG REVA_MODE=""
```

### Dual-Mode Pattern

For Dockerfiles that support both Git and local sources:

```dockerfile
ARG REVA_URL="https://github.com/cs3org/reva"
ARG REVA_REF="v3.3.3"
ARG REVA_SHA=""
ARG REVA_PATH=""
ARG REVA_MODE=""

# Conditional logic: use local path if MODE is "local", otherwise use git clone
RUN --mount=type=bind,source=${REVA_PATH:-.},target=/tmp/local-reva,ro \
    if [ "$REVA_MODE" = "local" ]; then \
      mkdir -p /reva-git && \
      cp -a /tmp/local-reva/. /reva-git; \
    else \
      git clone --branch ${REVA_REF} ${REVA_URL} /reva-git; \
    fi
```

**Reminder:** Local directories are copied into `.build-sources/{source}` inside the service context. Without the explicit bind mount, Docker cannot see that directory and the local copy step will fail.

## Related Documentation

- [Service Configuration](../concepts/service-configuration.md) - Complete service configuration guide
- [Build System](../concepts/build-system.md) - Build argument injection priority
- [Config Schema](../reference/config-schema.md) - Complete schema reference
