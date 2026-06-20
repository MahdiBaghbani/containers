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

# Minimal effective-config inspect surface (guard-owned model only)

use ../build/config.nu [load-service-config]
use ../manifest/core.nu [
  check-versions-manifest-exists load-versions-manifest
  get-default-version get-version-spec apply-version-defaults
]
use ../platforms/core.nu [
  check-platforms-manifest-exists load-platforms-manifest
]

export def resolve-inspect-version-spec [
  service: string,
  version: string
] {
  if not (check-versions-manifest-exists $service) {
    error make {
      msg: $"Service '($service)' has no versions manifest; omit --version only when the service has no versions"
    }
  }

  let manifest = (load-versions-manifest $service)
  let version_name = (if ($version | str length) > 0 {
    $version
  } else {
    get-default-version $manifest
  })
  let version_spec = (get-version-spec $manifest $version_name)
  apply-version-defaults $manifest $version_spec
}

# Load guard-owned effective merged config for one service/version/platform.
export def inspect-effective-config [
  service: string,
  plane_ctx: record,
  version: string = "",
  platform: string = ""
] {
  let version_spec = (resolve-inspect-version-spec $service $version)
  let has_platforms = (check-platforms-manifest-exists $service)
  let platforms_manifest = (if $has_platforms { load-platforms-manifest $service } else { null })

  load-service-config $service $version_spec $platform $platforms_manifest $plane_ctx
}
