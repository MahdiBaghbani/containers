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

# Validate CLI facade - service and manifest validation
# See docs/reference/cli-reference.md for usage

use ../services/core.nu [list-service-names]
use ./core.nu [validate-service-complete validate-manifest-file print-validation-results]

# Show validate CLI help
export def validate-help [] {
  print "Usage: nu scripts/dockypody.nu validate [options]"
  print ""
  print "Options:"
  print "  --service <name>   Validate specific service"
  print "  --all-services     Validate all services"
  print "  --manifests-only   Only validate version manifests"
  print ""
  print "Examples:"
  print "  nu scripts/dockypody.nu validate --all-services"
  print "  nu scripts/dockypody.nu validate --service gaia"
  print "  nu scripts/dockypody.nu validate --service gaia --manifests-only"
}

# Validate CLI entrypoint - called from dockypody.nu
export def validate-cli [
  flags: record  # Flags: { service: string, all_services: bool, manifests_only: bool }
] {
  let service = (try { $flags.service } catch { "" })
  let all_services = (try { $flags.all_services } catch { false })
  let manifests_only = (try { $flags.manifests_only } catch { false })
  
  if $all_services {
    print "Validating all services...\n"
    let services = (list-service-names)
    
    # Validate each service and count errors using reduce
    let total_errors = ($services | reduce --fold 0 {|svc, acc|
      print $"--- ($svc) ---"
      let result = (if $manifests_only {
        validate-manifest-file $svc
      } else {
        validate-service-complete $svc
      })
      print-validation-results $result
      print ""
      
      if not $result.valid {
        $acc + 1
      } else {
        $acc
      }
    })
    
    if $total_errors > 0 {
      print $"($total_errors) service\(s\) failed validation"
      exit 1
    } else {
      print "All services passed validation"
    }
  } else if ($service | str length) > 0 {
    print $"Validating service: ($service)\n"
    let result = (if $manifests_only {
      validate-manifest-file $service
    } else {
      validate-service-complete $service
    })
    print-validation-results $result
    if not $result.valid {
      exit 1
    }
  } else if $manifests_only {
    print "Usage: --manifests-only requires --all-services or --service <name>"
    exit 1
  } else {
    validate-help
  }
}
