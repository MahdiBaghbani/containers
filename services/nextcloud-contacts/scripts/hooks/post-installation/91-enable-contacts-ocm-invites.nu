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

# Enable OCM Invites feature and configure mesh providers service
# Runs after contacts app is enabled (hook execution order: 90 -> 91)

use /usr/bin/lib/utils.nu [run_as, get_env_or_default]

# Parse boolean environment variable (supports true/1/yes, case-insensitive)
def parse_bool_env [var_name: string, default: bool = false] {
  let value = (get_env_or_default $var_name "")
  
  if ($value | str length) == 0 {
    return $default
  }
  
  let value_str = ($value | into string | str downcase)
  $value_str in ["true", "1", "yes"]
}

# Check if an occ command exists
def command_exists [user: string, cmd: string] {
  try {
    let result = (run_as $user "php /var/www/html/occ list" | complete)
    if $result.exit_code == 0 {
      ($result.stdout | str contains $cmd)
    } else {
      false
    }
  } catch {
    false
  }
}

# Check if OCM invites is already enabled
def is_ocm_invites_enabled [user: string] {
  try {
    let result = (run_as $user "php /var/www/html/occ config:app:get contacts ocm_invites_enabled" | complete)
    if $result.exit_code == 0 {
      let value = ($result.stdout | str trim)
      ($value == "1") or ($value == "true")
    } else {
      false
    }
  } catch {
    false
  }
}

# Check if mesh providers service is already configured with expected URL
def is_mesh_providers_configured [user: string, expected_url: string] {
  try {
    let result = (run_as $user "php /var/www/html/occ config:app:get contacts mesh_providers_service" | complete)
    if $result.exit_code == 0 {
      let value = ($result.stdout | str trim)
      $value == $expected_url
    } else {
      false
    }
  } catch {
    false
  }
}

# Enable OCM invites feature (idempotent)
def enable_ocm_invites [user: string] {
  print "Checking OCM Invites feature availability..."
  
  if not (command_exists $user "contacts:enable-ocm-invites") {
    print "Warning: contacts:enable-ocm-invites command not available, skipping OCM Invites enablement"
    return
  }
  
  if (is_ocm_invites_enabled $user) {
    print "OCM Invites is already enabled"
    return
  }
  
  print "Enabling OCM Invites..."
  try {
    let result = (run_as $user "php /var/www/html/occ contacts:enable-ocm-invites" | complete)
    if $result.exit_code == 0 {
      print "OCM Invites enabled successfully"
    } else {
      print $"Warning: occ contacts:enable-ocm-invites returned exit code ($result.exit_code)"
      print $result.stdout
      print $result.stderr
    }
  } catch {
    print $"Warning: Failed to enable OCM Invites: ($in)"
  }
}

# Configure mesh providers service URL (idempotent)
def configure_mesh_providers [user: string, url: string] {
  print $"Checking mesh providers service configuration..."
  
  if not (command_exists $user "contacts:set-mesh-providers-service") {
    print "Warning: contacts:set-mesh-providers-service command not available, skipping mesh providers configuration"
    return
  }
  
  if (is_mesh_providers_configured $user $url) {
    print $"Mesh providers service already configured with URL: ($url)"
    return
  }
  
  if not (($url | str starts-with "http://") or ($url | str starts-with "https://")) {
    print $"Warning: Mesh providers service URL does not start with http:// or https://: ($url)"
  }
  
  print $"Configuring mesh providers service: ($url)"
  try {
    let result = (run_as $user $"php /var/www/html/occ contacts:set-mesh-providers-service ($url)" | complete)
    if $result.exit_code == 0 {
      print "Mesh providers service configured successfully"
    } else {
      print $"Warning: occ contacts:set-mesh-providers-service returned exit code ($result.exit_code)"
      print $result.stdout
      print $result.stderr
    }
  } catch {
    print $"Warning: Failed to configure mesh providers service: ($in)"
  }
}

def main [] {
  # Parse environment variables
  let enable_ocm = (parse_bool_env "CONTACTS_ENABLE_OCM_INVITES" false)
  let mesh_service = (get_env_or_default "CONTACTS_MESH_PROVIDERS_SERVICE" "")
  
  # Early return if nothing to do
  if not $enable_ocm and ($mesh_service | str length) == 0 {
    return
  }
  
  # Get user context (same pattern as contacts hook)
  let uid = (^id -u | into int)
  let user = if $uid == 0 {
    ($env.APACHE_RUN_USER? | default "www-data") | str replace --regex "^#" ""
  } else {
    ($uid | into string)
  }
  
  # Enable OCM invites if requested
  if $enable_ocm {
    enable_ocm_invites $user
  }
  
  # Configure mesh providers service if provided
  if ($mesh_service | str length) > 0 {
    configure_mesh_providers $user $mesh_service
  }
}
