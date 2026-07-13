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
use ./workflow.nu [gen-workflow]
use ./cache-shards.nu [make-shard-name]
use ./artifacts.nu [get-github-run-context list-run-artifacts-github download-and-load-shard]
use ../build/cache.nu [get-dep-nodes-for-service]
use ../build/dep-nodes.nu [get-matching-dependency-shards]
use ../build/pull.nu [compute-canonical-image-ref]
use ../registries/info.nu [get-registry-info]
use ../registries/core.nu [login-default-registry]
use ./ghcr/cli.nu [ghcr-purge-cli validate-force-flags]
use ../plane/guard.nu [parse-plane reject-local-plane-for-tracked-generator]

# Re-export for direct module usage
export use ./deps.nu [get-direct-dependency-services get-all-dependency-services]
export use ./workflow.nu [gen-workflow]

# Prepare dependency shards by downloading artifacts from current workflow run
# Soft-failure: returns true even on errors, letting dep-cache handle rebuilds
export def prepare-node-deps-internal [
  service: string,
  version: string,
  platform: string,
  dependencies: string,
  debug: bool
] {
  if ($service | str length) == 0 or ($version | str length) == 0 {
    print --stderr "ERROR: --service and --version are required for ci prepare-node-deps"
    return false
  }

  # Parse dependencies comma-separated string
  let dep_services = (if ($dependencies | str length) == 0 {
    []
  } else {
    $dependencies | split row "," | each {|s| $s | str trim} | where {|s| ($s | str length) > 0}
  })

  if ($dep_services | is-empty) {
    if $debug {
      print --stderr "DEBUG: No dependencies to prepare"
    }
    return true
  }

  if $debug {
    print --stderr $"DEBUG: Preparing deps for ($service):($version):($platform)"
    print --stderr $"DEBUG: Dependency services: ($dep_services | str join ', ')"
  }

  # Get GitHub run context - soft failure if not in CI
  let ctx = (get-github-run-context)
  if not $ctx.ok {
    print --stderr $"INFO: Skipping artifact download - ($ctx.reason)"
    print --stderr "INFO: Dependency images will be rebuilt by dep-cache if needed"
    return true
  }

  if $debug {
    print --stderr $"DEBUG: GitHub context: ($ctx.owner)/($ctx.repo) run ($ctx.run_id)"
  }

  # List artifacts for this run - cache the list
  let artifacts = (list-run-artifacts-github $ctx)
  if ($artifacts | is-empty) {
    if $debug {
      print --stderr "DEBUG: No artifacts found in current run"
    }
    return true
  }

  if $debug {
    print --stderr $"DEBUG: Found ($artifacts | length) artifact\(s\) in run"
  }

  # Get candidate shards to load based on dep services and target platform
  let candidates = (get-matching-dependency-shards $dep_services $platform)
  
  if ($candidates | is-empty) {
    if $debug {
      print --stderr "DEBUG: No dependency shard candidates computed"
    }
    return true
  }

  if $debug {
    print --stderr $"DEBUG: Will attempt to load ($candidates | length) shard\(s\)"
  }

  # Try to download and load each candidate shard
  mut requested = 0
  mut found = 0
  mut loaded = 0

  for candidate in $candidates {
    $requested = $requested + 1
    let shard_name = (make-shard-name $candidate.service $candidate.version $candidate.platform)
    
    if $debug {
      print --stderr $"DEBUG: Looking for shard: ($shard_name)"
    }

    let result = (download-and-load-shard $ctx $artifacts $candidate.service $candidate.version $candidate.platform)
    
    if $result.ok {
      $found = $found + 1
      $loaded = $loaded + (try { $result.loaded } catch { 1 })
      print --stderr $"Loaded shard: ($shard_name)"
    } else {
      if $debug {
        print --stderr $"DEBUG: ($result.reason)"
      }
    }
  }

  print --stderr $"Shard summary: requested=($requested) found=($found) images_loaded=($loaded)"
  
  # Always return true - missing shards are handled by dep-cache
  true
}

