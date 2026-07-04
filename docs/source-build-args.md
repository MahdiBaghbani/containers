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

Source repositories automatically generate build arguments using a
convention-based system. The build system creates build args from source keys
without requiring explicit `build_arg` fields.

The build arguments generated depend on the source type:

- **Git sources** (using `url`/`ref` fields) generate: `{SOURCE_KEY}_REF`,
  `{SOURCE_KEY}_URL`, `{SOURCE_KEY}_REF_KIND`, and optionally
  `{SOURCE_KEY}_SHA` (metadata)
- **Local sources** (using `path` field) generate: `{SOURCE_KEY}_PATH`,
  `{SOURCE_KEY}_MODE`, and `{SOURCE_KEY}_REF_KIND="local"`

Dockerfiles should fetch Git sources through the shared
`clone-source.nu` helper (staged into the build context when the Dockerfile
copies it). The helper reads `{SOURCE_KEY}_REF_KIND` to choose branch/tag
clone vs full-SHA fetch/checkout. Do not use bare `git clone --branch` as the
recommended pattern.

## Source Type Detection

The build system selects source type from config fields and env overrides:

- **Local mode**: Selected when the source config has a `path` field, or when
  `{SOURCE_KEY}_PATH` is set in the environment.
- **Git mode** (default): Used when neither a config `path` nor
  `{SOURCE_KEY}_PATH` is present.

`{SOURCE_KEY}_URL` and `{SOURCE_KEY}_REF` override Git clone values but do
**not** switch the source type. A Git-configured source stays Git even when
only those env vars are set.

**Mutual Exclusivity:** A source cannot have both `path` and `url`/`ref`
fields. This is validated during configuration validation.

## Git Source Build Args

For Git sources, the build system generates clone-driving args plus optional
SHA metadata:

### Build Arguments

1. **`{SOURCE_KEY}_REF`** - The git ref: branch name, tag, or full 40-hex
   commit SHA
2. **`{SOURCE_KEY}_URL`** - The repository URL (e.g.,
   `https://github.com/cs3org/reva`)
3. **`{SOURCE_KEY}_REF_KIND`** - How to clone: `ref` (branch/tag),
   `sha` (full 40-hex SHA), or auto-classified from `_REF` when unset in the
   helper
4. **`{SOURCE_KEY}_SHA`** - Optional short commit SHA (7 characters) for
   labels and metadata. The build system may emit this, but it does **not**
   drive clone behavior. Declare it only when needed for OCI labels or
   cache-bust display.

The build system classifies `*_REF_KIND` from the effective `*_REF` after
merges and environment overrides: full 40-hex SHA -> `sha`, otherwise `ref`.

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
- `REVA_REF_KIND="ref"`
- `REVA_SHA="a1b2c3d"` (optional metadata, when extraction succeeds)

### Dockerfile Usage

Copy the helper into the image context, declare the source ARGs, and invoke
`clone-source.nu`:

```dockerfile
ARG REVA_URL="https://github.com/cs3org/reva"
ARG REVA_REF="v3.3.3"
ARG REVA_REF_KIND=""
ARG REVA_SHA=""
ARG REVA_PATH=""
ARG REVA_MODE=""
ARG CACHEBUST="default"

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu

RUN --mount=type=cache,id=reva-git-${CACHEBUST:-${REVA_REF}},target=/src/reva-git-cache,sharing=shared \
    --mount=type=bind,source=${REVA_PATH:-.},target=/src/local-reva,ro \
    nu /tmp/clone-source.nu \
    --mode "${REVA_MODE:-git}" \
    --url "${REVA_URL}" \
    --ref "${REVA_REF}" \
    --ref-kind "${REVA_REF_KIND}" \
    --local-dir /src/local-reva \
    --cache-dir /src/reva-git-cache \
    --dest /reva-git
```

**Legacy pattern (do not use for new Dockerfiles):** bare
`git clone --branch ${REVA_REF}` fails for full-SHA refs and is rejected by
`validate` on merged configs when that source is wired into active build lines.

## Local Source Build Args

For local sources, the build system generates three build arguments:

### Local Source Build Arguments

1. **`{SOURCE_KEY}_PATH`** - The path to the source directory (relative to
   build context root, e.g., `.build-sources/reva/`)
2. **`{SOURCE_KEY}_MODE`** - Always set to `"local"` to indicate local source
   mode
