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

use ../mocks.nu [clear-mock-platform-registry clear-mock-service-deps-registry]

export def cleanup-test-environment [] {
  clear-mock-platform-registry
  clear-mock-service-deps-registry

  try {
    rm -f .tmp/test-state-registry.json
    mkdir .tmp
    {} | to json | save -f .tmp/test-state-registry.json
  } catch {
    if (".tmp/test-state-registry.json" | path exists) {
      {} | to json | save -f .tmp/test-state-registry.json
    }
  }

  true
}

export def with-test-cleanup [test_block: closure] {
  let result = (try {
    do $test_block
  } catch {|err|
    cleanup-test-environment | ignore
    error make {msg: $err.msg}
  })

  cleanup-test-environment | ignore

  $result
}
