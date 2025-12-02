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

# CI/CD Workflows

> **Status:** Documentation pending implementation

This section will document CI/CD workflows and automation for the DockyPody build system.

## Topics to Document

- GitHub Actions workflows (`.github/workflows/build.yml`, `.github/workflows/build-push.yml`)
- Forgejo Actions workflows (`.forgejo/workflows/build-containers.yml`)
- CI/CD build triggers and matrix generation
- Registry authentication in CI environments
- Multi-arch build strategy in CI
- Explicit workflow control (builds are triggered by workflow dispatch, not inferred from commits)
- Build vs validation workflows (PR validation does not build images)

## Related Documentation

- [Build System](../concepts/build-system.md) - Build system architecture and features
- [CLI Reference](../reference/cli-reference.md) - Complete CLI documentation
