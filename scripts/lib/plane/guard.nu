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

# Shared local-plane policy guard (phase 1 entry surface)
# T1: root presence; T2: whole-root topology audit

use ./presence.nu [local-root-path local-root-present]
use ./audit.nu [audit-local-root-topology]
use ../core/repo.nu [get-repo-root]

export const PLANE_TRACKED = "tracked"
export const PLANE_LOCAL = "local"

# Normalize and validate `--plane` values
export def parse-plane [plane: string] {
  let normalized = ($plane | str trim | str downcase)
  if $normalized == "" or $normalized == $PLANE_TRACKED {
    $PLANE_TRACKED
  } else if $normalized == $PLANE_LOCAL {
    $PLANE_LOCAL
  } else {
    error make {
      msg: $"Invalid --plane value: '($plane)'. Use 'tracked' or 'local'."
    }
  }
}

# Hard error when `--plane local` is active but the root directory is missing
export def require-local-root-presence [repo_root?: string] {
  if not (local-root-present $repo_root) {
    let expected = (local-root-path $repo_root)
    error make {
      msg: $"--plane local requires local root directory: ($expected)"
    }
  }
}

# T1+T2 guard: root presence and whole-root topology audit
export def guard-local-plane-presence [repo_root?: string] {
  require-local-root-presence $repo_root
  audit-local-root-topology $repo_root | merge {
    plane: $PLANE_LOCAL
  }
}

# Route guard by plane; tracked plane is a no-op
export def guard-plane [plane: string, repo_root?: string] {
  let resolved = (parse-plane $plane)
  if $resolved == $PLANE_LOCAL {
    guard-local-plane-presence $repo_root
  } else {
    {
      plane: $PLANE_TRACKED
      repo_root: (if ($repo_root | is-empty) { get-repo-root } else { $repo_root | path expand })
    }
  }
}
