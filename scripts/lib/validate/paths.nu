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
# Checks path exists, is directory, and is within an allowed root.
# Allowed roots: repo_root itself, or the parent repos/ directory when the
# repo lives directly inside a directory named "repos" (workspace clones).
export def validate-local-path [path: string, repo_root: string] {
    mut errors = []

    let repo_root_expanded = ($repo_root | path expand)
    # Allow sibling workspace clones when the repo lives inside a "repos/" dir
    let parent_dir = ($repo_root_expanded | path dirname)
    let parent_root = (if ($parent_dir | path basename) == "repos" {
        $parent_dir
    } else {
        null
    })

    # Boundary-safe containment: avoids /foo/bar falsely matching /foo/baz
    let in_boundary = {|candidate, root|
        $candidate == $root or ($candidate | str starts-with ($root + "/"))
    }

    # Resolve path: absolute paths are expanded in place; relative paths are
    # resolved from repo_root (supports ../sibling-repo style references)
    let resolved_path = (if ($path | str starts-with "/") {
        ($path | path expand)
    } else {
        ($repo_root_expanded | path join $path | path expand)
    })

    let in_repo = (do $in_boundary $resolved_path $repo_root_expanded)
    let in_parent = (if $parent_root != null {
        do $in_boundary $resolved_path $parent_root
    } else {
        false
    })

    if not ($in_repo or $in_parent) {
        $errors = ($errors | append $"Path '($path)' is outside repository root '($repo_root)'")
        return {valid: false, errors: $errors}
    }

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
        $errors = ($errors | append $"Path '($path)' is not a directory \(type: ($path_type)\)")
        return {valid: false, errors: $errors}
    }

    {valid: true, errors: []}
}