3. **`{SOURCE_KEY}_REF_KIND`** - Always set to `"local"` for local sources

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
- `REVA_REF_KIND="local"`

**Note:** The path in the build arg is relative to the build context root
(where the source was copied), not the original path from the config.

### Local Source Dockerfile Usage

Use the same `clone-source.nu` invocation as Git sources. Pass
`--mode "${REVA_MODE:-git}"` and `--local-dir` from a bind mount; the helper
copies local content when mode is `local`:

```dockerfile
ARG REVA_PATH=""
ARG REVA_MODE=""
ARG REVA_REF_KIND=""
ARG REVA_URL=""
ARG REVA_REF=""

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu

RUN --mount=type=bind,source=${REVA_PATH:-.},target=/src/local-reva,ro \
    nu /tmp/clone-source.nu \
    --mode "${REVA_MODE:-git}" \
    --url "${REVA_URL}" \
    --ref "${REVA_REF}" \
    --ref-kind "${REVA_REF_KIND}" \
    --local-dir /src/local-reva \
    --dest /reva-git
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

| Source Type | Fields Required | Build Args Generated                                      | SHA metadata? |
| ----------- | --------------- | --------------------------------------------------------- | ------------- |
| **Git**     | `url`, `ref`    | `{KEY}_REF`, `{KEY}_URL`, `{KEY}_REF_KIND` (+ `{KEY}_SHA` when extracted) | Optional      |
| **Local**   | `path`          | `{KEY}_PATH`, `{KEY}_MODE`, `{KEY}_REF_KIND="local"`      | No            |

## Validation

`nu scripts/dockypody.nu validate` checks merged/effective source configs.
When a source `ref` is a full 40-hex SHA and active Dockerfile lines reference
that source's `*_REF` arg, validation requires either:

- `clone-source.nu` with `{SOURCE_KEY}_REF_KIND` passed through, or
- an explicit SHA fetch/checkout path in the Dockerfile

Legacy `git clone --branch` wiring for SHA-pinned refs fails validation.

## Environment Variable Overrides

You can override source build args using environment variables:

### Git Source Override

```bash
export REVA_REF="custom-branch"
export REVA_URL="https://github.com/custom/reva"
nu scripts/dockypody.nu build --service my-service
```

After overrides, the build system recomputes `REVA_REF_KIND` from the
effective `REVA_REF`.

### Local Source Override

```bash
export REVA_PATH="/path/to/local/reva"
nu scripts/dockypody.nu build --service my-service
```

**Note:** Environment overrides follow the same type rules as config: only
`{SOURCE_KEY}_PATH` selects local mode. `{SOURCE_KEY}_URL` and
`{SOURCE_KEY}_REF` override Git values on a Git-configured source without
changing its type.

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

- `REVA_REF`, `REVA_URL`, `REVA_REF_KIND` (+ optional `REVA_SHA`) for Git
- `CUSTOM_LIB_PATH`, `CUSTOM_LIB_MODE`, `CUSTOM_LIB_REF_KIND="local"` for local

## Dockerfile Requirements

Dockerfiles MUST declare ARGs with sensible defaults for both source types.

### Git Source ARGs

```dockerfile
ARG REVA_URL="https://github.com/cs3org/reva"
ARG REVA_REF="v3.3.3"
ARG REVA_REF_KIND=""
ARG REVA_SHA=""
```

### Local Source ARGs

```dockerfile
ARG REVA_PATH=""
ARG REVA_MODE=""
ARG REVA_REF_KIND=""
```

### Dual-Mode Pattern

For Dockerfiles that support both Git and local sources, use one
`clone-source.nu` call with bind mount and cache mount as shown in the Git
source Dockerfile usage section above. See
[services/revad-base/Dockerfile.production](../services/revad-base/Dockerfile.production)
for a live example.

**Reminder:** Local directories are copied into `.build-sources/{source}`
inside the service context. Without the explicit bind mount, Docker cannot see
that directory and the local copy step will fail.

## Related Documentation

- [Service Configuration](concepts/service-configuration.md) - Complete
  service configuration guide
- [Build System](concepts/build-system.md) - Build argument injection priority
- [Config Schema](reference/config-schema.md) - Complete schema reference
- [Dockerfile Development Rules](guides/dockerfile-development.md) - Enforced
  Dockerfile patterns
