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

# Documentation Index

## Concepts (What/Why)

- [Service Configuration](concepts/service-configuration.md) - Service config structure, JSONC requirements, version manifests requirement
- [Dependency Management](concepts/dependency-management.md) - Dependency resolution, version inheritance, platform inheritance
- [Build System](concepts/build-system.md) - Build argument injection, build flow, file structure
- [TLS Management](concepts/tls-management.md) - Certificate management, CA propagation, selective copying

## Guides (How-To)

- [Getting Started](guides/getting-started.md) - Quick start tutorial
- [Service Setup](guides/service-setup.md) - Creating and configuring services
- [Multi-Version Builds](guides/multi-version-builds.md) - Building multiple versions
- [Multi-Platform Builds](guides/multi-platform-builds.md) - Building platform variants
- [Nushell Development](guides/nushell-development.md) - Nushell scripting guide
- [Docker Buildx](guides/docker-buildx.md) - Docker Buildx features and cache mounts
- [System Administration](guides/system-administration.md) - System administration tasks
- [CI/CD Workflows](guides/ci-cd.md) - CI/CD workflow documentation (pending)

## Reference (API/Schema)

- [CLI Reference](reference/cli-reference.md) - Complete CLI documentation
- [Config Schema](reference/config-schema.md) - Service configuration schema
- [Version Manifest Schema](reference/version-manifest-schema.md) - Version manifest schema
- [Platform Manifest Schema](reference/platform-manifest-schema.md) - Platform manifest schema
- [Makefile Reference](reference/makefile-reference.md) - Makefile documentation (pending)
