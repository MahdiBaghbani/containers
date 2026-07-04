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

# CI domain test suite

use ../lib/core/repo.nu [get-repo-root]
use ./lib.nu [print-test-summary]
use ./ci/deps-resolution.nu [
    test-list-service-names test-direct-dep-resolution test-all-direct-deps-known
    test-transitive-deps test-kasm-base-deps test-cypress-deps
]
use ./ci/workflows-github.nu [test-generated-workflows-match]
use ./ci/workflows-forgejo.nu [test-forgejo-workflows]
use ./ci/dep-nodes.nu [
    test-dep-nodes-common-tools-all-platforms test-dep-nodes-common-tools-debian
    test-dep-nodes-common-tools-unknown-target test-dep-nodes-shards-default-platform
    test-dep-nodes-shards-explicit-platform
]
use ./ci/tracked-only-plane.nu [
    test-tracked-only-build-matrix-json-rejected test-tracked-only-ci-workflow-rejected
    test-tracked-only-ci-ghcr-purge-rejected test-tracked-only-ci-deps-ignore-local-fragment
    test-tracked-only-build-matrix-json-with-fragment test-tracked-only-ci-workflow-with-fragment
    test-tracked-only-ci-ghcr-purge-with-fragment
]

def main [--verbose] {
  let entry = ((get-repo-root) | path join "scripts" "dockypody.nu")

  let results = [
    (test-list-service-names $verbose)
    (test-direct-dep-resolution $verbose)
    (test-all-direct-deps-known $verbose)
    (test-transitive-deps $verbose)
    (test-kasm-base-deps $verbose)
    (test-cypress-deps $verbose)
    (test-generated-workflows-match $verbose)
    (test-forgejo-workflows $verbose)
    (test-dep-nodes-common-tools-all-platforms $verbose)
    (test-dep-nodes-common-tools-debian $verbose)
    (test-dep-nodes-common-tools-unknown-target $verbose)
    (test-dep-nodes-shards-default-platform $verbose)
    (test-dep-nodes-shards-explicit-platform $verbose)
    (test-tracked-only-build-matrix-json-rejected $entry $verbose)
    (test-tracked-only-ci-workflow-rejected $entry $verbose)
    (test-tracked-only-ci-ghcr-purge-rejected $entry $verbose)
    (test-tracked-only-ci-deps-ignore-local-fragment $verbose)
    (test-tracked-only-build-matrix-json-with-fragment $entry $verbose)
    (test-tracked-only-ci-workflow-with-fragment $entry $verbose)
    (test-tracked-only-ci-ghcr-purge-with-fragment $entry $verbose)
  ]

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
