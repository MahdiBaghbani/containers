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

# Parse optional boolean environment variable (returns null if unset)
def parse_optional_bool_env [var_name: string] {
  let value = (get_env_or_default $var_name "")
  
  if ($value | str length) == 0 {
    return null
  }
  
  let value_str = ($value | into string | str downcase)
  $value_str in ["true", "1", "yes"]
}

# Normalize a truthy/falsy string to bool.
# Accepts on/1/true/yes -> true, off/0/false/no -> false, anything else -> null.
def normalize_bool_str [s: string] {
  let v = ($s | str trim | str downcase)
  if $v in ["1", "on", "true", "yes"] {
    true
  } else if $v in ["0", "off", "false", "no"] {
    false
  } else {
    null
  }
}

# Read an OCM invites bool toggle via the unified contacts command.
# Returns "1" or "0" on success, empty string on failure.
def get_ocm_invites_option [user: string, option: string] {
  try {
    let result = (run_as $user $"php /var/www/html/occ contacts:ocm-invites-config ($option)" | complete)
    if $result.exit_code == 0 {
      $result.stdout | str trim
    } else {
      ""
    }
  } catch {
    ""
  }
}

# Persist an OCM invites bool toggle if it differs from the current value.
# Uses occ contacts:ocm-invites-config so admins and the hook share one entry point.
# Idempotence check normalizes on/off and 1/0 to the same canonical bool.
def set_ocm_invites_option_if_changed [user: string, option: string, enabled: bool] {
  let current_raw = (get_ocm_invites_option $user $option)
  let current_bool = (normalize_bool_str $current_raw)
  
  if $current_bool == $enabled {
    return false
  }
  
  let value_arg = if $enabled { "on" } else { "off" }
  try {
    let result = (run_as $user $"php /var/www/html/occ contacts:ocm-invites-config ($option) ($value_arg)" | complete)
    if $result.exit_code == 0 {
      print $"Set ($option) = ($value_arg)"
      true
    } else {
      print $"Warning: Failed to set ($option): exit code ($result.exit_code)"
      false
    }
  } catch {
    print $"Warning: Failed to set ($option): ($in)"
    false
  }
}

