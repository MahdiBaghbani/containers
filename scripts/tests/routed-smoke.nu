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

# Routed CLI smoke tests
#
# Exercises operator-facing dispatch paths through scripts/dockypody.nu and
# the Makefile. Non-Docker and CI-safe: help paths only print, the make path
# uses -n (dry run), and the forced-CA path is hermetic (stubbed git +
# openssl, temp repo) so it never writes a real CA.

use ./lib.nu [print-test-summary]
use ./routed-smoke/help-dispatch.nu [
    test-smoke-root-help test-smoke-build-help test-smoke-tls-help
    test-smoke-ssh-help test-smoke-ci-help test-smoke-ci-workflow-no-target
    test-smoke-docs-help test-smoke-inspect-help
]
use ./routed-smoke/make-routing.nu [test-smoke-make-certs-filter]
use ./routed-smoke/tls-force-hermetic.nu [test-smoke-tls-ca-force-routing]
use ./routed-smoke/test-suite-metadata.nu [
    test-smoke-test-help test-smoke-docker-integration-skipped test-smoke-test-help-inventory
]
use ./routed-smoke/local-plane-build.nu [
    test-smoke-local-missing-root test-smoke-local-empty-topology
    test-smoke-tracked-miss-local-only-build
]
use ./routed-smoke/local-plane-inspect.nu [
    test-smoke-local-baseline-inspect test-smoke-local-env-materialization
    test-smoke-local-only-version-inspect test-smoke-tracked-miss-local-only-inspect
    test-smoke-local-version-replace-inspect test-smoke-local-version-scoped-fragment-precedence
    test-smoke-local-incomplete-mirror
]
use ./routed-smoke/local-plane-validate.nu [
    test-smoke-local-bad-topology test-smoke-local-validate-additive-version-source
    test-smoke-local-guard-ordering
]
use ./routed-smoke/internal-errors.nu [test-smoke-internal-suite-errors]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })

    let results = [
        (test-smoke-root-help $verbose_flag)
        (test-smoke-build-help $verbose_flag)
        (test-smoke-tls-help $verbose_flag)
        (test-smoke-ssh-help $verbose_flag)
        (test-smoke-ci-help $verbose_flag)
        (test-smoke-ci-workflow-no-target $verbose_flag)
        (test-smoke-docs-help $verbose_flag)
        (test-smoke-inspect-help $verbose_flag)
        (test-smoke-make-certs-filter $verbose_flag)
        (test-smoke-tls-ca-force-routing $verbose_flag)
        (test-smoke-test-help $verbose_flag)
        (test-smoke-docker-integration-skipped $verbose_flag)
        (test-smoke-test-help-inventory $verbose_flag)
        (test-smoke-local-missing-root $verbose_flag)
        (test-smoke-local-empty-topology $verbose_flag)
        (test-smoke-local-baseline-inspect $verbose_flag)
        (test-smoke-local-env-materialization $verbose_flag)
        (test-smoke-local-only-version-inspect $verbose_flag)
        (test-smoke-tracked-miss-local-only-build $verbose_flag)
        (test-smoke-tracked-miss-local-only-inspect $verbose_flag)
        (test-smoke-local-version-replace-inspect $verbose_flag)
        (test-smoke-local-version-scoped-fragment-precedence $verbose_flag)
        (test-smoke-local-bad-topology $verbose_flag)
        (test-smoke-local-validate-additive-version-source $verbose_flag)
        (test-smoke-local-guard-ordering $verbose_flag)
        (test-smoke-local-incomplete-mirror $verbose_flag)
        (test-smoke-internal-suite-errors $verbose_flag)
    ]

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
