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

# Makefile Reference

> **Status:** Documentation pending implementation

This section will document Makefile targets and their Nushell script equivalents.

## Topics to Document

- Make targets and their Nushell script equivalents
- Makefile variables (SERVICE, PUSH, LATEST, PROVENANCE, TAG, EXTRA_TAG)
- When to use Make vs direct Nushell scripts
- TLS certificate management via Make (`make tls all`, `make tls clean`)
- Build commands via Make (`make build`, `make build-push`)
- Documentation linting (`make lint-docs`, `make lint-docs-fix`)

## Related Documentation

- [Build System](../concepts/build-system.md) - Build system architecture and features
- [CLI Reference](cli-reference.md) - Complete CLI documentation
