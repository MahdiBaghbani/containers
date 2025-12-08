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
use ./cache-shards.nu [merge-node-shards make-shard-name]
use ./artifacts.nu [get-github-run-context list-run-artifacts-github download-and-load-shard]
use ../build/cache.nu [get-dep-nodes-for-service]
use ../build/dep-nodes.nu [get-matching-dependency-shards]
use ../build/pull.nu [compute-canonical-image-ref]
use ../registries/info.nu [get-registry-info]
use ../registries/core.nu [login-default-registry]

# Re-export for direct module usage
export use ./deps.nu [get-direct-dependency-services get-all-dependency-services]
export use ./tarballs.nu [load-dep-tarballs load-owner save-owner]
export use ./workflow.nu [gen-workflow]

const SHARD_ROOT_DEFAULT = "/tmp/docker-images/shards"

def get-shard-root [] {
  let override = (try { $env.DOCKYPODY_SHARD_BASE_DIR } catch { "" })
  if ($override | str length) > 0 {
    $override
  } else {
    $SHARD_ROOT_DEFAULT
  }
}

def get-shard-dir [
  service: string,
  shard_root: string
] {
  $"($shard_root)/($service)"
}

export def ci-merge-cache-shards-internal [
  service: string,
  ref: string,
  sha: string,
  debug: bool,
  shard_root: string
] {
  if ($service | str length) == 0 or ($ref | str length) == 0 or ($sha | str length) == 0 {
    print --stderr "ERROR: --service, --ref, and --sha are required for ci merge-cache-shards"
    return false
  }

  let shard_dir = (get-shard-dir $service $shard_root)

  if $debug {
    print --stderr $"DEBUG: Merging cache shards from: ($shard_dir)"
  }

  if not ($shard_dir | path exists) {
    print --stderr $"WARNING: Shard directory does not exist: ($shard_dir) - nothing to merge"
    return true
  }

  let result = (try {
    merge-node-shards $service $shard_dir
    true
  } catch {|err|
    print --stderr $"ERROR: Failed to merge cache shards: ($err.msg)"
    false
  })

  $result
}

