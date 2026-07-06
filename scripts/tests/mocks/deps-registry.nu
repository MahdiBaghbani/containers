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

# Test state registry using temporary files (avoids Nushell env var persistence issues)

export const TEST_STATE_FILE = ".tmp/test-state-registry.json"

export def register-mock-service-dependencies [service: string, version: string, dependencies: record] {
  init-mock-service-deps-registry
  let node_key = $"($service):($version)"
  let current = (try {
    open $TEST_STATE_FILE
  } catch {
    {}  # Return empty registry if file doesn't exist
  })
  let updated = ($current | upsert $node_key $dependencies)
  $updated | to json | save -f $TEST_STATE_FILE
}

export def clear-mock-service-deps-registry [] {
  {} | to json | save -f $TEST_STATE_FILE
}

export def init-mock-service-deps-registry [] {
  if not ($TEST_STATE_FILE | path exists) {
    mkdir .tmp
    {} | to json | save -f $TEST_STATE_FILE
  }
}

export def get-registered-dependencies [service: string, version: string] {
  init-mock-service-deps-registry
  let node_key = $"($service):($version)"
  let registry = (open $TEST_STATE_FILE)
  if $node_key in ($registry | columns) {
    $registry | get $node_key
  } else {
    {}
  }
}
