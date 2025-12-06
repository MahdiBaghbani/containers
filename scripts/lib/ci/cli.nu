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

# CI CLI facade - see docs/reference/cli-reference.md

use ./deps.nu [get-direct-dependency-services get-all-dependency-services]
use ./tarballs.nu [load-dep-tarballs load-owner save-owner]
use ./workflow.nu [gen-workflow]
use ../build/cache.nu [get-dep-nodes-for-service]
use ../build/pull.nu [compute-canonical-image-ref]
use ../registries/info.nu [get-registry-info]

# Re-export for direct module usage
export use ./deps.nu [get-direct-dependency-services get-all-dependency-services]
export use ./tarballs.nu [load-dep-tarballs load-owner save-owner]
export use ./workflow.nu [gen-workflow]

# Show CI CLI help
export def ci-help [] {
  print "Usage: nu scripts/dockypody.nu ci <subcommand> [options]"
  print ""
  print "Subcommands:"
  print "  list-deps      List dependency services"
  print "  load-deps      Load dependency tarballs"
  print "  load-owner     Load owner tarballs"
  print "  save-owner     Save owner tarballs"
  print "  workflow       Generate CI workflows (--target all|build|build-push|orchestrator)"
  print "  images         List canonical image references for a service"
  print ""
  print "Options:"
  print "  --service <name>   Target service"
  print "  --target <name>    Workflow target (for workflow subcommand: all, build, build-push, orchestrator)"
  print "  --transitive       Include transitive dependencies"
  print "  --dry-run          Show what would be done"
}

# List dependencies for a service
export def list-deps [
    --service: string  # Service name to list dependencies for
    --transitive       # Include transitive dependencies (default: direct only)
    --debug            # Enable verbose output on stderr
] {
    if ($service | str length) == 0 {
        print --stderr "ERROR: --service is required"
        exit 1
    }

    let mode = (if $transitive { "transitive" } else { "direct" })
    if $debug {
        print --stderr $"DEBUG: Getting ($mode) dependencies for service: ($service)"
    }

    let dep_services = (if $transitive {
        get-all-dependency-services $service
    } else {
        get-direct-dependency-services $service
    })

    if $debug {
        print --stderr $"DEBUG: Found ($dep_services | length) ($mode) dependencies"
    }

    # Output each dependency on its own line (clean stdout for CI parsing)
    for dep in $dep_services {
        print $dep
    }
}

# List canonical image references for a service (for CI caching)
def list-service-images [service: string] {
    if ($service | str length) == 0 {
        print --stderr "ERROR: --service is required"
        exit 1
    }

    # Get registry info for CI environment detection
    let registry_info = (get-registry-info)
    let is_local = ($registry_info.ci_platform == "local")

    # Get all nodes for the service using dep-cache module
    let nodes = (get-dep-nodes-for-service $service $registry_info $is_local)

    if ($nodes | is-empty) {
        print --stderr $"WARNING: Service '($service)' has no versions or nodes defined"
        return
    }

    # Convert nodes to canonical image refs
    let image_refs = ($nodes | each {|node|
        compute-canonical-image-ref $node.node_key $registry_info $is_local
    })

    # Deduplicate and print one per line
    let unique_refs = ($image_refs | uniq)
    for ref in $unique_refs {
        print $ref
    }
}

# CI CLI entrypoint - called from dockypody.nu
export def ci-cli [
  subcommand: string,  # Subcommand: list-deps, load-deps, load-owner, save-owner, workflow, images, help
  flags: record        # Flags: { service, target, transitive, debug, dry_run }
] {
  let service = (try { $flags.service } catch { "" })
  let target = (try { $flags.target } catch { "all" })
  let transitive = (try { $flags.transitive } catch { false })
  let debug = (try { $flags.debug } catch { false })
  let dry_run = (try { $flags.dry_run } catch { false })
  
  match $subcommand {
    "help" | "--help" | "-h" => {
      ci-help
    }
    "list-deps" => {
      list-deps --service $service --transitive=$transitive --debug=$debug
    }
    "load-deps" => {
      load-dep-tarballs --service $service
    }
    "load-owner" => {
      load-owner --service $service
    }
    "save-owner" => {
      save-owner --service $service
    }
    "workflow" => {
      use ./workflow.nu [get-workflows-for-target write-workflows]
      
      let workflows = (get-workflows-for-target $target)
      write-workflows $workflows --dry-run=$dry_run
    }
    "images" => {
      list-service-images $service
    }
    _ => {
      print $"Unknown ci subcommand: ($subcommand)"
      print ""
      ci-help
      exit 1
    }
  }
}