# Show CI CLI help
export def ci-help [] {
  print "Usage: nu scripts/dockypody.nu ci <subcommand> [options]"
  print ""
  print "Subcommands:"
  print "  list-deps             List dependency services"
  print "  prepare-node-deps     Download and load dependency shards from artifacts (CI only)"
  print "  workflow              Generate CI workflows (requires --target: all|build|build-push|orchestrator|build-service|image-purge)"
  print "  images                List canonical image references for a service"
  print "  login-registry        Log in to container registry (CI only)"
  print "  ghcr-purge            Purge stale GHCR package versions based on SSOT"
  print ""
  print "Options:"
  print "  --service <name>        Target service"
  print "  --version <name>        Target version (for prepare-node-deps)"
  print "  --platform <name>       Target platform (for prepare-node-deps)"
  print "  --dependencies <list>   Comma-separated dependency services (for prepare-node-deps)"
  print "  --target <name>         Workflow target (required for workflow: all, build, build-push, orchestrator, build-service, image-purge)"
  print "  --transitive            Include transitive dependencies"
  print "  --dry-run               Show what would be done without deleting"
  print "  --max-deletes <n>       Global budget: max versions deleted across ALL services in this run (0 = unlimited, default: 0)"
  print "  --force                 For ci ghcr-purge: when desired_tags is empty, delete all candidates instead of only untagged ones."
  print "                          Requires --service (single service only) and --dry-run=false."
  print "  --partial-success       For ci ghcr-purge: tolerate live delete failures and continue."
  print "                          Default is strict: any live delete failure exits 1."
  print "  --debug                 Enable verbose output"
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

# Log in to container registry (CI helper)
def login-registry [--debug] {
  let result = (login-default-registry)
  
  if not $result.ok {
    print --stderr $"ERROR: Failed to log in to registry ($result.registry): ($result.reason)"
    exit 1
  }
  
  if $debug {
    if ($result.registry | str length) > 0 {
      print --stderr $"DEBUG: Successfully logged in to ($result.registry)"
    } else {
      print --stderr $"DEBUG: ($result.reason)"
    }
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
  subcommand: string,  # Subcommand: list-deps, prepare-node-deps, workflow, images, login-registry, ghcr-purge, help
  flags: record        # Flags: { service, version, platform, dependencies, target, transitive, debug, dry_run, max_deletes, force, partial_success }
] {
  let service = (try { $flags.service } catch { "" })
  let version = (try { $flags.version } catch { "" })
  let platform = (try { $flags.platform } catch { "" })
  let dependencies = (try { $flags.dependencies } catch { "" })
  let target = (try { $flags.target } catch { "" })
  let transitive = (try { $flags.transitive } catch { false })
  let debug = (try { $flags.debug } catch { false })
  let dry_run = (try { $flags.dry_run } catch { false })
  let max_deletes = (try { $flags.max_deletes } catch { 0 })
  let force = (try { $flags.force } catch { false })
  let partial_success = (try { $flags.partial_success } catch { false })
  let plane = (parse-plane (try { $flags.plane } catch { "tracked" }))
  
  match $subcommand {
    "help" => {
      ci-help
    }
    "list-deps" => {
      list-deps --service $service --transitive=$transitive --debug=$debug
    }
    "prepare-node-deps" => {
      let ok = (prepare-node-deps-internal $service $version $platform $dependencies $debug)
      if not $ok {
        exit 1
      }
    }
    "workflow" => {
      reject-local-plane-for-tracked-generator $plane "CI workflow generation"
      use ./workflow.nu [get-workflows-for-target write-workflows]

      if ($target | str length) == 0 {
        print --stderr "ERROR: --target is required for ci workflow (all, build, build-push, orchestrator, build-service, image-purge)"
        exit 1
      }
      let workflows = (get-workflows-for-target $target)
      write-workflows $workflows --dry-run=$dry_run
    }
    "images" => {
      list-service-images $service
    }
    "login-registry" => {
      login-registry --debug=$debug
    }
    "ghcr-purge" => {
      reject-local-plane-for-tracked-generator $plane "GHCR SSOT tag purge"
      ghcr-purge-cli $service $dry_run $max_deletes $debug $force --partial-success=$partial_success
    }
    _ => {
      print $"Unknown ci subcommand: ($subcommand)"
      print ""
      ci-help
      exit 1
    }
  }
}
