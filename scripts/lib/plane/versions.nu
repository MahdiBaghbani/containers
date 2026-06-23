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

# Local-plane effective versions manifest (L1 foundation)
# Merges tracked versions.nuon with optional local fragment mirror.

use ../core/records.nu [find-duplicates]
use ../manifest/core.nu [load-versions-manifest]
use ./effective-config.nu [
  load-local-fragment
  validate-local-plane-source-entry
]

const PLANE_LOCAL = "local"

export def merge-version-universe [
  tracked_versions: list,
  fragment_versions: list
] {
  let tracked_names = ($tracked_versions | each {|v| (try { $v.name } catch { "" }) })

  let fragment_by_name = ($fragment_versions | reduce --fold {} {|v, acc|
    let name = (try { $v.name } catch { "" })
    if ($name | str length) > 0 {
      $acc | upsert $name $v
    } else {
      $acc
    }
  })

  mut merged = ($tracked_versions | each {|v|
    let name = (try { $v.name } catch { "" })
    if ($name in ($fragment_by_name | columns)) {
      $fragment_by_name | get $name
    } else {
      $v
    }
  })

  mut seen_new = []
  for fv in $fragment_versions {
    let name = (try { $fv.name } catch { "" })
    let is_new = ($name | str length) > 0 and not ($name in $tracked_names) and not ($name in $seen_new)
    if $is_new {
      $merged = ($merged | append $fv)
      $seen_new = ($seen_new | append $name)
    }
  }

  $merged
}

export def resolve-tracked-source-id-universe [tracked_manifest: record] {
  mut ids = []

  let default_sources = (try { $tracked_manifest.defaults.sources } catch { {} })
  $ids = ($ids | append ($default_sources | columns))

  let versions = (try { $tracked_manifest.versions } catch { [] })
  for v in $versions {
    let version_sources = (try { $v.overrides.sources } catch { {} })
    $ids = ($ids | append ($version_sources | columns))
  }

  $ids | uniq | sort
}

export def validate-fragment-versions [
  fragment_versions: list,
  ctx: string
] {
  mut version_idx = 0
  mut valid_names = []
  for version_spec in $fragment_versions {
    if not ("name" in ($version_spec | columns)) {
      error make {
        msg: $"($ctx): Version entry #($version_idx) missing required field: 'name'"
      }
    }
    let version_name = $version_spec.name
    if ($version_name | str length) == 0 {
      error make {
        msg: $"($ctx): Version entry #($version_idx) missing required field: 'name'"
      }
    }
    $valid_names = ($valid_names | append $version_name)
    $version_idx = ($version_idx + 1)
  }

  let dup_names = (find-duplicates $valid_names)
  for dup in $dup_names {
    error make {
      msg: $"($ctx): Duplicate version name: '($dup)' appears multiple times"
    }
  }
}

export def validate-local-version-sources [
  fragment_versions: list,
  allowed_ids: list<string>,
  ctx: string
] {
  for v in $fragment_versions {
    let version_name = (try { $v.name } catch { "" })
    let version_sources = (try { $v.overrides.sources } catch { {} })
    for source_key in ($version_sources | columns) {
      if not ($source_key in $allowed_ids) {
        error make {
          msg: $"($ctx): version '($version_name)': sources.($source_key): Additive source id '($source_key)' is forbidden under --plane local."
        }
      }
      validate-local-plane-source-entry $source_key ($version_sources | get $source_key) $ctx
    }
  }
}

def resolve-repo-root [plane_ctx: record] {
  try {
    $plane_ctx.repo_root
  } catch {
    error make {msg: "Local plane context missing repo_root"}
  }
}

def is-local-plane [plane_ctx: any] {
  if $plane_ctx == null {
    return false
  }
  (try { $plane_ctx.plane } catch { "" }) == $PLANE_LOCAL
}

export def load-effective-versions-manifest [
  service: string,
  plane_ctx: any
] {
  let tracked = (load-versions-manifest $service)

  if not (is-local-plane $plane_ctx) {
    return $tracked
  }

  let repo_root = (resolve-repo-root $plane_ctx)
  let fragment = (load-local-fragment $service $repo_root)
  if $fragment == null {
    return $tracked
  }

  let tracked_versions = (try { $tracked.versions } catch { [] })
  let fragment_versions = (try { $fragment.versions } catch { [] })
  let ctx = $"Service '($service)' local fragment"
  validate-fragment-versions $fragment_versions $ctx
  let merged_versions = (merge-version-universe $tracked_versions $fragment_versions)

  let merged_default = if ("default" in ($fragment | columns)) {
    $fragment.default
  } else {
    $tracked.default
  }

  let allowed_ids = (resolve-tracked-source-id-universe $tracked)
  validate-local-version-sources $fragment_versions $allowed_ids $ctx

  $tracked
  | upsert versions $merged_versions
  | upsert default $merged_default
}

# BUILD path: root nodes use effective manifest under local plane; deps stay tracked.
export def load-build-versions-manifest [
  service: string,
  plane_ctx: any,
  root_scope: bool
] {
  if $root_scope {
    load-effective-versions-manifest $service $plane_ctx
  } else {
    load-versions-manifest $service
  }
}

# Resolve version_spec from a build-order node key (service:version[:platform]).
export def resolve-build-node-version-spec [
  node: string,
  platform: string,
  plane_ctx: any,
  root_scope: bool
] {
  use ../manifest/core.nu [
    apply-version-defaults
    check-versions-manifest-exists
    get-version-or-null
    resolve-version-name
  ]
  use ../platforms/core.nu [
    check-platforms-manifest-exists
    expand-version-to-platforms
    get-default-platform
    load-platforms-manifest
    strip-platform-suffix
  ]

  let parts = ($node | split row ":")
  if ($parts | length) < 2 {
    error make {
      msg: $"Invalid build node format: '($node)'. Expected 'service:version' or 'service:version:platform'"
    }
  }

  let service = ($parts | get 0)
  let version_name = ($parts | get 1)

  if not (check-versions-manifest-exists $service) {
    error make { msg: $"Service '($service)' does not have a version manifest" }
  }

  let versions_manifest = (load-build-versions-manifest $service $plane_ctx $root_scope)

  let has_platforms = (check-platforms-manifest-exists $service)
  let platforms_manifest = (if $has_platforms {
    try { load-platforms-manifest $service } catch { null }
  } else {
    null
  })

  let base_version_name = (if $platforms_manifest != null {
    let stripped = (try {
      strip-platform-suffix $version_name $platforms_manifest
    } catch {
      {base_name: $version_name, platform_name: ""}
    })
    $stripped.base_name
  } else {
    $version_name
  })

  let version_resolved = (resolve-version-name $base_version_name $versions_manifest $platforms_manifest null)
  let version_spec = (get-version-or-null $versions_manifest $version_resolved.base_name)
  if $version_spec == null {
    error make {
      msg: $"Version '($version_resolved.base_name)' not found in manifest for service '($service)'"
    }
  }

  if $has_platforms and ($platform | str length) > 0 {
    let expanded_versions = (
      expand-version-to-platforms $version_spec $platforms_manifest (get-default-platform $platforms_manifest)
    )
    let matching = ($expanded_versions | where {|item| $item.platform == $platform} | first)
    if $matching == null {
      error make {
        msg: $"Platform '($platform)' not found in expanded versions for '($service):($base_version_name)'"
      }
    }
    $matching
  } else {
    apply-version-defaults $versions_manifest $version_spec
  }
}
