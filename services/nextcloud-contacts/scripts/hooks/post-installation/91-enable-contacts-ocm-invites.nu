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

# Configure the Contacts OCM Invites feature from environment variables.
# Runs after the contacts app is enabled (hook order: 90 -> 91).
# Every setting is written to the contacts app config via occ config:app:set.

use /usr/bin/lib/utils.nu [run_as, get_env_or_default]

# Parse a boolean environment variable, returning $default when unset/empty.
def parse_bool [name: string, default: bool] {
  let raw = (get_env_or_default $name "")
  if ($raw | str length) == 0 {
    $default
  } else {
    (($raw | str downcase) in ["1", "true", "yes", "on"])
  }
}

# Parse an optional boolean environment variable, returning null when unset.
def parse_optional_bool [name: string] {
  let raw = (get_env_or_default $name "")
  if ($raw | str length) == 0 {
    null
  } else {
    (($raw | str downcase) in ["1", "true", "yes", "on"])
  }
}

# Resolve the user that owns the occ process.
def occ_user [] {
  let uid = (^id -u | into int)
  if $uid == 0 {
    ($env.APACHE_RUN_USER? | default "www-data") | str replace --regex "^#" ""
  } else {
    ($uid | into string)
  }
}

# Write a boolean contacts app config value.
def set_bool [user: string, key: string, value: bool] {
  let raw = (if $value { "true" } else { "false" })
  let result = (run_as $user $"php /var/www/html/occ config:app:set contacts ($key) --value=($raw) --type=boolean" | complete)
  if $result.exit_code == 0 {
    print $"Set ($key) = ($raw)"
  } else {
    print $"Warning: failed to set ($key): exit code ($result.exit_code)"
    print $result.stderr
  }
}

# Write a string contacts app config value.
def set_string [user: string, key: string, value: string] {
  let result = (run_as $user $"php /var/www/html/occ config:app:set contacts ($key) --value=($value) --type=string" | complete)
  if $result.exit_code == 0 {
    print $"Set ($key) = ($value)"
  } else {
    print $"Warning: failed to set ($key): exit code ($result.exit_code)"
    print $result.stderr
  }
}

def main [] {
  let enable = (parse_bool "CONTACTS_ENABLE_OCM_INVITES" false)
  let mode = (get_env_or_default "CONTACTS_OCM_INVITES_MODE" "" | str downcase)
  let mesh = (get_env_or_default "CONTACTS_MESH_PROVIDERS_SERVICE" "")
  let optional_mail_override = (parse_optional_bool "CONTACTS_OCM_INVITES_OPTIONAL_MAIL")
  let encoded_copy_override = (parse_optional_bool "CONTACTS_OCM_INVITES_ENCODED_COPY_BUTTON")
  let ssrf_override = (parse_optional_bool "CONTACTS_OCM_INVITES_DISABLE_SSRF_GUARD")

  let has_mode = ($mode | str length) > 0
  let has_flags = ($optional_mail_override != null) or ($encoded_copy_override != null)
  let has_mesh = ($mesh | str length) > 0
  let has_ssrf = ($ssrf_override != null)

  # Nothing requested: leave the app config untouched.
  if (not $enable) and (not $has_mode) and (not $has_flags) and (not $has_mesh) and (not $has_ssrf) {
    return
  }

  let user = (occ_user)

  # Feature toggle.
  set_bool $user "ocm_invites_enabled" $enable

  # Mode presets, then per-flag overrides.
  if $has_mode or $has_flags {
    if $has_mode and ($mode not-in ["basic", "advanced"]) {
      print $"Warning: unknown CONTACTS_OCM_INVITES_MODE '($mode)', using basic defaults"
    }
    let advanced = ($mode == "advanced")
    let optional_mail = ($optional_mail_override | default $advanced)
    let encoded_copy = ($encoded_copy_override | default $advanced)
    set_bool $user "ocm_invites_optional_mail" $optional_mail
    set_bool $user "ocm_invites_encoded_copy_button" $encoded_copy
  }

  # Discovery SSRF guard (needed for private or local mesh hosts).
  if $has_ssrf {
    set_bool $user "ocm_invites_disable_ssrf_guard" $ssrf_override
  }

  # Mesh providers discovery service URL.
  if $has_mesh {
    if not (($mesh | str starts-with "http://") or ($mesh | str starts-with "https://")) {
      print $"Warning: CONTACTS_MESH_PROVIDERS_SERVICE does not start with http:// or https://: ($mesh)"
    }
    set_string $user "mesh_providers_service" $mesh
  }
}
