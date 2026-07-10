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

# Parse-check service hook scripts before image boot.

use ../lib.nu [run-test]

const HOOK_GLOB = "services/nextcloud-webapp/scripts/hooks/**/*.nu"

def acceptable-ide-error [message: string] {
  $message == "Module not found."
}

def ide-check-hook-errors [file: string] {
  (^nu --ide-check 50 $file
    | lines
    | each {|line| try { $line | from json } catch { null } }
    | where $it != null
    | where {|rec| ($rec.type? | default "") == "diagnostic" }
    | where {|rec| ($rec.severity? | default "") == "Error" }
    | where {|rec| not (acceptable-ide-error ($rec.message? | default "")) }
  )
}

def parse-check-hook [file: string] {
  let errors = (ide-check-hook-errors $file)
  if not ($errors | is-empty) {
    let details = ($errors | each {|e| $e.message } | str join "; ")
    error make {msg: $"($file): ($details)"}
  }
  true
}

export def hook-parse-tests [verbose: bool] {
  let hooks = (glob $HOOK_GLOB | sort)
  if ($hooks | is-empty) {
    error make {msg: $"No hook files matched ($HOOK_GLOB)"}
  }

  $hooks
  | each {|hook|
    run-test $"Hook parse check: ($hook)" {
      parse-check-hook $hook
    } $verbose
  }
}
