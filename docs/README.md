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
# Documentation

Overview of DockyPody documentation structure.

## Documentation Structure

- **[Concepts](concepts/)** - System understanding (what/why)
- **[Guides](guides/)** - Step-by-step tutorials (how-to)
- **[Reference](reference/)** - Complete API/schema documentation

## Quick Navigation

### For New Users

- Start with [Getting Started](guides/getting-started.md)
- Then read [Service Configuration](concepts/service-configuration.md)

### For Developers

- [Nushell Development Guide](guides/nushell-development.md) - Essential before editing scripts
- [Build System](concepts/build-system.md) - Build system architecture

### For Service Authors

- [Service Setup Guide](guides/service-setup.md) - Creating new services
- [Multi-Version Builds](guides/multi-version-builds.md) - Version management
- [Multi-Platform Builds](guides/multi-platform-builds.md) - Platform variants

### Reference Documentation

- [CLI Reference](reference/cli-reference.md) - Complete CLI documentation
- [Config Schema](reference/config-schema.md) - Service configuration schema
- [Version Manifest Schema](reference/version-manifest-schema.md) - Version manifest schema
- [Platform Manifest Schema](reference/platform-manifest-schema.md) - Platform manifest schema

## Topic Index

See [index.md](index.md) for comprehensive topic index.

## Contributing

Document solutions as you find them. Keep debugging scenarios updated.

## Markdown Formatting

All markdown files must pass linting checks. Common requirements:

- **Lists:** Must have blank lines before them when following text ending with a colon
- **Code blocks:** Must have blank lines before and after, and must specify a language tag (`nu`, `nuon`, `dockerfile`, `bash`, `json`, `yaml`, `text`)
- **Headings:** Must have blank lines before and after them
- **Bold headers:** Convert `**Text:**` used as section headers to proper headings (`###` or `####`)
- **Duplicate headings:** Make headings unique by adding context (e.g., `#### Problem: Specific Issue`)

Before committing, run linting checks and fix all errors. See `.cursor/rules/writing.mdc` for complete markdown linting guidelines and common mistakes.
