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

use ../mocks.nu [
  detect-build
  get-mock-service-config
  build-mock-version-manifest
  build-mock-platform-manifest
  set-mock-platform-behavior
  register-mock-service-dependencies
]
use ../../lib/manifest/core.nu [get-version-or-null]

export def setup-test-environment [
  service: string = "test-service",
  version_name: string = "v1.0.0",
  has_platforms: bool = true,
  custom_version_overrides: record = {},
  custom_platforms: list = []
] {
  set-mock-platform-behavior $service $has_platforms

  let version_list = (if ($custom_version_overrides | is-empty) {
    [{
      name: $version_name,
      latest: true,
      tags: [],
      overrides: {}
    }]
  } else {
    [{
      name: $version_name,
      latest: true,
      tags: [],
      overrides: $custom_version_overrides
    }]
  })
  let version_manifest = (build-mock-version-manifest $version_name $version_list)

  let version_spec = (get-version-or-null $version_manifest $version_name)
  if $version_spec == null {
    error make { msg: $"Version '($version_name)' not found in mock manifest" }
  }

  let platforms = (if $has_platforms {
    if ($custom_platforms | length) > 0 {
      build-mock-platform-manifest "debian" $custom_platforms
    } else {
      build-mock-platform-manifest
    }
  } else {
    null
  })

  let platform = (if $platforms != null {
    try { $platforms.default } catch { "" }
  } else {
    ""
  })
  let merged_cfg = (get-mock-service-config $service $version_spec $platform $platforms)

  let meta = (detect-build)

  let deps_resolved = {}

  let tls_meta = {
    enabled: false,
    mode: "disabled",
    cert_name: "",
    ca_name: ""
  }

  let ssh_meta = {
    enabled: false,
    mode: "disabled",
    default_user: "root",
    port: 22,
    listen: "0.0.0.0"
  }

  let registry_info = {
    registry: "",
    namespace: "",
    is_local: true
  }

  {
    service: $service,
    version_spec: $version_spec,
    version_manifest: $version_manifest,
    platforms: $platforms,
    merged_cfg: $merged_cfg,
    meta: $meta,
    deps_resolved: $deps_resolved,
    tls_meta: $tls_meta,
    ssh_meta: $ssh_meta,
    registry_info: $registry_info
  }
}

export def setup-test-service-with-deps [
  service: string,
  dependencies: record,
  version_name: string = "v1.0.0"
] {
  mut test_env = (setup-test-environment $service $version_name)

  mut merged_cfg = $test_env.merged_cfg
  if "dependencies" in ($merged_cfg | columns) {
    $merged_cfg = ($merged_cfg | upsert dependencies ($merged_cfg.dependencies | merge $dependencies))
  } else {
    $merged_cfg = ($merged_cfg | insert dependencies $dependencies)
  }

  $test_env = ($test_env | upsert merged_cfg $merged_cfg)

  register-mock-service-dependencies $service $version_name $dependencies

  $test_env
}
