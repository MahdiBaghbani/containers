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

# Path and local source validation functions

# Validate local source path (for local folder sources feature)
# Checks path exists, is directory, and is within repo root (prevents path traversal)
export def validate-local-path [path: string, repo_root: string] {
    mut errors = []
    
    # Resolve path relative to repo root
    let resolved_path = (if ($path | path expand | str starts-with "/") {
        # Absolute path - validate it's within repo root
        let abs_path = ($path | path expand)
        let repo_root_expanded = ($repo_root | path expand)
        if not ($abs_path | str starts-with $repo_root_expanded) {
            $errors = ($errors | append $"Path '($path)' is outside repository root '($repo_root)'")
            return {valid: false, errors: $errors}
        }
        $abs_path
    } else {
        # Relative path - resolve relative to repo root
        ($repo_root | path join $path | path expand)
    })
    
    # Check path exists
    if not ($resolved_path | path exists) {
        $errors = ($errors | append $"Path '($path)' does not exist")
        return {valid: false, errors: $errors}
    }
    
    # Check is directory
    let path_type = (try {
        ($resolved_path | path type)
    } catch {
        "unknown"
    })
    
    if $path_type != "dir" {
        $errors = ($errors | append $"Path '($path)' is not a directory (type: ($path_type))")
        return {valid: false, errors: $errors}
    }
    
    # Validate path traversal prevention (reject .. outside repo root)
    # resolved_path is already expanded, just normalize repo_root for comparison
    let normalized_repo = ($repo_root | path expand)
    if not ($resolved_path | str starts-with $normalized_repo) {
        let error_msg = $"Path '($path)' resolves outside repository root - path traversal detected"
        $errors = ($errors | append $error_msg)
        return {valid: false, errors: $errors}
    }
    
    {
        valid: true,
        errors: []
    }
}
