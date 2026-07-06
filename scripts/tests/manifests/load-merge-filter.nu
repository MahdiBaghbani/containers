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

# Load, merge, and filter behavior tests.

use ../../lib/manifest/core.nu [load-versions-manifest filter-versions]
use ../../lib/platforms/core.nu [merge-version-overrides]
use ../lib.nu [run-test]

export def test-load-manifest [verbose: bool] {
  run-test "Load manifest" {
    let manifest = (load-versions-manifest "revad-base")
    if $verbose { print $"    Default version: ($manifest.default)" }
    true
  } $verbose
}

export def test-config-merge-with-overrides [verbose: bool] {
  run-test "Config merge with overrides" {
    let manifest = (load-versions-manifest "revad-base")
    let base_config = (open "services/revad-base.nuon")

    if ($manifest.versions | length) > 0 {
      let version_spec = $manifest.versions.0
      # Use merge-version-overrides with empty platform string for single-platform
      let merged = (merge-version-overrides $base_config $version_spec "" null)
      if $verbose { print $"    Merged config has ($merged | columns | length) keys" }
    }
    true
  } $verbose
}

export def test-filter-versions-all [verbose: bool] {
  run-test "Filter versions (all)" {
    let manifest = (load-versions-manifest "revad-base")
    # filter-versions now returns record with {versions, detected_platforms}
    let result = (filter-versions $manifest null --all=true)
    let all_versions = $result.versions
    if $verbose { print $"    Found ($all_versions | length) version\(s\)" }
    true
  } $verbose
}
