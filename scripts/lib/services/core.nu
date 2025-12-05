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

# Services domain - service discovery and management
# See docs/concepts/service-configuration.md for architecture

# Get path to service config file
export def get-service-config-path [name: string] {
  $"services/($name).nuon"
}

# Get service directory path
export def get-service-dir [name: string] {
  $"services/($name)"
}

export def list-service-names [] {
  glob "services/*.nuon" 
  | where ($it | path basename) != "versions.nuon"
  | each {|file| 
      try {
        let cfg = (open $file)
        $cfg.name
      } catch {
        null
      }
  }
  | compact
  | sort
}

export def list-services [
  --tls-only                    # Filter to TLS-enabled services only
  --tls-disabled                # Filter to TLS-disabled services only
] {
  let all_services = (glob "services/*.nuon" 
    | where ($it | path basename) != "versions.nuon"
    | each {|file| 
        try {
          let cfg = (open $file)
          {
            name: $cfg.name,
            path: $file,
            config: $cfg,
            tls: (try { $cfg.tls } catch { {enabled: false} })
          }
        } catch {
          null
        }
    }
    | compact
    | sort-by name)
  
  # Apply TLS filtering if requested
  if $tls_only {
    $all_services | where {|svc|
      let tls_cfg = ($svc.tls | default {enabled: false})
      let enabled = (try { $tls_cfg.enabled } catch { false })
      $enabled == true
    }
  } else if $tls_disabled {
    $all_services | where {|svc|
      let tls_cfg = ($svc.tls | default {enabled: false})
      let enabled = (try { $tls_cfg.enabled } catch { false })
      $enabled == false
    }
  } else {
    $all_services
  }
}

export def get-service [name: string] {
  let service_file = $"services/($name).nuon"
  
  if not ($service_file | path exists) {
    error make { 
      msg: $"Service '($name)' not found. File does not exist: ($service_file)"
    }
  }
  
  try {
    open $service_file
  } catch {
    error make { 
      msg: $"Failed to parse service config: ($service_file)"
    }
  }
}

export def service-exists [name: string] {
  let services = (list-service-names)
  $name in $services
}

export def validate-service-name [name: string] {
  if not (service-exists $name) {
    let services = (list-service-names)
    let services_list = ($services | each {|s| $"  - ($s)" } | str join "\n")
    
    error make { 
      msg: $"Service '($name)' not found.\n\nAvailable services:\n($services_list)"
    }
  }
}

export def get-service-path [name: string] {
  $"services/($name).nuon"
}

export def has-version-manifest [name: string] {
  let manifest_path = $"services/($name)/versions.nuon"
  $manifest_path | path exists
}
