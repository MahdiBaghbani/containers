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

# Mock infrastructure for test isolation - stable public import surface

export use ./mocks/config-builders.nu [
  get-default-platform
  detect-build
  get-mock-service-config
  build-mock-version-manifest
  build-mock-platform-manifest
]
export use ./mocks/platform-registry.nu [
  set-mock-platform-behavior
  clear-mock-platform-registry
  check-platforms-manifest-exists
  check-versions-manifest-exists
]
export use ./mocks/deps-registry.nu [
  register-mock-service-dependencies
  clear-mock-service-deps-registry
]
export use ./mocks/dependency-graph.nu [build-dependency-graph-with-mocks]