export def ci-cleanup-cache-shards-internal [
  service: string,
  ref: string,
  sha: string,
  debug: bool,
  dry_run: bool
] {
  if ($service | str length) == 0 or ($ref | str length) == 0 or ($sha | str length) == 0 {
    print --stderr "ERROR: --service, --ref, and --sha are required for ci cleanup-cache-shards"
    return false
  }

  let prefix = $"images-($service)-($ref)-($sha)-"
  let repo = (try { $env.GITHUB_REPOSITORY } catch { "" })

  if $dry_run {
    if ($repo | str length) == 0 {
      print --stderr $"DRY-RUN: Would delete caches with keys starting with '($prefix)' (GITHUB_REPOSITORY not set)"
    } else {
      print --stderr $"DRY-RUN: Would delete caches with keys starting with '($prefix)' in repo ($repo)"
    }
    return true
  }

  let token = (try { $env.GITHUB_TOKEN } catch { "" })
  if ($token | str length) == 0 {
    print --stderr "WARNING: GITHUB_TOKEN is not set; skipping cache shard cleanup"
    return true
  }

  if ($repo | str length) == 0 {
    print --stderr "WARNING: GITHUB_REPOSITORY is not set; skipping cache shard cleanup"
    return true
  }

  let gh_check = (try { ^gh --version | complete } catch { null })
  if $gh_check == null or $gh_check.exit_code != 0 {
    print --stderr "WARNING: gh CLI is not available; skipping cache shard cleanup"
    return true
  }

  let parts = ($repo | split row "/")
  if ($parts | length) != 2 {
    print --stderr $"WARNING: GITHUB_REPOSITORY has unexpected format: ($repo); skipping cache shard cleanup"
    return true
  }

  let owner = ($parts | get 0)
  let name = ($parts | get 1)
  let api_path = $"/repos/($owner)/($name)/actions/caches"

  if $debug {
    print --stderr $"DEBUG: Fetching caches from GitHub Actions for repo ($repo)"
  }

  let api_result = (try {
    let cmd = (^gh api $api_path | complete)
    if $cmd.exit_code != 0 {
      let stderr = (try { $cmd.stderr } catch { "Unknown error" })
      {ok: false, error: $stderr, body: null}
    } else {
      {ok: true, error: "", body: ($cmd.stdout | from json)}
    }
  } catch {|err|
    {ok: false, error: (try { $err.msg } catch { "Command failed" }), body: null}
  })

  if not $api_result.ok {
    print --stderr $"WARNING: Failed to list caches: ($api_result.error)"
    return true
  }

  let caches = (try { $api_result.body.actions_caches } catch { [] })

  if ($caches | is-empty) {
    if $debug {
      print --stderr "DEBUG: No caches found for repository"
    }
    return true
  }

  let shard_caches = ($caches | where {|c|
    let key = (try { $c.key } catch { "" })
    ($key | str starts-with $prefix)
  })

  if ($shard_caches | length) == 0 {
    if $debug {
      print --stderr $"DEBUG: No caches with prefix '($prefix)' found"
    }
    return true
  }

  print --stderr $"Found ($shard_caches | length) shard cache(s) to delete (prefix: '($prefix)')"

  mut deleted = 0
  mut failed = 0

  for cache in $shard_caches {
    let cache_id = (try { $cache.id } catch { null })
    let cache_key = (try { $cache.key } catch { "" })

    if $cache_id == null {
      continue
    }

    let del_path = $"/repos/($owner)/($name)/actions/caches/($cache_id)"

    if $debug {
      print --stderr $"DEBUG: Deleting cache id=($cache_id) key='($cache_key)'"
    }

    let del_result = (try {
      let cmd = (^gh api -X DELETE $del_path | complete)
      if $cmd.exit_code == 0 {
        {ok: true, error: ""}
      } else {
        let stderr = (try { $cmd.stderr } catch { "Unknown error" })
        {ok: false, error: $stderr}
      }
    } catch {|err|
      {ok: false, error: (try { $err.msg } catch { "Command failed" })}
    })

    if $del_result.ok {
      $deleted = $deleted + 1
    } else {
      $failed = $failed + 1
      print --stderr $"WARNING: Failed to delete cache id=($cache_id) key='($cache_key)': ($del_result.error)"
    }
  }

  print --stderr $"Cleanup summary: deleted=($deleted) failed=($failed)"

  if $failed > 0 {
    print --stderr "WARNING: Some shard caches could not be deleted; continuing without failing CI"
  }

  true
}

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
    print --stderr $"DEBUG: Found ($artifacts | length) artifact(s) in run"
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
    print --stderr $"DEBUG: Will attempt to load ($candidates | length) shard(s)"
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
  print "  list-deps           List dependency services"
  print "  load-deps           Load dependency tarballs"
  print "  load-owner          Load owner tarballs"
  print "  save-owner          Save owner tarballs"
  print "  prepare-node-deps   Download and load dependency shards from artifacts (CI only)"
  print "  workflow            Generate CI workflows (--target all|build|build-push|orchestrator)"
  print "  images              List canonical image references for a service"
  print "  login-registry      Log in to container registry (CI only)"
  print ""
  print "Options:"
  print "  --service <name>        Target service"
  print "  --version <name>        Target version (for prepare-node-deps)"
  print "  --platform <name>       Target platform (for prepare-node-deps)"
  print "  --dependencies <list>   Comma-separated dependency services (for prepare-node-deps)"
  print "  --target <name>         Workflow target (for workflow: all, build, build-push, orchestrator)"
  print "  --transitive            Include transitive dependencies"
  print "  --dry-run               Show what would be done"
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
  subcommand: string,  # Subcommand: list-deps, load-deps, load-owner, save-owner, prepare-node-deps, workflow, images, shard helpers, help
  flags: record        # Flags: { service, version, platform, dependencies, target, ref, sha, transitive, debug, dry_run }
] {
  let service = (try { $flags.service } catch { "" })
  let version = (try { $flags.version } catch { "" })
  let platform = (try { $flags.platform } catch { "" })
  let dependencies = (try { $flags.dependencies } catch { "" })
  let target = (try { $flags.target } catch { "all" })
  let transitive = (try { $flags.transitive } catch { false })
  let debug = (try { $flags.debug } catch { false })
  let dry_run = (try { $flags.dry_run } catch { false })
  let ref = (try { $flags.ref } catch { "" })
  let sha = (try { $flags.sha } catch { "" })
  
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
    "prepare-node-deps" => {
      let ok = (prepare-node-deps-internal $service $version $platform $dependencies $debug)
      if not $ok {
        exit 1
      }
    }
    "workflow" => {
      use ./workflow.nu [get-workflows-for-target write-workflows]
      
      let workflows = (get-workflows-for-target $target)
      write-workflows $workflows --dry-run=$dry_run
    }
    "images" => {
      list-service-images $service
    }
    "login-registry" => {
      login-registry --debug=$debug
    }
    "merge-cache-shards" => {
      let ok = (ci-merge-cache-shards-internal $service $ref $sha $debug (get-shard-root))
      if not $ok {
        exit 1
      }
    }
    "cleanup-cache-shards" => {
      let ok = (ci-cleanup-cache-shards-internal $service $ref $sha $debug $dry_run)
      if not $ok {
        exit 1
      }
    }
    _ => {
      print $"Unknown ci subcommand: ($subcommand)"
      print ""
      ci-help
      exit 1
    }
  }
}
