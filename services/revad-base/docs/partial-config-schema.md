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

# Partial Configuration Schema

## Overview

Complete reference for partial configuration files used to extend base Reva configurations without duplication.

**Note**: This is Reva-specific documentation. For DockyPody build system documentation, see [`docs/`](../../../docs/).

## Schema Location

Partial configurations are stored as `.toml` files in partial directories:

- **Build-time**: `services/{service}/configs/partial/*.toml` (merged during Dockerfile build)
- **Runtime**: `/etc/revad/partial/*.toml` (volume mount) or `/configs/partial/*.toml` (image fallback)

For the authoritative schema file, see [`services/revad-base/schemas/partial-config.nuon`](../schemas/partial-config.nuon).

## Architecture and Design

For architecture details, design decisions, and implementation:

- **Service Documentation**: See [`configuration.md`](configuration.md#partial-configuration-system) for partial config system overview
- **CERNBox Partials**: See [`services/cernbox-revad/docs/configuration.md`](../../cernbox-revad/docs/configuration.md#partial-configurations) for CERNBox-specific partials

## Purpose

Partial configs allow you to:

- **Extend base configs** without duplicating entire configuration files
- **Add services** (e.g., thumbnail service) to existing configs
- **Maintain separation** between base configs and service-specific additions
- **Support both maintainers and end users** (build-time and runtime partials)

## File Structure

### Required Section: `[target]`

Every partial config file must start with a `[target]` section that defines:

```toml
[target]
file = "gateway.toml"  # Required: target config file name
order = 1             # Optional: merge order (integer)
```

**Fields**:

- **`file`** (string, required): The name of the target config file (e.g., `"gateway.toml"`, `"dataprovider-localhome.toml"`)
- **`order`** (integer, optional): Explicit merge order number. Partials with explicit numbers are sorted numerically. Unnumbered partials are sorted alphabetically.

### Content Section

After the `[target]` section, include any TOML content that should be merged into the target file:

```toml
[target]
file = "gateway.toml"
order = 1

# Content below is merged into gateway.toml
[http.services.thumbnails]
cache = "lru"
output_type = "jpg"
quality = 80
```

## Ordering Rules

Partials are merged in a specific order based on these rules:

1. **Explicit order numbers** take precedence and are sorted numerically (1, 2, 3, ...)
2. **Unnumbered partials** are sorted alphabetically by filename
3. **Auto-assigned order** starts after the highest explicit number
4. **Per-target ordering**: Each target file has its own independent sequence

### Example

Given these partials for `gateway.toml`:

- `thumbnails.toml` (no order)
- `cernbox-extras.toml` (order = 2)
- `ocm-config.toml` (order = 1)
- `logging.toml` (no order)

**Result**:

1. `ocm-config.toml` (order = 1)
2. `cernbox-extras.toml` (order = 2)
3. `thumbnails.toml` (auto-order = 3, alphabetical first)
4. `logging.toml` (auto-order = 4, alphabetical second)

## Build-Time vs Runtime Partials

### Build-Time Partials (Maintainers)

**Location**: `services/{service}/configs/partial/*.toml`

**When**: Merged during Dockerfile build

**Use Case**: Maintainers adding features to base services

**Example**: CERNBox maintainer adds thumbnail service to `revad-base`

```toml
# services/revad-base/configs/partial/thumbnails.toml
[target]
file = "gateway.toml"
order = 1

[http.services.thumbnails]
cache = "lru"
```

**Result**: Merged into image at `/configs/revad/gateway.toml` during build

### Runtime Partials (End Users)

**Location**: `/etc/revad/partial/*.toml` (volume) or `/configs/partial/*.toml` (image)

**When**: Merged during container initialization

**Use Case**: End users adding custom services without rebuilding images

**Example**: End user adds custom service via volume mount

```toml
# /etc/revad/partial/custom.toml (volume mount)
[target]
file = "gateway.toml"
order = 20

[http.services.custom]
enabled = true
```

**Result**: Merged into `/etc/revad/gateway.toml` at runtime

## Marker System (Runtime Only)

When partials are merged at runtime, they are automatically wrapped with comment markers:

```toml
# === Merged from: thumbnails.toml (order: 1) ===
# This section was automatically merged from a partial config file.
# DO NOT EDIT MANUALLY - changes will be lost on container restart.
# To modify, edit the source partial file instead.

[http.services.thumbnails]
cache = "lru"
# ... content ...

# === End of merge from: thumbnails.toml ===
```

**Purpose**: These markers allow the system to:

- Remove old merged sections on container restart (prevents duplicates)
- Identify which sections came from partials
- Preserve user edits (unmarked sections are not removed)

**Note**: Build-time partials are merged without markers (baked into image).

## Placeholder Support

Partials can contain placeholders that are processed after merging:

```toml
[target]
file = "gateway.toml"

[http.services.thumbnails]
cache = "lru"
quality = {{placeholder:THUMBNAIL_QUALITY:80}}
```

**Flow**:

1. Partial merged into config
2. Placeholders processed (replaced with environment variables)
3. Config ready for use

## Complete Example

### Thumbnail Service Partial

```toml
# services/cernbox-revad/configs/partial/thumbnails.toml
[target]
file = "gateway.toml"
order = 1

[http.services.thumbnails]
cache = "lru"
output_type = "jpg"
quality = 80
insecure = true
fixed_resolutions = ["36x36"]

[http.services.thumbnails.cache_drivers.lru]
size = 1000000
expiration = 172800
```

### Result in gateway.toml

After merge (with markers at runtime):

```toml
# ... existing gateway.toml content ...

# === Merged from: thumbnails.toml (order: 1) ===
# This section was automatically merged from a partial config file.
# DO NOT EDIT MANUALLY - changes will be lost on container restart.
# To modify, edit the source partial file instead.

[http.services.thumbnails]
cache = "lru"
output_type = "jpg"
quality = 80
insecure = true
fixed_resolutions = ["36x36"]

[http.services.thumbnails.cache_drivers.lru]
size = 1000000
expiration = 172800

# === End of merge from: thumbnails.toml ===
```

## Validation

Partial config files are validated:

- **TOML syntax**: Must be valid TOML (parser will catch errors)
- **Target section**: Must have `[target]` section with `file` field
- **Target file**: Target file must exist (error if missing)
- **Content**: Content must be valid TOML (will be appended to target)

## Error Handling

The merge system uses **hard fail** strategy:

- **Missing target file**: Error with clear message
- **Invalid TOML**: Error from TOML parser
- **Missing `[target]` section**: Error with guidance
- **Invalid order**: Error if order is not an integer

## Best Practices

1. **Use explicit order** for critical partials (ensures consistent ordering)
2. **Use descriptive filenames** for unnumbered partials (affects alphabetical ordering)
3. **Keep partials focused** (one service or feature per partial)
4. **Document partials** (add comments explaining what they do)
5. **Test partials** (verify merge order and content)

## Integration Points

Partials are merged in mode-specific initialization scripts:

- `init-gateway.nu` - Merges partials for `gateway.toml`
- `init-dataprovider.nu` - Merges partials for `dataprovider-*.toml`
- Other mode init scripts - Merge partials for their respective configs

**Timing**: Partials are merged **after** config copy (if needed), **before** placeholder processing.

## See Also

- [Configuration System](configuration.md) - Reva configuration system overview
- [Schema File](../schemas/partial-config.nuon) - Authoritative schema definition
- [CERNBox Partials](../../cernbox-revad/docs/configuration.md#partial-configurations) - CERNBox-specific partials
