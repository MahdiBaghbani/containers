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

# Shared validation helpers

use ../core/repo.nu [get-repo-root]
use ./paths.nu [validate-local-path]

export def validate-source-entries [
  sources: any,
  context: string,
  require_complete: bool
] {
  mut errors = []

  if not (($sources | describe) | str starts-with "record") {
    return {valid: false, errors: [$"($context): sources: Must be a record."]}
  }

  let repo_root = (get-repo-root)

  for source_key in ($sources | columns) {
    let source = ($sources | get $source_key)

    if not ($source_key =~ '^[a-z0-9_]+$') {
      $errors = ($errors | append $"($context): sources.($source_key): key must be lowercase alphanumeric with underscores only \(pattern: ^[a-z0-9_]+$\)")
    }

    let source_type = ($source | describe)
    if not ($source_type | str starts-with "record") {
      $errors = ($errors | append $"($context): sources.($source_key): Must be a record.")
      continue
    }

    let has_path = ("path" in ($source | columns))
    let has_url = ("url" in ($source | columns))
    let has_ref = ("ref" in ($source | columns))

    if "build_arg" in ($source | columns) {
      $errors = ($errors | append $"($context): sources.($source_key): 'build_arg' field is forbidden. Build args are auto-generated as <KEY>_REF and <KEY>_URL.")
    }

    # Mutual exclusivity: cannot have both path and url/ref
    if $has_path and ($has_url or $has_ref) {
      $errors = ($errors | append $"($context): sources.($source_key): Cannot have both 'path' and 'url'/'ref' fields. They are mutually exclusive.")
      continue
    }

    if $has_path {
      let path_value = (try { $source.path } catch { "" })
      if ($path_value | str length) == 0 {
        $errors = ($errors | append $"($context): sources.($source_key): 'path' field is empty")
      } else {
        let path_validation = (validate-local-path $path_value $repo_root)
        if not $path_validation.valid {
          let formatted_errors = ($path_validation.errors | each {|err| $"($context): sources.($source_key): ($err)"})
          $errors = ($errors | append $formatted_errors)
        }
      }
    } else if $require_complete {
      if not $has_url {
        $errors = ($errors | append $"($context): sources.($source_key): Missing required field 'url'.")
      }
      if not $has_ref {
        $errors = ($errors | append $"($context): sources.($source_key): Missing required field 'ref'.")
      }
    }
  }

  {valid: ($errors | is-empty), errors: $errors}
}