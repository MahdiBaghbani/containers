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

# Version manifest tests

use ./lib.nu [print-test-summary]
use ./manifests/integration.nu [
  test-matrix-json-generation test-all-services-pass-complete-validation
]
use ./manifests/inventory.nu [
  test-all-services-have-manifests test-validate-service-configs test-validate-manifests
]
use ./manifests/load-merge-filter.nu [
  test-load-manifest test-config-merge-with-overrides test-filter-versions-all
]
use ./manifests/version-validation.nu [
  test-detect-forbidden-latest-in-tags test-detect-duplicate-version-names
  test-detect-tag-collision-across-versions test-detect-multiple-latest-versions
]
use ./manifests/platform-validation.nu [
  test-detect-platform-suffix-in-version-name test-platform-expansion-composite-uniqueness
  test-multi-platform-service-without-base-dockerfile test-single-platform-service-without-dockerfile
  test-platform-config-missing-build-arg test-platform-config-complete-external-images
]
use ./manifests/matrix.nu [test-matrix-includes-platform-field]
use ./manifests/merge-behavior.nu [test-deep-merge-external-images]
use ./manifests/expanded-tags.nu [
  test-validate-manifest-file-expanded-tag-validation test-validate-manifest-file-auto-loads-platforms
]
use ./manifests/schema-examples.nu [test-schema-examples-validate-against-live-validators]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })

  let results = [
    (test-matrix-json-generation $verbose_flag)
    (test-all-services-have-manifests $verbose_flag)
    (test-load-manifest $verbose_flag)
    (test-validate-service-configs $verbose_flag)
    (test-validate-manifests $verbose_flag)
    (test-config-merge-with-overrides $verbose_flag)
    (test-filter-versions-all $verbose_flag)
    (test-detect-forbidden-latest-in-tags $verbose_flag)
    (test-detect-duplicate-version-names $verbose_flag)
    (test-detect-tag-collision-across-versions $verbose_flag)
    (test-detect-multiple-latest-versions $verbose_flag)
    (test-detect-platform-suffix-in-version-name $verbose_flag)
    (test-platform-expansion-composite-uniqueness $verbose_flag)
    (test-matrix-includes-platform-field $verbose_flag)
    (test-multi-platform-service-without-base-dockerfile $verbose_flag)
    (test-single-platform-service-without-dockerfile $verbose_flag)
    (test-platform-config-missing-build-arg $verbose_flag)
    (test-platform-config-complete-external-images $verbose_flag)
    (test-deep-merge-external-images $verbose_flag)
    (test-validate-manifest-file-expanded-tag-validation $verbose_flag)
    (test-validate-manifest-file-auto-loads-platforms $verbose_flag)
    (test-all-services-pass-complete-validation $verbose_flag)
    (test-schema-examples-validate-against-live-validators $verbose_flag)
  ]

  print-test-summary $results

  if ($results | any {|r| not $r}) {
    exit 1
  }
}
