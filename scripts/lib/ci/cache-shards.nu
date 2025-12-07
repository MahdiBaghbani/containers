#!/usr/bin/env nu

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

# CI cache shard helpers for per-node image tarballs
# See docs/concepts/build-system.md for dep-cache and CI caching overview

use ../build/cache.nu [get-owner-cache-dir get-image-tarball-path get-manifest-path write-manifest]
use ../build/pull.nu [compute-canonical-image-ref]
use ../registries/info.nu [get-registry-info]

const SHARD_MANIFEST_EXTENSION = ".nuon"

# Build canonical node key: service:version or service:version:platform
export def make-node-key [
  service: string,
  version: string,
  platform: string = ""
] {
  if ($platform | str length) > 0 {
    $"($service):($version):($platform)"
  } else {
    $"($service):($version)"
  }
}

# Build shard artifact name: shard-<service>-<version>-<platform|single>
# This is the single source of truth for artifact naming in CI workflows.
export def make-shard-name [
  service: string,
  version: string,
  platform: string = ""
] {
  let platform_part = (if ($platform | str length) > 0 { $platform } else { "single" })
  $"shard-($service)-($version)-($platform_part)"
}

# Internal: get Docker image ID for a given image reference
def get-docker-image-id [image_ref: string] {
  try {
    let result = (^docker image inspect $image_ref --format "{{.Id}}" | complete)
    if $result.exit_code == 0 {
      $result.stdout | str trim
    } else {
      ""
    }
  } catch {
    ""
  }
}

# Internal: compute shard file layout for a node+image
def compute-shard-layout [
  service: string,
  version: string,
  platform: string,
  base_dir: string,
  image_id: string,
  image_ref: string
] {
  let node_key = (make-node-key $service $version $platform)

  # Shard directory is scoped by service; caller may further scope by ref/sha
  let shard_dir = (if ($base_dir | path exists) { $base_dir } else { $base_dir })

  if not ($shard_dir | path exists) {
    mkdir $shard_dir
  }

  # Reuse cache.nu filename convention but under shard_dir to keep layout predictable
  let safe_id = ($image_id | str replace "sha256:" "")
  let tarball_path = $"($shard_dir)/($safe_id).tar.zst"
  let manifest_path = $"($shard_dir)/($safe_id)($SHARD_MANIFEST_EXTENSION)"

  {
    node_key: $node_key,
    shard_dir: $shard_dir,
    tarball_path: $tarball_path,
    manifest_path: $manifest_path,
    image_id: $image_id,
    image_ref: $image_ref
  }
}

# Create a shard for a single node by inspecting Docker and writing tarball + manifest
#
# Parameters:
#   service, version, platform: node identity
#   base_dir: directory under which shard files will be written
#
# The caller is responsible for ensuring the image already exists locally.
export def create-node-shard [
  service: string,
  version: string,
  base_dir: string,
  platform: string = ""
] {
  if ($service | str length) == 0 or ($version | str length) == 0 {
    error make {
      msg: "create-node-shard requires non-empty service and version"
    }
  }

  # Determine registry context from CI environment
  let registry_info = (get-registry-info)
  let is_local = ($registry_info.ci_platform == "local")

  let node_key = (make-node-key $service $version $platform)
  let image_ref = (compute-canonical-image-ref $node_key $registry_info $is_local)

  let image_id = (get-docker-image-id $image_ref)
  if ($image_id | str length) == 0 {
    error make {
      msg: $"Docker image not found for ref '($image_ref)' (node '($node_key)')"
    }
  }

  let layout = (compute-shard-layout $service $version $platform $base_dir $image_id $image_ref)

  # Save tarball for this single image (all refs for image_id are equivalent)
  let save_result = (try {
    let cmd_result = (^docker save $image_ref | ^zstd -T0 -3 -o $layout.tarball_path | complete)
    if $cmd_result.exit_code == 0 {
      {success: true, error: ""}
    } else {
      {success: false, error: (try { $cmd_result.stderr } catch { "Unknown error" })}
    }
  } catch {|err|
    {success: false, error: (try { $err.msg } catch { "Command failed" })}
  })

  if not $save_result.success {
    error make {
      msg: $"Failed to save shard tarball for image '($image_id | str substring 0..16)...': ($save_result.error)"
    }
  }

  # Write tiny shard manifest for this node
  let shard_manifest = {
    node_key: $layout.node_key,
    image_id: $layout.image_id,
    refs: [$layout.image_ref]
  }

  $shard_manifest | to nuon | save -f $layout.manifest_path

  $layout
}

# Merge all node shards under base_dir into the owner cache for a service
# and write a final manifest.nuon compatible with cache.nu
export def merge-node-shards [
  service: string,
  base_dir: string
] {
  if ($service | str length) == 0 {
    error make {
      msg: "merge-node-shards requires non-empty service"
    }
  }

  if not ($base_dir | path exists) {
    error make {
      msg: $"Shard directory does not exist: ($base_dir)"
    }
  }

  let manifest_files = (ls $base_dir | where {|f| $f.type == "file" and ($f.name | str ends-with $SHARD_MANIFEST_EXTENSION)} | get name)

  if ($manifest_files | is-empty) {
    error make {
      msg: $"No shard manifests found under directory: ($base_dir)"
    }
  }

  mut nodes = {}
  mut images = {}

  for path in $manifest_files {
    let shard = (open $path)
    let node_key = (try { $shard.node_key } catch { "" })
    let image_id = (try { $shard.image_id } catch { "" })
    let refs = (try { $shard.refs } catch { [] })

    if ($node_key | str length) == 0 or ($image_id | str length) == 0 {
      continue
    }

    # Update node -> image mapping
    $nodes = ($nodes | upsert $node_key $image_id)

    # Update image -> refs mapping using dep-cache style schema
    let existing = (try { $images | get $image_id } catch { null })
    let owner_service = $service
    let merged_refs = (if $existing == null {
      $refs
    } else {
      let current = (try { $existing.refs } catch { [] })
      ($current | append $refs) | uniq
    })

    $images = ($images | upsert $image_id {
      refs: $merged_refs,
      owner_service: $owner_service
    })
  }

  let owner_cache_dir = (get-owner-cache-dir $service)

  if not ($owner_cache_dir | path exists) {
    mkdir $owner_cache_dir
  }

  # Move shard tarballs into owner cache using cache.nu naming
  let shard_tarballs = (ls $base_dir | where {|f| $f.type == "file" and ($f.name | str ends-with ".tar.zst")} | get name)

  for shard_tar in $shard_tarballs {
    # Derive image_id from filename (strip extension and optional directory)
    let filename = ($shard_tar | path basename)
    let image_id_no_prefix = ($filename | str replace ".tar.zst" "")
    let target_path = (get-image-tarball-path $service $image_id_no_prefix)

    # Ensure target directory exists
    let target_dir = ($target_path | path dirname)
    if not ($target_dir | path exists) {
      mkdir $target_dir
    }

    mv $shard_tar $target_path
  }

  # Write final manifest for owner cache using existing helper
  write-manifest $service {nodes: $nodes, images: $images}

  {
    nodes: $nodes,
    images: $images
  }
}
