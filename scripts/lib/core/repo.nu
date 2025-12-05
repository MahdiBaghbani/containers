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

# Repository root detection utilities
# Part of scripts/lib/core/ - cross-cutting helpers with no domain knowledge
#
# Merged from common.nu and tls/lib.nu implementations:
# - common.nu: git-based detection
# - tls/lib.nu: FILE_PWD path traversal fallback

# Get repository root - tries git first, falls back to path traversal
export def get-repo-root [] {
  # Try git-based detection first (most accurate)
  let git_result = (try {
    ^git rev-parse --show-toplevel | str trim
  } catch {
    null
  })
  
  if $git_result != null and ($git_result | str length) > 0 {
    return ($git_result | path expand)
  }
  
  # Fallback: use FILE_PWD with path traversal (for non-git contexts)
  let script_dir = (try { 
    $env.FILE_PWD
  } catch { 
    $env.PWD
  })
  
  if ($script_dir | str contains "scripts") {
    return (($script_dir | path join ".." "..") | path expand)
  }
  
  # Final fallback: current working directory
  ($env.PWD | path expand)
}

# Ensure we're running from repository root
export def ensure-repo-root [] {
  if not (("services" | path exists) and ("scripts" | path exists)) {
    error make {msg: "This script must be run from the repository root"}
  }
}
