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

# Effective-config inspect surface (guard-owned model + semantic metadata)

use ../build/config.nu [load-service-config]
use ../build/meta.nu [detect-build]
use ../build/tags.nu [generate-tags]
use ../registries/info.nu [get-registry-info]
use ../manifest/core.nu [
  check-versions-manifest-exists load-versions-manifest
  get-default-version get-version-spec apply-version-defaults
]
use ../platforms/core.nu [
  check-platforms-manifest-exists load-platforms-manifest get-default-platform
]
use ../plane/guard.nu [PLANE_LOCAL PLANE_TRACKED]
use ../plane/presence.nu [local-root-path local-services-path]
use ../plane/effective-config.nu [load-local-fragment]
use ../plane/versions.nu [load-effective-versions-manifest]

export def resolve-inspect-version-spec [
  service: string,
  version: string,
  plane_ctx: any = null
] {
  if not (check-versions-manifest-exists $service) {
    error make {
      msg: $"Service '($service)' has no versions manifest; omit --version only when the service has no versions"
    }
  }

  let plane = (if $plane_ctx != null {
    try { $plane_ctx.plane } catch { $PLANE_TRACKED }
  } else {
    $PLANE_TRACKED
  })
  let manifest = (if $plane == $PLANE_LOCAL {
    load-effective-versions-manifest $service $plane_ctx
  } else {
    load-versions-manifest $service
  })
  let version_name = (if ($version | str length) > 0 {
    $version
  } else {
    get-default-version $manifest
  })
  let version_spec = (get-version-spec $manifest $version_name)
  apply-version-defaults $manifest $version_spec
}

def resolve-repo-root [plane_ctx: record] {
  try {
    $plane_ctx.repo_root
  } catch {
    error make {msg: "Plane context missing repo_root"}
  }
}

def fragment-source-keys [fragment: any, version_name: string] {
  if $fragment == null {
    return []
  }
  mut keys = (try { $fragment.overrides.sources } catch { {} } | columns)
  if ($version_name | str length) > 0 and ("versions" in ($fragment | columns)) {
    let versions = (try { $fragment.versions } catch { [] })
    let version_match = ($versions | where {|v| (try { $v.name } catch { "" }) == $version_name } | first)
    if $version_match != null {
      let version_sources = (try { $version_match.overrides.sources } catch { {} })
      for source_key in ($version_sources | columns) {
        if not ($source_key in $keys) {
          $keys = ($keys | append $source_key)
        }
      }
    }
  }
  $keys
}

def classify-effective-source [source: record] {
  let has_path = ("path" in ($source | columns))
  if $has_path {
    "tracked-local"
  } else {
    "tracked-git"
  }
}

def collect-env-keys-used [
  sources: record,
  repo_root: string
] {
  mut used = []
  for source_key in ($sources | columns) {
    let env_key = $"($source_key | str upcase)_PATH"
    let env_path = (try { ($env | get -o $env_key) } catch { null })
    if ($env_path != null) and ($env_path | str length) > 0 {
      let effective_path = (try { ($sources | get $source_key).path } catch { "" })
      if ($effective_path | str length) > 0 {
        let expanded_env = (try { $env_path | path expand } catch { $env_path })
        let expanded_effective = (try { $effective_path | path expand } catch { $effective_path })
        if $expanded_env == $expanded_effective {
          $used = ($used | append $env_key)
        }
      }
    }
  }
  $used
}

def build-source-origin [
  sources: record,
  env_keys_used: list<string>,
  fragment_keys: list<string>
] {
  ($sources | columns | reduce --fold {} {|source_key, acc|
    let source = ($sources | get $source_key)
    let env_key = $"($source_key | str upcase)_PATH"
    let origin = (if ($env_key in $env_keys_used) {
      "env-only"
    } else if ($source_key in $fragment_keys) {
      if ("path" in ($source | columns)) { "fragment-local" } else { "fragment-git" }
    } else {
      classify-effective-source $source
    })
    $acc | upsert $source_key $origin
  })
}

def has-fragment-source-overrides [fragment: any, version_name: string] {
  if $fragment == null {
    return false
  }
  let top_sources = (try { $fragment.overrides.sources } catch { {} })
  if not ($top_sources | is-empty) {
    return true
  }
  if ($version_name | str length) > 0 and ("versions" in ($fragment | columns)) {
    let versions = (try { $fragment.versions } catch { [] })
    let version_match = ($versions | where {|v| (try { $v.name } catch { "" }) == $version_name } | first)
    if $version_match != null {
      let version_sources = (try { $version_match.overrides.sources } catch { {} })
      if not ($version_sources | is-empty) {
        return true
      }
    }
  }
  false
}

