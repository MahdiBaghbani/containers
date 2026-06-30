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

# Makefile Reference

> **Status:** Stub (topic list only)

This page is still a compact reference, but the core build and docs targets
now map to the live `dockypody` CLI surfaces below.

## Build Targets

- `make build` calls the same build entrypoint as CI:
  `nu scripts/dockypody.nu build ...`
- `make build-push` is the push-enabled wrapper over the same CLI surface
- `SERVICE`, `PUSH`, `LATEST`, `PROVENANCE`, `TAG`, and `EXTRA_TAG` shape the
  forwarded build flags
- Use the Make targets when you want the repo's familiar shortcuts; use
  `nu scripts/dockypody.nu ...` when you want the exact underlying command

## Docs Targets

- `make lint-docs` maps to `nu scripts/dockypody.nu docs lint`
- `make lint-docs-fix` maps to `nu scripts/dockypody.nu docs lint --fix`

## Other Topics

- TLS certificate management via Make (`make tls all`, `make tls clean`)
- Full target-by-target variable reference

## Related Documentation

- [Build System](../concepts/build-system.md) - Build system architecture and features
- [CLI Reference](cli-reference.md) - Complete CLI documentation
