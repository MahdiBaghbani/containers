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

# Test-controlled registry for platform manifest existence

export def set-mock-platform-behavior [service: string, has_platforms: bool] {
  let registry_str = (try {
    $env.MOCK_PLATFORM_REGISTRY
  } catch {
    null
  })

  let current = (if $registry_str != null {
    try {
      $registry_str | from json
    } catch {
      {}
    }
  } else {
    {}
  })

  let updated = ($current | upsert $service $has_platforms)
  $env.MOCK_PLATFORM_REGISTRY = ($updated | to json)
}

export def clear-mock-platform-registry [] {
  try {
    $env.MOCK_PLATFORM_REGISTRY = "{}"
  } catch {
    try {
      hide-env MOCK_PLATFORM_REGISTRY
    } catch {}
    $env.MOCK_PLATFORM_REGISTRY = "{}"
  }
}

export def check-platforms-manifest-exists [service: string] {
  let registry_str = (try { $env.MOCK_PLATFORM_REGISTRY } catch { null })
  let registry = (if $registry_str != null {
    try { $registry_str | from json } catch { {} }
  } else {
    {}
  })
  if $service in ($registry | columns) {
    $registry | get $service
  } else {
    true  # Default: multi-platform
  }
}

export def check-versions-manifest-exists [service: string] {
  true  # Mocks assume all services have version manifests
}
