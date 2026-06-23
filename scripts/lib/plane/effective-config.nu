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

# Local-plane effective source materialization (guard-owned)
# Applies env-only {SOURCE_KEY}_PATH overrides to merged tracked sources.

use ./presence.nu [local-services-path]
use ./audit.nu [LOCAL_MIRROR_FILE]
use ../validate/paths.nu [validate-local-path]

const PLANE_LOCAL = "local"

export def local-fragment-path [service: string, repo_root: string] {
  (local-services-path $repo_root)
  | path join $service
  | path join $LOCAL_MIRROR_FILE
}

export def load-local-fragment [service: string, repo_root: string] {
  let path = (local-fragment-path $service $repo_root)
  if not ($path | path exists) {
    return null
  }
  try {
    open $path
  } catch {
    error make {
      msg: $"Failed to parse local fragment: ($path)"
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

# Validate one local-plane source entry: full local, full git, or fail on partial/mixed.
export def validate-local-plane-source-entry [
  source_key: string,
  source: record,
  context: string
] {
  let has_path = ("path" in ($source | columns))
  let has_url = ("url" in ($source | columns))
  let has_ref = ("ref" in ($source | columns))

  if $has_path and ($has_url or $has_ref) {
    error make {
      msg: $"($context): sources.($source_key): Cannot have both 'path' and 'url'/'ref' under --plane local."
    }
  }

  if $has_path {
    let path_value = (try { $source.path } catch { "" })
    if ($path_value | str length) == 0 {
      error make {
        msg: $"($context): sources.($source_key): 'path' field is empty under --plane local."
      }
    }
    return
  }

  if $has_url xor $has_ref {
    error make {
      msg: $"($context): sources.($source_key): Partial git source is forbidden under --plane local. Provide both 'url' and 'ref', or use 'path'."
    }
  }

  if $has_url and $has_ref {
    return
  }

  error make {
    msg: $"($context): sources.($source_key): Source entry must be a full local 'path' replacement or a complete git source under --plane local."
  }
}

export def materialize-env-only-sources [
  sources: record,
  service: string,
  repo_root: string
] {
  mut effective = $sources

  for source_key in ($sources | columns) {
    let env_key = $"($source_key | str upcase)_PATH"
    let env_path = (try { ($env | get -o $env_key) } catch { null })
    if ($env_path != null) and ($env_path | str length) > 0 {
      let path_validation = (validate-local-path $env_path $repo_root)
      if not $path_validation.valid {
        error make {
          msg: ($"Service '($service)': Environment variable '($env_key)' contains invalid path: "
            + ($path_validation.errors | str join "; "))
        }
      }
      $effective = ($effective | upsert $source_key { path: $env_path })
    }
  }

  $effective
}

# Apply env-only {SOURCE_KEY}_PATH materialization to merged tracked sources.
export def apply-local-plane-effective-sources [
  merged_cfg: record,
  service: string,
  version_spec: record,
  plane_ctx: record
] {
  if (try { $plane_ctx.plane } catch { "" }) != $PLANE_LOCAL {
    return $merged_cfg
  }

  let repo_root = (resolve-repo-root $plane_ctx)
  let tracked_sources = (try { $merged_cfg.sources } catch { {} })

  if ($tracked_sources | is-empty) {
    return $merged_cfg
  }

  let effective_sources = (materialize-env-only-sources $tracked_sources $service $repo_root)

  if "sources" in ($merged_cfg | columns) {
    $merged_cfg | upsert sources $effective_sources
  } else {
    $merged_cfg | insert sources $effective_sources
  }
}
