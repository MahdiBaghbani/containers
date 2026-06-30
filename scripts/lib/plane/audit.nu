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

# Local-plane whole-root topology audit (phase 1)
# Fail closed: optional services/, tracked mirrors only, versions.nuon only

use ./presence.nu [
  local-root-path
  local-services-path
  LOCAL_ROOT_DIR
  LOCAL_SERVICES_DIR
]
use ../core/repo.nu [get-repo-root]

export const LOCAL_MIRROR_FILE = "versions.nuon"

def tracked-service-names-for-mirrors [
  mirror_names: list<string>
  repo_root?: string
] {
  let base = if ($repo_root | is-empty) {
    get-repo-root
  } else {
    $repo_root | path expand
  }

  mut names = []
  for mirror_name in $mirror_names {
    let file = ($base | path join $"services/($mirror_name).nuon")
    if not ($file | path exists) {
      continue
    }
    try {
      let manifest = (open $file)
      if ($manifest.name? | is-empty) {
        error make {
          msg: $"Tracked service manifest missing 'name': ($file)"
        }
      }
      if $manifest.name != $mirror_name {
        error make {
          msg: $"Tracked service manifest name mismatch: ($file) declares name '($manifest.name)'; local mirror directory basename must match manifest filename"
        }
      }
      $names = ($names | append $mirror_name)
    } catch {|err|
      if ($err.msg | str starts-with "Tracked service manifest") {
        error make {msg: $err.msg}
      }
      error make {
        msg: $"Unable to read tracked service manifest: ($file) ($err.msg)"
      }
    }
  }
  $names | sort
}

def list-entries [dir: string] {
  if not ($dir | path exists) {
    return []
  }
  try {
    ls -a $dir
  } catch {
    error make {
      msg: $"Unable to read local topology directory: ($dir)"
    }
  }
}

export def require-services-directory [services_path: string] {
  let services_type = (try { ($services_path | path type) } catch { "unknown" })
  if $services_type != "dir" {
    error make {
      msg: $"Local path must be a directory: ($services_path)"
    }
  }
}

def audit-mirror-entries [mirror_name: string, mirror_path: string] {
  let entries = (list-entries $mirror_path)
  mut has_versions_file = false

  for item in $entries {
    let item_name = ($item.name | path basename)
    if $item.type == "dir" {
      error make {
        msg: $"Unsupported directory in local service mirror '($mirror_name)': ($item_name). Only '($LOCAL_MIRROR_FILE)' is allowed"
      }
    } else if $item.type != "file" {
      error make {
        msg: $"Unsupported item in local service mirror '($mirror_name)': ($item_name). Only file '($LOCAL_MIRROR_FILE)' is allowed"
      }
    } else if $item_name != $LOCAL_MIRROR_FILE {
      error make {
        msg: $"Unsupported file in local service mirror '($mirror_name)': ($item_name). Only '($LOCAL_MIRROR_FILE)' is allowed"
      }
    } else {
      $has_versions_file = true
    }
  }

  if not $has_versions_file {
    error make {
      msg: $"Incomplete local service mirror '($mirror_name)'. Mirror must contain '($LOCAL_MIRROR_FILE)'"
    }
  }
}

def audit-root-entries [
  entries: list
  allowed_mirrors: list
  services_path: string
] {
  for entry in $entries {
    let name = ($entry.name | path basename)
    if $name == $LOCAL_SERVICES_DIR {
      continue
    } else if $entry.type == "file" {
      error make {
        msg: $"Unsupported local root file: ($name). Only optional '($LOCAL_SERVICES_DIR)/' is allowed under ($LOCAL_ROOT_DIR)/"
      }
    } else if $entry.type == "dir" {
      error make {
        msg: $"Unsupported local root directory: ($name). Only '($LOCAL_SERVICES_DIR)/' is allowed under ($LOCAL_ROOT_DIR)/"
      }
    } else {
      error make {
        msg: $"Unsupported local root item: ($name). Only optional '($LOCAL_SERVICES_DIR)/' is allowed under ($LOCAL_ROOT_DIR)/"
      }
    }
  }

  if not ($services_path | path exists) {
    return
  }

  require-services-directory $services_path

  for mirror in (list-entries $services_path) {
    let mirror_name = ($mirror.name | path basename)
    if $mirror.type != "dir" {
      error make {
        msg: $"Unsupported local service mirror: ($mirror_name). Mirror entries must be directories for tracked services"
      }
    }
    if not ($mirror_name in $allowed_mirrors) {
      error make {
        msg: $"Unknown local service mirror: ($mirror_name). Mirror names must match tracked services"
      }
    }

    audit-mirror-entries $mirror_name $mirror.name
  }
}

# Fail closed on any unsupported `.dockypody.local/` topology
export def audit-local-root-topology [repo_root?: string] {
  let root = (local-root-path $repo_root)
  let services_path = (local-services-path $repo_root)
  let local_mirror_dirs = (if ($services_path | path exists) {
    let services_type = (try { ($services_path | path type) } catch { "unknown" })
    if $services_type == "dir" {
      list-entries $services_path | where type == "dir"
    } else {
      []
    }
  } else {
    []
  })
  let mirror_names = ($local_mirror_dirs
    | each {|entry| $entry.name | path basename}
  )
  let allowed_mirrors = (if ($mirror_names | is-not-empty) {
    tracked-service-names-for-mirrors $mirror_names $repo_root
  } else {
    []
  })

  audit-root-entries (list-entries $root) $allowed_mirrors $services_path

  let mirrors = ($mirror_names | sort)

  {
    local_root: $root
    services_path: (if ($services_path | path exists) { $services_path } else { null })
    mirrors: $mirrors
  }
}
