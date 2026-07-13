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
use ./freshness.nu [lint-docs-refs]

# Show docs CLI help
export def docs-help [] {
  print "Usage: nu scripts/dockypody.nu docs <subcommand> [options]"
  print ""
  print "Subcommands:"
  print "  lint       ASCII hygiene, then service/version freshness"
  print "  lint-refs  Service/version freshness only"
  print "  help       Show this help"
  print ""
  print "Options:"
  print "  --fix              Attempt to fix ASCII violations automatically"
  print "                     (freshness has no autofix; edit docs or add allow comments)"
}

# Docs CLI entrypoint - called from dockypody.nu
export def docs-cli [
  subcommand: string,  # Subcommand: lint, lint-refs, help
  flags: record        # Flags: { files: list<string>, fix: bool }
] {
  match $subcommand {
    "help" => {
      docs-help
    }
    "lint" => {
      let files = (try { $flags.files } catch { [] })
      let fix = (try { $flags.fix } catch { false })
      # ASCII first. On failure, do not run freshness and do not treat the
      # overall lint as a pass (even if freshness would have been clean).
      print "docs lint: ASCII check..."
      let ascii_ok = (lint-docs $files $fix)
      if not $ascii_ok {
        exit 1
      }
      print "docs lint: freshness check..."
      let refs_ok = (lint-docs-refs $files)
      if not $refs_ok {
        exit 1
      }
    }
    "lint-refs" => {
      let files = (try { $flags.files } catch { [] })
      let refs_ok = (lint-docs-refs $files)
      if not $refs_ok {
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
