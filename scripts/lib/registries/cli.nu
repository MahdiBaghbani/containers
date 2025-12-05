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

# Registries CLI facade - scaffolding for future registry tooling
# See docs/reference/cli-reference.md for usage
#
# NOTE: This is scaffolding for future CLI behavior.
# Any new CLI commands for registry management must be added here.

# Registries CLI entrypoint - called from dockypody.nu
export def registries-cli [
  subcommand: string,  # Subcommand (none available yet)
  flags: record        # Flags (none available yet)
] {
  print "Registries CLI - no subcommands available yet"
  print ""
  print "This is scaffolding for future registry management tooling."
  print "Registry info functions are available via direct module import"
  print "from scripts/lib/registries/core.nu and scripts/lib/registries/info.nu"
  exit 1
}

