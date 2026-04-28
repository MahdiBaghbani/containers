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

# Managed-config helpers for allow_local_remote_servers.
# Handles env validation, legacy stray-line repair, and fragment sync.

# The exact top-level line that prior sed-based installs injected into config.php
const STRAY_CONFIG_LINE = "  'allow_local_remote_servers' => true,"

# Validate NEXTCLOUD_ALLOW_LOCAL_REMOTE_SERVERS_MODE.
# Returns "off" or "allow". Unset/empty defaults to "off".
# Fails fast on any invalid non-empty value.
export def validate_allow_local_mode [] {
  let raw = ($env.NEXTCLOUD_ALLOW_LOCAL_REMOTE_SERVERS_MODE? | default "")
  if $raw == "" or $raw == "off" {
    "off"
  } else if $raw == "allow" {
    "allow"
  } else {
    error make { msg: $"Invalid NEXTCLOUD_ALLOW_LOCAL_REMOTE_SERVERS_MODE: '($raw)'. Allowed values: off, allow" }
  }
}

# Repair the legacy stray allow_local_remote_servers line in config.php.
# If the file does not exist or PHP lints clean, returns immediately.
# Only removes the exact known stray line; errors out on other parse failures.
# Preserves owner/group/mode on replacement. Re-lints after repair.
export def repair_legacy_config_php [
  --config: string = "/var/www/html/config/config.php"
] {
  if not ($config | path exists) {
    return
  }

  let lint = (^php -l $config | complete)
  if $lint.exit_code == 0 {
    return
  }

  let raw = (open --raw $config)
  let ends_with_nl = ($raw | str ends-with "\n")
  let lines = ($raw | lines)
  let stray_count = ($lines | where {|l| $l == $STRAY_CONFIG_LINE} | length)

  if $stray_count == 0 {
    error make {
      msg: ($"config.php PHP lint failed but the known stray line was not found."
        + " Manual repair needed. PHP error: " + ($lint.stderr | str trim))
    }
  }

  let filtered = ($lines | where {|l| $l != $STRAY_CONFIG_LINE})
  let new_content = if $ends_with_nl {
    ($filtered | str join "\n") + "\n"
  } else {
    $filtered | str join "\n"
  }

  let stat_out = (^stat -c "%U %G %a" $config | complete)
  let tmp = $"($config).tmp"
  $new_content | save --force $tmp

  if $stat_out.exit_code == 0 {
    let parts = ($stat_out.stdout | str trim | split row " ")
    if ($parts | length) >= 3 {
      ^chown $"($parts | get 0):($parts | get 1)" $tmp
      ^chmod ($parts | get 2) $tmp
    }
  }

  ^mv $tmp $config

  let lint2 = (^php -l $config | complete)
  if $lint2.exit_code != 0 {
    error make {
      msg: ($"config.php still fails PHP lint after stray-line removal."
        + " PHP error: " + ($lint2.stderr | str trim))
    }
  }

  print "Repaired legacy allow_local_remote_servers stray line in config.php"
}

# Sync the managed allow-local-remote-servers fragment from image source to the
# runtime config directory. The fragment is always managed here; the PHP inside
# the fragment reads NEXTCLOUD_ALLOW_LOCAL_REMOTE_SERVERS_MODE at runtime.
# Creates a missing parent dir, creates a missing target, and overwrites a stale
# target with atomic temp write+rename. Preserves owner/group/mode when
# replacing an existing file.
export def sync_allow_local_fragment [
  --src: string = "/usr/src/config/nextcloud/allow-local-remote-servers.config.php"
  --dst: string = "/var/www/html/config/allow-local-remote-servers.config.php"
] {
  validate_allow_local_mode | ignore

  if not ($src | path exists) {
    error make { msg: $"Managed config source not found: ($src)" }
  }

  let src_content = (open --raw $src)
  let dst_dir = ($dst | path dirname)

  if not ($dst_dir | path exists) {
    mkdir $dst_dir
  }

  if ($dst | path exists) {
    let dst_content = (open --raw $dst)
    if $src_content == $dst_content {
      return
    }
    let stat_out = (^stat -c "%U %G %a" $dst | complete)
    let tmp = $"($dst).tmp"
    $src_content | save --force $tmp
    if $stat_out.exit_code == 0 {
      let parts = ($stat_out.stdout | str trim | split row " ")
      if ($parts | length) >= 3 {
        ^chown $"($parts | get 0):($parts | get 1)" $tmp
        ^chmod ($parts | get 2) $tmp
      }
    }
    ^mv $tmp $dst
    print "Updated allow-local-remote-servers.config.php"
  } else {
    $src_content | save --force $dst
    print "Created allow-local-remote-servers.config.php"
  }
}

# Combined entry point: repair legacy config, then sync the managed fragment.
export def apply_allow_local_config [] {
  repair_legacy_config_php
  sync_allow_local_fragment
}
