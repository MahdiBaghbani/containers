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

# Validation domain test suite
# Contract tests for validator and schema correctness: source validation,
# SSH/TLS placement, local-path boundaries, and the latest-version rule.

use ./lib.nu [print-test-summary]
use ./validate/local-path.nu [local-path-tests]
use ./validate/latest-version.nu [latest-version-tests]
use ./validate/defaults-placement.nu [defaults-placement-tests]
use ./validate/ssh-wiring.nu [ssh-wiring-base-tests ssh-wiring-override-tests]
use ./validate/sources.nu [sources-tests]
use ./validate/overrides-guards.nu [overrides-guards-tests]
use ./validate/tls-merged-dep.nu [tls-merged-dep-tests]
use ./validate/manifest-warnings.nu [manifest-warnings-tests]
use ./validate/service-complete-smoke.nu [service-complete-smoke-tests]
use ./validate/service-complete-merge.nu [service-complete-merge-tests]
use ./validate/clone-compat.nu [clone-compat-tests]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })

  let results = (
    (local-path-tests $verbose_flag)
    | append (latest-version-tests $verbose_flag)
    | append (defaults-placement-tests $verbose_flag)
    | append (ssh-wiring-base-tests $verbose_flag)
    | append (sources-tests $verbose_flag)
    | append (ssh-wiring-override-tests $verbose_flag)
    | append (overrides-guards-tests $verbose_flag)
    | append (tls-merged-dep-tests $verbose_flag)
    | append (manifest-warnings-tests $verbose_flag)
    | append (service-complete-smoke-tests $verbose_flag)
    | append (service-complete-merge-tests $verbose_flag)
    | append (clone-compat-tests $verbose_flag)
  )

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
