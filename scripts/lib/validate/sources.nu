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

# Service and manifest file validation

use ./merged.nu [validate-service-config]

export def validate-service-file [
  service: string
] {
  use ../platforms/core.nu [check-platforms-manifest-exists]
  
  let cfg_path = $"services/($service).nuon"
  
  if not ($cfg_path | path exists) {
    return {
      valid: false,
      errors: [$"Service config not found: ($cfg_path)"]
    }
  }
  
  let config = (try {
    open $cfg_path
  } catch {
    return {
      valid: false,
      errors: [$"Failed to parse service config: ($cfg_path)"]
    }
  })
  
  let has_platforms = (check-platforms-manifest-exists $service)
  let service_name = (try { $config.name } catch { $service })
  validate-service-config $config $has_platforms $service_name
}

# Validate version manifest (two-phase: base validation, then platform expansion if platforms exist)
export def validate-manifest-file [
  service: string
] {
  use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest]
  use ./versions.nu [validate-version-manifest]
  
  let manifest_path = $"services/($service)/versions.nuon"
  
  if not ($manifest_path | path exists) {
    return {
      valid: false,
      errors: [$"Version manifest not found: ($manifest_path). All services MUST have version manifests."]
    }
  }
  
  let manifest = (try {
    open $manifest_path
  } catch {
    return {
      valid: false,
      errors: [$"Failed to parse version manifest: ($manifest_path)"]
    }
  })
  
  # Load platforms manifest if it exists for expanded-tag validation
  # Optimization: Only load if it exists (already checked in validate-service-complete)
  let has_platforms = (check-platforms-manifest-exists $service)
  let platforms = (if $has_platforms {
    try {
      load-platforms-manifest $service
    } catch { |err|
      # If platforms manifest exists but can't be loaded, return error
      return {
        valid: false,
        errors: [$"Failed to load platforms manifest for service '($service)': ($err.msg)"]
      }
    }
  } else {
    null
  })
  
  # Pass platforms manifest to enable expanded-tag validation (tag collision detection after expansion)
  # Note: platforms can be null for single-platform services
  validate-version-manifest $manifest $platforms
}