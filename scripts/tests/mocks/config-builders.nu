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

use ../../lib/platforms/core.nu [
  get-platform-spec
  merge-platform-config
  merge-version-overrides
]
use ../../lib/validate/core.nu [validate-merged-config]
use ./deps-registry.nu [get-registered-dependencies]
use ./platform-registry.nu [check-platforms-manifest-exists]

export def get-default-platform [platforms: record] {
  try { $platforms.default } catch { "" }
}

export def detect-build [] {
  {
    ref: "test-branch",
    sha: "test-sha-1234567890abcdef",
    commit_message: "Test commit message",
    is_local: true,
    platforms: ["linux/amd64"]
  }
}

export def get-mock-service-config [
  service: string,
  version_spec: record,
  platform: string = "",
  platforms: any = null
] {
  mut base_cfg = {
    name: $service,
    context: $"services/($service)",
    dockerfile: $"services/($service)/Dockerfile",
    sources: {
      test_source: {
        url: "https://github.com/test/repo",
        ref: "v1.0.0"
      }
    }
  }

  let registered_deps = (get-registered-dependencies $service $version_spec.name)
  if not ($registered_deps | is-empty) {
    $base_cfg = ($base_cfg | insert dependencies $registered_deps)
  }

  if "overrides" in ($version_spec | columns) {
    let overrides = $version_spec.overrides
    if "external_images" in ($overrides | columns) {
      let ext_images = $overrides.external_images
      if "build" in ($ext_images | columns) {
        let build_img = $ext_images.build
        if "tag" in ($build_img | columns) {
          $base_cfg = ($base_cfg | insert external_images {
            build: {
              name: (try { $build_img.name } catch { "golang" }),
              tag: $build_img.tag,
              build_arg: (try { $build_img.build_arg } catch { "BASE_BUILD_IMAGE" })
            }
          })
        }
      }
    }
  }

  if not ("external_images" in ($base_cfg | columns)) {
    $base_cfg = ($base_cfg | insert external_images {
      build: {
        name: "golang",
        tag: "1.25-trixie",
        build_arg: "BASE_BUILD_IMAGE"
      }
    })
  }

  mut merged_cfg = $base_cfg

  if ($platform | str length) > 0 {
    if $platforms == null {
      error make { msg: $"Platform '($platform)' specified but platforms manifest not provided to get-mock-service-config" }
    }
    let platform_spec = (get-platform-spec $platforms $platform)
    $merged_cfg = (merge-platform-config $merged_cfg $platform_spec)
  }

  $merged_cfg = (merge-version-overrides $merged_cfg $version_spec $platform $platforms)

  let has_platforms = (if $platforms != null {
    true
  } else {
    (check-platforms-manifest-exists $service)
  })

  let validation = (validate-merged-config $merged_cfg $service $has_platforms $platform)
  if not $validation.valid {
    error make { msg: $"Mock config validation failed for service '($service)': ($validation.errors | str join ', ')" }
  }

  $merged_cfg
}

export def build-mock-version-manifest [
  default_version: string = "v1.0.0",
  versions: list = []
] {
  let version_list = (if ($versions | length) == 0 {
    [{
      name: $default_version,
      latest: true,
      tags: [],
      overrides: {}
    }]
  } else {
    $versions
  })

  {
    default: $default_version,
    versions: $version_list
  }
}

export def build-mock-platform-manifest [
  default_platform: string = "debian",
  platforms: list = []
] {
  let platform_list = (if ($platforms | length) == 0 {
    [{
      name: $default_platform,
      dockerfile: $"services/test-service/Dockerfile",
      external_images: {
        build: {
          name: "golang",
          tag: "1.25-trixie",
          build_arg: "BASE_BUILD_IMAGE"
        }
      }
    }]
  } else {
    $platforms
  })

  {
    default: $default_platform,
    platforms: $platform_list
  }
}
