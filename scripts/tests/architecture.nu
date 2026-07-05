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

# Architecture enforcement tests
# Ensures CLI pattern: dockypody.nu routes through domain-local cli.nu files

use ./lib.nu [print-test-summary]
use ./architecture/layout-structure.nu [
  test-no-flat-nu-files-in-lib test-lib-only-directories test-required-domain-dirs
  test-only-dockypody-at-scripts-root test-cli-domains-have-cli-nu
  test-plane-module-exposes-helpers
]
use ./architecture/plane-guard-basics.nu [
  test-plane-local-requires-root test-empty-local-root-valid test-empty-local-services-valid
  test-tracked-plane-no-local-root test-parse-plane-rejects-unknown test-file-local-root-invalid
]
use ./architecture/cli-plane-docs.nu [
  test-build-help-documents-plane test-validate-help-documents-plane
]
use ./architecture/cli-plane-routing.nu [
  test-build-plane-local-guard test-validate-plane-local-service-guard test-validate-plane-local-help
]
use ./architecture/topology-errors.nu [
  test-unsupported-root-file test-unsupported-root-directory test-unknown-service-mirror
  test-unsupported-mirror-file test-unsupported-mirror-subdirectory test-empty-tracked-mirror
  test-unsupported-root-symlink test-tracked-mirror-symlink test-unreadable-topology-dirs
  test-loose-file-under-services test-unreadable-tracked-mirror test-non-directory-services-path
  test-extra-mirror-sibling test-hidden-root-entry test-hidden-unknown-mirror
  test-hidden-mirror-content test-manifest-filename-name-mismatch test-unsupported-mirror-non-file-item
]
use ./architecture/topology-legal.nu [
  test-legal-tracked-mirror test-audit-reports-legal-mirrors test-guard-merged-audit-shape
  test-absent-local-mirrors test-empty-local-services
]
use ./architecture/tracked-manifest-guard-order.nu [
  test-manifest-missing-name test-broken-manifest-before-mirror-audit
  test-empty-root-ignores-broken-manifest test-empty-services-ignores-broken-manifest
  test-mirror-passes-unrelated-broken-manifest test-audit-ignores-broken-unrelated-manifest
]
use ./architecture/effective-config.nu [
  test-env-only-source-path-materializes test-invalid-env-source-path
  test-load-service-config-env-materialization test-build-args-ignore-post-guard-env
  test-inspect-routes-through-guard test-inspect-effective-config-success
  test-missing-root-presence-contract
]

def main [--verbose] {
  let verbose_flag = $verbose

  print "Architecture Enforcement Tests\n"

  let results = [
    (test-no-flat-nu-files-in-lib $verbose_flag)
    (test-lib-only-directories $verbose_flag)
    (test-required-domain-dirs $verbose_flag)
    (test-only-dockypody-at-scripts-root $verbose_flag)
    (test-cli-domains-have-cli-nu $verbose_flag)
    (test-plane-module-exposes-helpers $verbose_flag)
    (test-plane-local-requires-root $verbose_flag)
    (test-empty-local-root-valid $verbose_flag)
    (test-empty-local-services-valid $verbose_flag)
    (test-tracked-plane-no-local-root $verbose_flag)
    (test-parse-plane-rejects-unknown $verbose_flag)
    (test-build-help-documents-plane $verbose_flag)
    (test-validate-help-documents-plane $verbose_flag)
    (test-file-local-root-invalid $verbose_flag)
    (test-build-plane-local-guard $verbose_flag)
    (test-validate-plane-local-service-guard $verbose_flag)
    (test-validate-plane-local-help $verbose_flag)
    (test-unsupported-root-file $verbose_flag)
    (test-unsupported-root-directory $verbose_flag)
    (test-unknown-service-mirror $verbose_flag)
    (test-unsupported-mirror-file $verbose_flag)
    (test-unsupported-mirror-subdirectory $verbose_flag)
    (test-empty-tracked-mirror $verbose_flag)
    (test-legal-tracked-mirror $verbose_flag)
    (test-unsupported-root-symlink $verbose_flag)
    (test-tracked-mirror-symlink $verbose_flag)
    (test-unreadable-topology-dirs $verbose_flag)
    (test-loose-file-under-services $verbose_flag)
    (test-unreadable-tracked-mirror $verbose_flag)
    (test-audit-reports-legal-mirrors $verbose_flag)
    (test-guard-merged-audit-shape $verbose_flag)
    (test-absent-local-mirrors $verbose_flag)
    (test-empty-local-services $verbose_flag)
    (test-manifest-missing-name $verbose_flag)
    (test-non-directory-services-path $verbose_flag)
    (test-extra-mirror-sibling $verbose_flag)
    (test-hidden-root-entry $verbose_flag)
    (test-hidden-unknown-mirror $verbose_flag)
    (test-hidden-mirror-content $verbose_flag)
    (test-broken-manifest-before-mirror-audit $verbose_flag)
    (test-empty-root-ignores-broken-manifest $verbose_flag)
    (test-empty-services-ignores-broken-manifest $verbose_flag)
    (test-mirror-passes-unrelated-broken-manifest $verbose_flag)
    (test-audit-ignores-broken-unrelated-manifest $verbose_flag)
    (test-manifest-filename-name-mismatch $verbose_flag)
    (test-unsupported-mirror-non-file-item $verbose_flag)
    (test-env-only-source-path-materializes $verbose_flag)
    (test-invalid-env-source-path $verbose_flag)
    (test-load-service-config-env-materialization $verbose_flag)
    (test-build-args-ignore-post-guard-env $verbose_flag)
    (test-inspect-routes-through-guard $verbose_flag)
    (test-inspect-effective-config-success $verbose_flag)
    (test-missing-root-presence-contract $verbose_flag)
  ]

  print-test-summary $results

  if ($results | all {|r| $r}) {
    exit 0
  } else {
    exit 1
  }
}
