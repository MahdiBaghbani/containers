#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

# Common utilities for build scripts

export const ERROR_CA_NOT_FOUND = "CA metadata file not found. Please run scripts/tls/generate-ca.nu first"
export const ERROR_SERVICE_NOT_FOUND = "Service not found. Run 'make list-services' to see available services"

export def find-duplicates [items: list] {
  let unique = ($items | uniq)
  if ($items | length) == ($unique | length) {
    []
  } else {
    mut seen = []
    mut dups = []
    for item in $items {
      if $item in $seen {
        if not ($item in $dups) {
          $dups = ($dups | append $item)
        }
      } else {
        $seen = ($seen | append $item)
      }
    }
    $dups
  }
}

# Deep merge two records (records merge recursively, other values override)
export def deep-merge [
  base: record,
  override: record
] {
  mut result = $base
  
  for key in ($override | columns) {
    let override_val = ($override | get $key)
    let base_val = (try { $base | get $key } catch { null })
    
    # If both are records, merge recursively
    if ($override_val | describe | str starts-with "record") and ($base_val | describe | str starts-with "record") {
      $result = ($result | upsert $key (deep-merge $base_val $override_val))
    } else {
      # Otherwise, override wins
      $result = ($result | upsert $key $override_val)
    }
  }
  
  $result
}

export def require-ca [] {
  # Import relative to common.nu location
  use ../tls/lib.nu read-shared-ca-name
  let ca_name = (read-shared-ca-name)
  if $ca_name == null {
    error make {msg: $ERROR_CA_NOT_FOUND}
  }
  $ca_name
}

# Wrap error messages with context
export def with-error-context [context: string, block: closure] {
  try {
    do $block
  } catch {|err|
    error make {msg: $"($context): ($err.msg)"}
  }
}

export def get-service-dir [name: string] {
  $"services/($name)"
}

export def get-service-tls-dir [name: string] {
  $"services/($name)/tls"
}

export def get-service-cert-dir [name: string] {
  $"services/($name)/tls/certificates"
}

export def get-service-ca-dir [name: string] {
  $"services/($name)/tls/certificate-authority"
}

export def get-service-config-path [name: string] {
  $"services/($name).nuon"
}

export def get-service-versions-manifest-path [name: string] {
  $"services/($name)/versions.nuon"
}

export def get-service-platforms-manifest-path [name: string] {
  $"services/($name)/platforms.nuon"
}

export def get-or-default [record: record, key: string, default: any] {
  try {
    $record | get $key
  } catch {
    $default
  }
}

# Require field in record or error with context
export def require-field [record: record, field: string, context: string] {
  if not ($field in ($record | columns)) {
    error make {msg: $"($context): missing required field '($field)'"}
  }
  $record | get $field
}

export def validate-platform-name-format [platform_name: string] {
  mut errors = []
  
  if not ($platform_name =~ '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
    $errors = ($errors | append $"Platform name '($platform_name)' must match pattern ^[a-z0-9]+(?:-[a-z0-9]+)*$ (lowercase alphanumeric with dashes)")
  }
  
  if ($platform_name | str contains "--") {
    $errors = ($errors | append $"Platform name '($platform_name)' contains double dash (--)")
  }
  
  if ($platform_name | str ends-with "-") {
    $errors = ($errors | append $"Platform name '($platform_name)' ends with dash (-)")
  }
  
  {
    valid: ($errors | is-empty),
    errors: $errors
  }
}

export def ensure-repo-root [] {
  if not (("services" | path exists) and ("scripts" | path exists)) {
    error make {msg: "This script must be run from the repository root"}
  }
}

export def get-tls-mode [cfg: record] {
    let tls_enabled = (try { $cfg.tls.enabled | default false } catch { false })
    
    if not $tls_enabled {
        return null
    }
    
    try { 
        $cfg.tls.mode
    } catch { 
        error make {msg: "tls.mode is required when tls.enabled=true"}
    }
}

# Shared helper to avoid duplication - reads CA name from ca.json
export def read-ca-name [tls_enabled: bool] {
    if not $tls_enabled {
        return ""
    }
    
    let ca_metadata_file = "tls/certificate-authority/ca.json"
    if not ($ca_metadata_file | path exists) {
        error make {msg: $"CA metadata file not found: ($ca_metadata_file). Please run scripts/tls/generate-ca.nu first"}
    }
    
    let ca_metadata = (try {
        open $ca_metadata_file
    } catch {|err|
        error make {msg: $"CA metadata file '($ca_metadata_file)' has invalid JSON. Error: ($err.msg)"}
    })
    
    if not ("name" in ($ca_metadata | columns)) {
        error make {msg: $"CA metadata file '($ca_metadata_file)' missing required field 'name'"}
    }
    
    let ca_name = $ca_metadata.name
    if ($ca_name | str trim | is-empty) {
        error make {msg: $"CA metadata file '($ca_metadata_file)' has empty 'name' field"}
    }
    
    $ca_name
}

# Get repository root using git (for accurate repo root resolution)
# Note: There is an existing get-repo-root in scripts/tls/lib.nu that uses FILE_PWD/PWD detection.
# This function uses git-based detection for more accurate repo root resolution.
# Keep separate for now - consolidation deferred to future refactoring task.
export def get-repo-root [] {
    let git_result = (try {
        ^git rev-parse --show-toplevel
    } catch {
        null
    })
    
    if $git_result != null {
        ($git_result | str trim | path expand)
    } else {
        # Fallback to current working directory if git not available or not in git repo
        ($env.PWD | path expand)
    }
}
