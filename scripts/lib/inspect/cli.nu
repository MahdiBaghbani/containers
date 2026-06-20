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

# Inspect CLI facade - guard-owned effective model introspection

use ../plane/guard.nu [guard-plane parse-plane]
use ./effective-config.nu [inspect-effective-config]

export def inspect-help [] {
  print "Usage: nu scripts/dockypody.nu inspect <subcommand> [options]"
  print ""
  print "Subcommands:"
  print "  effective-config   Print guard-owned effective merged config"
  print ""
  print "Options:"
  print "  --service <name>   Service to inspect (required for effective-config)"
  print "  --version <ver>    Version name (default: manifest default)"
  print "  --platform <plat>  Platform name (multi-platform services only)"
  print "  --plane <mode>     Config plane: tracked (default) or local"
  print "                     local requires .dockypody.local/ at repo root"
}

export def inspect-cli [
  subcommand: string,
  flags: record
] {
  let service = (try { $flags.service } catch { "" })
  let version = (try { $flags.version } catch { "" })
  let platform = (try { $flags.platform } catch { "" })
  let plane = (parse-plane (try { $flags.plane } catch { "tracked" }))
  let plane_ctx = (guard-plane $plane)

  match $subcommand {
    "help" => {
      inspect-help
    }
    "effective-config" => {
      if ($service | str length) == 0 {
        error make {msg: "--service is required for inspect effective-config"}
      }
      let cfg = (inspect-effective-config $service $plane_ctx $version $platform)
      $cfg | to json -r
    }
    _ => {
      print $"Unknown inspect subcommand: ($subcommand)"
      print ""
      inspect-help
      exit 1
    }
  }
}
