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

# Docs CLI facade - documentation tools
# See docs/reference/cli-reference.md for usage

use ./lint.nu [lint-docs]

# Show docs CLI help
export def docs-help [] {
  print "Usage: nu scripts/dockypody.nu docs <subcommand> [options]"
  print ""
  print "Subcommands:"
  print "  lint    Check documentation for prohibited characters"
  print ""
  print "Options:"
  print "  --fix              Attempt to fix violations automatically"
  print "  <files>...         Files to check (default: all .md files)"
}

# Docs CLI entrypoint - called from dockypody.nu
export def docs-cli [
  subcommand: string,  # Subcommand: lint, help
  flags: record        # Flags: { files: list<string>, fix: bool }
] {
  match $subcommand {
    "help" | "--help" | "-h" => {
      docs-help
    }
    "lint" => {
      let files = (try { $flags.files } catch { [] })
      let fix = (try { $flags.fix } catch { false })
      let result = (lint-docs $files $fix)
      if not $result {
        exit 1
      }
    }
    _ => {
      print $"Unknown docs subcommand: ($subcommand)"
      print ""
      docs-help
      exit 1
    }
  }
}