def classify-version-origin [
  plane: string,
  version_name: string,
  fragment: any,
  tracked_manifest: record
] {
  if $plane != $PLANE_LOCAL or $fragment == null {
    return "tracked"
  }
  let tracked_names = (
    try { $tracked_manifest.versions } catch { [] }
    | each {|v| (try { $v.name } catch { "" })}
  )
  let fragment_names = (
    try { $fragment.versions } catch { [] }
    | each {|v| (try { $v.name } catch { "" })}
  )
  if not ($version_name in $fragment_names) {
    return "tracked"
  }
  if $version_name in $tracked_names {
    "local-replace"
  } else {
    "local-only"
  }
}

def build-precedence-summary [
  plane: string,
  env_keys_used: list<string>,
  version_origin: string,
  has_fragment_source_overrides: bool
] {
  if $plane != $PLANE_LOCAL {
    return "tracked manifest only"
  }
  mut parts = (if $version_origin == "local-only" {
    ["local-only version"]
  } else {
    mut base = ["tracked manifest"]
    if $version_origin == "local-replace" {
      $base = ($base | append "local version (replace)")
    }
    $base
  })
  if $has_fragment_source_overrides {
    $parts = ($parts | append "local fragment overrides")
  }
  if ($env_keys_used | length) > 0 {
    $parts = ($parts | append "env PATH materialization")
  }
  $parts | str join " <- "
}

def build-single-primary-tag-state [
  plane: string,
  service: string,
  version_spec: record,
  platform: string,
  default_platform: string
] {
  if $plane != $PLANE_LOCAL {
    return {
      active: false
      policy: "standard"
    }
  }

  let is_local = (detect-build).is_local
  let registry_info = (get-registry-info)
  let current_platform = (try { $version_spec.platform } catch { $platform })
  let primary_tags = (generate-tags $service $version_spec $is_local $registry_info $current_platform $default_platform true)
  {
    active: true
    policy: "single-primary-non-publish"
    primary_tag: ($primary_tags | first)
    suppressed: [
      "manifest-latest"
      "cli-latest"
      "extra-tag"
      "publish"
      "dependency-tag-fanout"
      "dependency-push-fanout"
    ]
  }
}

def build-inspect-semantic-record [
  service: string,
  version_spec: record,
  plane_ctx: record,
  effective_cfg: record,
  platform: string = ""
] {
  let plane = (try { $plane_ctx.plane } catch { $PLANE_TRACKED })
  let version_name = $version_spec.name
  let repo_root = (resolve-repo-root $plane_ctx)
  let local_root = (if $plane == $PLANE_LOCAL { local-root-path $repo_root } else { "" })

  let fragment = (if $plane == $PLANE_LOCAL {
    load-local-fragment $service $repo_root
  } else {
    null
  })
  let local_fragment_present = $fragment != null
  let tracked_manifest = (if $plane == $PLANE_LOCAL {
    load-versions-manifest $service
  } else {
    {}
  })
  let version_origin = (classify-version-origin $plane $version_name $fragment $tracked_manifest)
  let has_fragment_source_overrides = (has-fragment-source-overrides $fragment $version_name)
  let fragment_keys = (if $fragment == null { [] } else { fragment-source-keys $fragment $version_name })

  let local_mirror_path = (if $plane == $PLANE_LOCAL {
    let mirror = (local-services-path $repo_root | path join $service)
    if ($mirror | path exists) { $mirror } else { "" }
  } else {
    ""
  })

  let sources = (try { $effective_cfg.sources } catch { {} })
  let env_keys_used = (if $plane == $PLANE_LOCAL {
    collect-env-keys-used $sources $repo_root
  } else {
    []
  })
  let env_only = ($env_keys_used | length) > 0

  let has_platform_arg = ($platform | str length) > 0
  let default_platform = (if $has_platform_arg and (check-platforms-manifest-exists $service) {
    try { get-default-platform (load-platforms-manifest $service) } catch { "" }
  } else {
    ""
  })

  {
    plane: $plane
    service: $service
    version: $version_name
    tracked_service: $service
    tracked_version: $version_name
    local_root: $local_root
    local_fragment_present: $local_fragment_present
    local_mirror_path: $local_mirror_path
    env_only: $env_only
    env_keys_used: $env_keys_used
    source_origin: (build-source-origin $sources $env_keys_used $fragment_keys)
    precedence_summary: (build-precedence-summary $plane $env_keys_used $version_origin $has_fragment_source_overrides)
    single_primary_tag_state: (build-single-primary-tag-state $plane $service $version_spec $platform $default_platform)
  }
}

# Load guard-owned effective merged config and semantic inspect metadata.
export def inspect-effective-config [
  service: string,
  plane_ctx: record,
  version: string = "",
  platform: string = ""
] {
  let version_spec = (resolve-inspect-version-spec $service $version $plane_ctx)
  let has_platforms = (check-platforms-manifest-exists $service)
  let platforms_manifest = (if $has_platforms { load-platforms-manifest $service } else { null })

  let effective_cfg = (load-service-config $service $version_spec $platform $platforms_manifest $plane_ctx)
  let semantic = (build-inspect-semantic-record $service $version_spec $plane_ctx $effective_cfg $platform)

  $semantic | merge $effective_cfg
}
