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

# GHCR purge offline unit tests.
# Tests desired-tag computation and version decision logic with no gh api calls.

use ./lib.nu [print-test-summary]
use ./ghcr-purge/decide.nu [
    test-decide-untagged-is-candidate test-decide-desired-tag-kept test-decide-no-desired-tags
    test-decide-partial-intersection test-decide-empty-versions test-decide-all-stale
    test-decide-empty-desired-set test-decide-ts-from-updated-at test-decide-ts-from-created-at
    test-decide-ts-empty test-decide-ts-updated-at-wins
]
use ./ghcr-purge/sort.nu [
    test-sort-oldest-first test-sort-empty-ts-first test-sort-id-tiebreaker
    test-sort-decide-pipeline test-budget-oldest-selected
]
use ./ghcr-purge/plan.nu [
    test-plan-empty-desired-no-force test-plan-empty-desired-force test-plan-nonempty-desired-no-force
    test-plan-force-noop-with-ssot test-plan-budget-cap test-plan-budget-zero-unlimited
    test-plan-empty-versions test-plan-no-untagged-empty-result
]
use ./ghcr-purge/force-gate.nu [
    test-force-gate-no-service test-force-gate-dry-run test-force-gate-allowed
    test-force-gate-no-force-always-allowed
]
use ./ghcr-purge/ssot.nu [
    test-ssot-known-service test-ssot-no-manifest test-ssot-no-registry-prefix
    test-ssot-sorted-unique test-ssot-tracked-only-isolation
]
use ./ghcr-purge/core.nu [
    test-core-live-delete-success test-core-live-delete-fail-strict test-core-live-delete-fail-partial
    test-core-dry-run test-core-strict-stop-first-failure test-core-partial-continues-after-failure
    test-core-permission-denied test-core-list-fail
]
use ./ghcr-purge/aggregate.nu [
    test-aggregate-dry-run-run-wide-budget test-aggregate-failed-services
    test-aggregate-budget-stops-iteration test-aggregate-strict-stop-halts
    test-aggregate-no-strict-stop-continues
]
use ./ghcr-purge/format.nu [test-format-summary test-format-summary-clean]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })

    let results = [
        (test-decide-untagged-is-candidate $verbose_flag)
        (test-decide-desired-tag-kept $verbose_flag)
        (test-decide-no-desired-tags $verbose_flag)
        (test-decide-partial-intersection $verbose_flag)
        (test-decide-empty-versions $verbose_flag)
        (test-decide-all-stale $verbose_flag)
        (test-decide-empty-desired-set $verbose_flag)
        (test-decide-ts-from-updated-at $verbose_flag)
        (test-decide-ts-from-created-at $verbose_flag)
        (test-decide-ts-empty $verbose_flag)
        (test-decide-ts-updated-at-wins $verbose_flag)
        (test-sort-oldest-first $verbose_flag)
        (test-sort-empty-ts-first $verbose_flag)
        (test-sort-id-tiebreaker $verbose_flag)
        (test-sort-decide-pipeline $verbose_flag)
        (test-budget-oldest-selected $verbose_flag)
        (test-plan-empty-desired-no-force $verbose_flag)
        (test-plan-empty-desired-force $verbose_flag)
        (test-plan-nonempty-desired-no-force $verbose_flag)
        (test-plan-force-noop-with-ssot $verbose_flag)
        (test-plan-budget-cap $verbose_flag)
        (test-plan-budget-zero-unlimited $verbose_flag)
        (test-plan-empty-versions $verbose_flag)
        (test-plan-no-untagged-empty-result $verbose_flag)
        (test-force-gate-no-service $verbose_flag)
        (test-force-gate-dry-run $verbose_flag)
        (test-force-gate-allowed $verbose_flag)
        (test-force-gate-no-force-always-allowed $verbose_flag)
        (test-ssot-known-service $verbose_flag)
        (test-ssot-no-manifest $verbose_flag)
        (test-ssot-no-registry-prefix $verbose_flag)
        (test-ssot-sorted-unique $verbose_flag)
        (test-ssot-tracked-only-isolation $verbose_flag)
        (test-core-live-delete-success $verbose_flag)
        (test-core-live-delete-fail-strict $verbose_flag)
        (test-core-live-delete-fail-partial $verbose_flag)
        (test-core-dry-run $verbose_flag)
        (test-aggregate-dry-run-run-wide-budget $verbose_flag)
        (test-aggregate-failed-services $verbose_flag)
        (test-aggregate-budget-stops-iteration $verbose_flag)
        (test-core-strict-stop-first-failure $verbose_flag)
        (test-core-partial-continues-after-failure $verbose_flag)
        (test-aggregate-strict-stop-halts $verbose_flag)
        (test-aggregate-no-strict-stop-continues $verbose_flag)
        (test-format-summary $verbose_flag)
        (test-format-summary-clean $verbose_flag)
        (test-core-permission-denied $verbose_flag)
        (test-core-list-fail $verbose_flag)
    ]

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
