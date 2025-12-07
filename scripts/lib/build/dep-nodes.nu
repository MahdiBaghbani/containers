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

# Helper to get dependency node keys for CI artifact loading
# Composes existing manifest helpers to determine which shards to attempt loading

use ../manifest/core.nu [check-versions-manifest-exists load-versions-manifest]
use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest]

# Get all node keys for a list of dependency services
# Returns list of {service, version, platform} records representing shards to attempt loading
#
# Strategy: For each dependency service, enumerate all version+platform combinations.
# The caller (prepare-node-deps) will attempt to load each shard; missing shards are not fatal.
export def get-dependency-node-candidates [
  dep_services: list,
  target_platform: string = ""
] {
  mut candidates = []

  for dep_service in $dep_services {
    if not (check-versions-manifest-exists $dep_service) {
      continue
    }

    let versions_manifest = (load-versions-manifest $dep_service)
    let versions = (try { $versions_manifest.versions } catch { [] })

    if ($versions | is-empty) {
      continue
    }

    let has_platforms = (check-platforms-manifest-exists $dep_service)
    let platforms_manifest = (if $has_platforms {
      try { load-platforms-manifest $dep_service } catch { null }
    } else {
      null
    })

    for version_spec in $versions {
      let version_name = $version_spec.name

      if $has_platforms and $platforms_manifest != null {
        # Multi-platform service: if target has a platform, prefer matching platform
        let platforms = (try { $platforms_manifest.platforms } catch { [] })
        
        if ($target_platform | str length) > 0 {
          # Try to find matching platform first
          let matching = ($platforms | where {|p| $p.name == $target_platform})
          if not ($matching | is-empty) {
            $candidates = ($candidates | append {
              service: $dep_service,
              version: $version_name,
              platform: $target_platform
            })
          } else {
            # Target platform not found in dep - add all platforms
            for platform_spec in $platforms {
              $candidates = ($candidates | append {
                service: $dep_service,
                version: $version_name,
                platform: $platform_spec.name
              })
            }
          }
        } else {
          # Target is single-platform - add all dependency platforms
          for platform_spec in $platforms {
            $candidates = ($candidates | append {
              service: $dep_service,
              version: $version_name,
              platform: $platform_spec.name
            })
          }
        }
      } else {
        # Single-platform service
        $candidates = ($candidates | append {
          service: $dep_service,
          version: $version_name,
          platform: ""
        })
      }
    }
  }

  $candidates
}

# Simplified helper: get candidate shards matching target's platform when possible
# This is more selective - only loads shards likely to be used by the target
export def get-matching-dependency-shards [
  dep_services: list,
  target_platform: string = ""
] {
  mut candidates = []

  for dep_service in $dep_services {
    if not (check-versions-manifest-exists $dep_service) {
      continue
    }

    let versions_manifest = (load-versions-manifest $dep_service)
    let versions = (try { $versions_manifest.versions } catch { [] })

    if ($versions | is-empty) {
      continue
    }

    let has_platforms = (check-platforms-manifest-exists $dep_service)
    let platforms_manifest = (if $has_platforms {
      try { load-platforms-manifest $dep_service } catch { null }
    } else {
      null
    })

    for version_spec in $versions {
      let version_name = $version_spec.name

      if $has_platforms and $platforms_manifest != null {
        let platforms = (try { $platforms_manifest.platforms } catch { [] })
        
        if ($target_platform | str length) > 0 {
          # Target has platform - only add matching platform if it exists
          let matching = ($platforms | where {|p| $p.name == $target_platform})
          if not ($matching | is-empty) {
            $candidates = ($candidates | append {
              service: $dep_service,
              version: $version_name,
              platform: $target_platform
            })
          }
          # If no matching platform, don't add any - dep might not be compatible
        } else {
          # Target is single-platform - add default platform of dependency
          let default_platform = (try { $platforms_manifest.default } catch { "" })
          if ($default_platform | str length) > 0 {
            $candidates = ($candidates | append {
              service: $dep_service,
              version: $version_name,
              platform: $default_platform
            })
          } else if not ($platforms | is-empty) {
            # No default, use first platform
            let first_platform = ($platforms | first | get name)
            $candidates = ($candidates | append {
              service: $dep_service,
              version: $version_name,
              platform: $first_platform
            })
          }
        }
      } else {
        # Single-platform service
        $candidates = ($candidates | append {
          service: $dep_service,
          version: $version_name,
          platform: ""
        })
      }
    }
  }

  $candidates
}
