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

# Build CLI facade - delegates to build orchestration
# See docs/concepts/build-system.md for architecture

use ./meta.nu [detect-build]
use ../registries/info.nu [get-registry-info]
use ./config.nu [parse-bool-flag]
use ./cache.nu [parse-dep-cache-mode]
use ./pull.nu [parse-pull-modes]
use ./orchestrate.nu [run-build]

# Show build CLI help
export def build-help [] {
  print "Usage: nu scripts/dockypody.nu build [options]"
  print ""
  print "Build Options:"
  print "  --service <name>       Build specific service"
  print "  --all-services         Build all services in dependency order"
  print "  --version <ver>        Build specific version"
  print "  --all-versions         Build all versions from manifest"
  print "  --versions <list>      Build specific versions (comma-separated)"
  print "  --platform <plat>      Build for specific platform"
  print "  --show-build-order     Show build order without building"
  print "  --matrix-json          Output CI matrix JSON"
  print ""
  print "Push/Tag Options:"
  print "  --push                 Push images after build"
  print "  --latest               Tag as latest"
  print "  --extra-tag <tag>      Add extra tag"
  print "  --provenance           Enable provenance attestation"
  print "  --push-deps            Also push dependency images"
  print "  --tag-deps             Also tag dependencies"
  print ""
  print "Cache Options:"
  print "  --no-cache             Disable Docker layer cache"
  print "  --cache-bust <key>     Force cache invalidation"
  print "  --dep-cache <mode>     Dependency cache mode (off, soft, strict)"
  print "  --cache-match <mode>   Cache match reporting (off, on, verbose)"
  print ""
  print "Build Behavior:"
  print "  --latest-only          Only build latest version"
  print "  --fail-fast            Stop on first failure"
  print "  --progress <mode>      Docker progress output (auto, plain, tty)"
  print "  --pull <mode>          Pre-pull behavior (off, on, always)"
  print "  --disk-monitor <mode>  Disk usage monitoring (off, on)"
  print "  --prune-cache-mounts   Prune BuildKit cache between versions"
}

# Build CLI entrypoint - called from dockypody.nu
# Constructs context and delegates to orchestration layer
export def build-cli [
  --service: string,
  --all-services,
  --push,
  --latest,
  --extra-tag: string = "",
  --provenance,
  --version: string = "",
  --all-versions,
  --versions: string = "",
  --latest-only,
  --platform: string = "",
  --matrix-json,
  --progress: string = "auto",
  --cache-bust: string = "",
  --no-cache,
  --show-build-order,
  --dep-cache: string = "",
  --push-deps,
  --tag-deps,
  --fail-fast,
  --pull: string = "",
  --cache-match: string = "",
  --disk-monitor: string = "off",
  --prune-cache-mounts
] {
  # Detect build environment (local vs CI)
  let meta = (detect-build)
  
  # Get registry info
  let info = (get-registry-info)
  
  # Normalize boolean flags
  let all_services_val = (parse-bool-flag ($all_services | default false))
  let push_val = (parse-bool-flag ($push | default false))
  let latest_val = (parse-bool-flag ($latest | default true))
  let provenance_val = (parse-bool-flag ($provenance | default false))
  let all_versions_val = (parse-bool-flag ($all_versions | default false))
  let latest_only_val = (parse-bool-flag ($latest_only | default false))
  let matrix_json_val = (parse-bool-flag ($matrix_json | default false))
  let no_cache_val = (parse-bool-flag ($no_cache | default false))
  let show_build_order_val = (parse-bool-flag ($show_build_order | default false))
  let push_deps_val = (parse-bool-flag ($push_deps | default false))
  let tag_deps_val = (parse-bool-flag ($tag_deps | default false))
  let fail_fast_val = (parse-bool-flag ($fail_fast | default false))
  let prune_cache_mounts_val = (parse-bool-flag ($prune_cache_mounts | default false))
  
  # Parse complex flags
  let dep_cache_mode = (parse-dep-cache-mode $dep_cache $meta.is_local)
  let pull_modes = (parse-pull-modes $pull)
  
  # Construct context record for orchestration
  let ctx = {
    flags: {
      service: $service,
      all_services: $all_services_val,
      push: $push_val,
      latest: $latest_val,
      extra_tag: $extra_tag,
      provenance: $provenance_val,
      version: $version,
      all_versions: $all_versions_val,
      versions: $versions,
      latest_only: $latest_only_val,
      platform: $platform,
      matrix_json: $matrix_json_val,
      progress: $progress,
      cache_bust: $cache_bust,
      no_cache: $no_cache_val,
      show_build_order: $show_build_order_val,
      dep_cache: $dep_cache_mode,
      push_deps: $push_deps_val,
      tag_deps: $tag_deps_val,
      fail_fast: $fail_fast_val,
      pull: $pull_modes,
      cache_match: $cache_match,
      disk_monitor: $disk_monitor,
      prune_cache_mounts: $prune_cache_mounts_val
    },
    meta: $meta,
    registry_info: $info
  }
  
  # Delegate to orchestration layer
  run-build $ctx
}
