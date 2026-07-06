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

# Test helper functions for setup, assertions, and cleanup - stable public import surface

export use ./helpers/setup.nu [
  setup-test-environment
  setup-test-service-with-deps
]
export use ./helpers/factories.nu [
  create-test-version-spec
  create-test-dependency
  create-test-deps-resolved
  create-test-tls-meta
  create-test-registry-info
]
export use ./helpers/assertions.nu [
  assert-cache-bust-format
  assert-cache-bust-value
  assert-build-args-contain
  assert-build-order
  assert-graph-structure
]
export use ./helpers/cleanup.nu [
  cleanup-test-environment
  with-test-cleanup
]
