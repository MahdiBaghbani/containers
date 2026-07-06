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

# Build system tests

use ../lib.nu [print-test-summary]

use ./cache-busting.nu [cache-busting-tests]
use ./build-order.nu [build-order-tests]
use ./automatic-deps.nu [automatic-deps-tests]
use ./continue-on-failure.nu [continue-on-failure-tests]
use ./docker-sentinel.nu [docker-sentinel-tests]
use ./synthetic-deps.nu [synthetic-deps-tests]
use ./disk-parsing.nu [disk-parsing-tests]
use ./clone-source-staging.nu [clone-source-staging-tests]
use ./dockerfile-contracts/mod.nu [clone-source-ref-kind-tests]
use ./clone-source-modes.nu [clone-source-modes-tests]
use ./clone-source-cache.nu [clone-source-cache-tests]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []

  $results = ($results | append (cache-busting-tests $verbose_flag))
  $results = ($results | append (build-order-tests $verbose_flag))
  $results = ($results | append (automatic-deps-tests $verbose_flag))
  $results = ($results | append (continue-on-failure-tests $verbose_flag))
  $results = ($results | append (docker-sentinel-tests $verbose_flag))
  $results = ($results | append (synthetic-deps-tests $verbose_flag))
  $results = ($results | append (disk-parsing-tests $verbose_flag))
  $results = ($results | append (clone-source-staging-tests $verbose_flag))
  $results = ($results | append (clone-source-ref-kind-tests $verbose_flag))
  $results = ($results | append (clone-source-modes-tests $verbose_flag))
  $results = ($results | append (clone-source-cache-tests $verbose_flag))

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  } else {
    exit 0
  }
}
