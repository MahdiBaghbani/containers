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

# Local-plane root presence helpers
# Phase 1: only `.dockypody.local/` is the off-git root

use ../core/repo.nu [get-repo-root]

export const LOCAL_ROOT_DIR = ".dockypody.local"
export const LOCAL_SERVICES_DIR = "services"

# Absolute path to the local-plane root under a repo root
export def local-root-path [repo_root?: string] {
  let base = if ($repo_root | is-empty) {
    get-repo-root
  } else {
    $repo_root | path expand
  }
  $base | path join $LOCAL_ROOT_DIR
}

# Absolute path to `.dockypody.local/services/`
export def local-services-path [repo_root?: string] {
  local-root-path $repo_root | path join $LOCAL_SERVICES_DIR
}

# True when the local-plane root exists and is a directory
export def local-root-present [repo_root?: string] {
  let root = (local-root-path $repo_root)
  if not ($root | path exists) {
    return false
  }
  (try { ($root | path type) == "dir" } catch { false })
}