# Persist an OCM invites string option via the unified command if it differs from current.
# Used for non-bool options such as mesh_providers_service.
def set_ocm_invites_string_if_changed [user: string, option: string, value: string] {
  let current = (get_ocm_invites_option $user $option)
  if $current == $value {
    return false
  }
  try {
    let result = (run_as $user $"php /var/www/html/occ contacts:ocm-invites-config ($option) ($value)" | complete)
    if $result.exit_code == 0 {
      print $"Set ($option) = ($value)"
      true
    } else {
      print $"Warning: Failed to set ($option): exit code ($result.exit_code)"
      false
    }
  } catch {
    print $"Warning: Failed to set ($option): ($in)"
    false
  }
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

# Enable OCM invites feature (idempotent).
# Prefers the unified contacts:ocm-invites-config command; falls back to the
# older contacts:enable-ocm-invites for app versions that do not have it yet.
def enable_ocm_invites [user: string] {
  print "Checking OCM Invites feature availability..."
  
  # Unified command path (newer app versions)
  if (command_exists $user "contacts:ocm-invites-config") {
    set_ocm_invites_option_if_changed $user "ocm_invites_enabled" true
    return
  }
  
  # Fallback: older app versions that only expose contacts:enable-ocm-invites
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

# Configure mesh providers service URL (idempotent).
# Prefers the unified contacts:ocm-invites-config command; falls back to the
# older contacts:set-mesh-providers-service for app versions that do not have it.
def configure_mesh_providers [user: string, url: string] {
  print $"Checking mesh providers service configuration..."
  
  if not (($url | str starts-with "http://") or ($url | str starts-with "https://")) {
    print $"Warning: Mesh providers service URL does not start with http:// or https://: ($url)"
  }
  
  # Unified command path (newer app versions)
  if (command_exists $user "contacts:ocm-invites-config") {
    set_ocm_invites_string_if_changed $user "mesh_providers_service" $url
    return
  }
  
  # Fallback: older app versions that only expose contacts:set-mesh-providers-service
  if not (command_exists $user "contacts:set-mesh-providers-service") {
    print "Warning: contacts:set-mesh-providers-service command not available, skipping mesh providers configuration"
    return
  }
  
  if (is_mesh_providers_configured $user $url) {
    print $"Mesh providers service already configured with URL: ($url)"
    return
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

# Configure OCM invites mode and granular flags
# Mode provides defaults, per-flag env vars can override
def configure_ocm_invites_flags [user: string] {
  # Parse mode and per-flag overrides
  let mode = (get_env_or_default "CONTACTS_OCM_INVITES_MODE" "")
  let override_optional_mail = (parse_optional_bool_env "CONTACTS_OCM_INVITES_OPTIONAL_MAIL")
  let override_cc_sender = (parse_optional_bool_env "CONTACTS_OCM_INVITES_CC_SENDER")
  let override_encoded_copy = (parse_optional_bool_env "CONTACTS_OCM_INVITES_ENCODED_COPY_BUTTON")
  
  # Early return if nothing to configure
  let has_mode = ($mode | str length) > 0
  let has_overrides = ($override_optional_mail != null) or ($override_cc_sender != null) or ($override_encoded_copy != null)
  
  if not $has_mode and not $has_overrides {
    return
  }
  
  print "Configuring OCM Invites flags..."
  
  # Start with defaults (basic mode behavior)
  mut optional_mail = false
  mut cc_sender = true
  mut encoded_copy = false
  
  # Apply mode-based defaults
  if $mode == "advanced" {
    $optional_mail = true
    $cc_sender = true
    $encoded_copy = true
    print "Mode: advanced (optional email, CC, encoded copy all enabled)"
  } else if $mode == "basic" {
    $optional_mail = false
    $cc_sender = true
    $encoded_copy = false
    print "Mode: basic (email required, CC enabled, encoded copy hidden)"
  } else if $has_mode {
    print $"Warning: Unknown mode '($mode)', using basic defaults"
  }
  
  # Apply per-flag overrides
  if $override_optional_mail != null {
    $optional_mail = $override_optional_mail
    print $"Override: optional_mail = ($optional_mail)"
  }
  if $override_cc_sender != null {
    $cc_sender = $override_cc_sender
    print $"Override: cc_sender = ($cc_sender)"
  }
  if $override_encoded_copy != null {
    $encoded_copy = $override_encoded_copy
    print $"Override: encoded_copy = ($encoded_copy)"
  }
  
  # Apply configuration via the unified contacts command
  if not (command_exists $user "contacts:ocm-invites-config") {
    print "Warning: contacts:ocm-invites-config command not available, skipping OCM Invites flag configuration"
    return
  }
  
  set_ocm_invites_option_if_changed $user "ocm_invites_optional_mail" $optional_mail
  set_ocm_invites_option_if_changed $user "ocm_invites_cc_sender" $cc_sender
  set_ocm_invites_option_if_changed $user "ocm_invites_encoded_copy_button" $encoded_copy
}

def main [] {
  # Parse environment variables
  let enable_ocm = (parse_bool_env "CONTACTS_ENABLE_OCM_INVITES" false)
  let mesh_service = (get_env_or_default "CONTACTS_MESH_PROVIDERS_SERVICE" "")
  let mode = (get_env_or_default "CONTACTS_OCM_INVITES_MODE" "")
  let has_flag_overrides = (
    ((get_env_or_default "CONTACTS_OCM_INVITES_OPTIONAL_MAIL" "") | str length) > 0
    or ((get_env_or_default "CONTACTS_OCM_INVITES_CC_SENDER" "") | str length) > 0
    or ((get_env_or_default "CONTACTS_OCM_INVITES_ENCODED_COPY_BUTTON" "") | str length) > 0
  )
  
  # Early return if nothing to do
  let has_mode_or_flags = ($mode | str length) > 0 or $has_flag_overrides
  if not $enable_ocm and ($mesh_service | str length) == 0 and not $has_mode_or_flags {
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
  
  # Configure OCM invites mode and flags
  configure_ocm_invites_flags $user
}
