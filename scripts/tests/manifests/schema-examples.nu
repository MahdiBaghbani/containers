#!/usr/bin/env nu

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

# Schema-example validation.

use ../../lib/validate/core.nu [
  validate-version-manifest validate-platforms-manifest
]
use ../lib.nu [run-test]

export def test-schema-examples-validate-against-live-validators [verbose: bool] {
  run-test "Schema examples validate against live validators" {
    let example_paths = (glob schemas/examples/*.nuon)
    if ($example_paths | is-empty) {
      error make {msg: "No schema example files found under schemas/examples/"}
    }

    mut invalid_examples = []
    mut unhandled_examples = []

    for example_path in $example_paths {
      let example_name = ($example_path | path basename)
      let example_text = (open --raw $example_path)
      let parse_result = (try {
        let parsed = ($example_text
          | lines
          | where {|line| not ($line =~ '^\s*//')}
          | str join "\n"
          | from nuon)
        {
          ok: true,
          value: $parsed,
          errors: []
        }
      } catch {|err|
        {
          ok: false,
          value: null,
          errors: [$"Failed to parse as NUON: ($err.msg)"]
        }
      })

      if not $parse_result.ok {
        $invalid_examples = ($invalid_examples | append {
          file: $example_name,
          errors: $parse_result.errors
        })
        continue
      }

      let example = $parse_result.value

      if (($example_name | str ends-with "-platforms.nuon")) {
        let result = (validate-platforms-manifest $example)
        if not $result.valid {
          $invalid_examples = ($invalid_examples | append {
            file: $example_name,
            errors: $result.errors
          })
        }
      } else if ("versions" in ($example | columns)) {
        let base_key = (if ($example_name | str ends-with "-versions.nuon") {
          $example_name | str replace --regex '-versions\.nuon$' ''
        } else {
          $example_name | str replace --regex '\.nuon$' ''
        })
        let companion_platform_path = ($example_paths | where {|p|
          ($p | path basename) == $"($base_key)-platforms.nuon"
        } | first)
        let companion_platforms = (if $companion_platform_path == null {
          null
        } else {
          let companion_text = (open --raw $companion_platform_path)
          let companion_parse = (try {
            let parsed = ($companion_text
              | lines
              | where {|line| not ($line =~ '^\s*//')}
              | str join "\n"
              | from nuon)
            {
              ok: true,
              value: $parsed,
              errors: []
            }
          } catch {|err|
            {
              ok: false,
              value: null,
              errors: [$"Failed to parse companion platforms example as NUON: ($err.msg)"]
            }
          })

          if not $companion_parse.ok {
            $invalid_examples = ($invalid_examples | append {
              file: ($companion_platform_path | path basename),
              errors: $companion_parse.errors
            })
            null
          } else {
            $companion_parse.value
          }
        })
        let result = (validate-version-manifest $example $companion_platforms)
        if not $result.valid {
          $invalid_examples = ($invalid_examples | append {
            file: $example_name,
            errors: $result.errors
          })
        }
      } else {
        $unhandled_examples = ($unhandled_examples | append $example_name)
      }
    }

    if not ($unhandled_examples | is-empty) {
      let names = ($unhandled_examples | str join ", ")
      error make {msg: $"No validator mapping for schema example(s): ($names)"}
    }

    if not ($invalid_examples | is-empty) {
      let details = ($invalid_examples | each {|item|
        let errs = ($item.errors | each {|e| $"    - ($e)"} | str join "\n")
        $"  - ($item.file)\n($errs)"
      } | str join "\n")
      error make {msg: $"Schema examples failed live validation:\n($details)"}
    }

    true
  } $verbose
}
