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

# Sync Nextcloud Contacts/OCM CA bundle with system CA bundle.
# Rebuilds /var/www/html/resources/config/ca-bundle.crt from an upstream
# base bundle plus the current system CA bundle in an idempotent way.

export def sync-ca-bundle [] {
  let system_bundle = "/etc/ssl/certs/ca-certificates.crt"
  let base_upstream = "/usr/src/nextcloud/resources/config/ca-bundle.crt"
  let base_runtime = "/var/www/html/resources/config/ca-bundle.crt"
  let target_dir = "/var/www/html/resources/config"
  let target_file = $"($target_dir)/ca-bundle.crt"
  let tmp_file = $"($target_dir)/.ca-bundle.crt.tmp"

  if not ($system_bundle | path exists) {
    print $"WARNING: System CA bundle not found at ($system_bundle); skipping Contacts CA-bundle sync."
    return
  }

  let base_path = if ($base_upstream | path exists) {
    $base_upstream
  } else if ($base_runtime | path exists) {
    $base_runtime
  } else {
    null
  }

  if not ($target_dir | path exists) {
    mkdir $target_dir
  }

  mut had_old = false
  mut old_owner = ""
  mut old_group = ""
  mut old_mode = ""

  if ($target_file | path exists) {
    $had_old = true

    let stat_output = (try { ^stat -c "%U %G %a" $target_file | str trim } catch { "" })
    let parts = ($stat_output | split row " ")

    if ($parts | length) == 3 {
      $old_owner = ($parts | get 0)
      $old_group = ($parts | get 1)
      $old_mode = ($parts | get 2)
    }
  }

  let base_content = if $base_path == null {
    ""
  } else {
    (try { open --raw $base_path } catch { "" })
  }

  let system_content = (try { open --raw $system_bundle } catch { "" })

  if ($system_content | str length) == 0 {
    print $"WARNING: System CA bundle at ($system_bundle) is empty; skipping Contacts CA-bundle sync."
    return
  }

  let merged = if ($base_content | str length) > 0 {
    if ($base_content | str ends-with "\n") {
      $"($base_content)($system_content)"
    } else {
      $"($base_content)\n($system_content)"
    }
  } else {
    $system_content
  }

  $merged | save --raw $tmp_file

  ^mv -f $tmp_file $target_file

  if $had_old and ($old_owner | str length) > 0 and ($old_group | str length) > 0 {
    ^chown $"($old_owner):($old_group)" $target_file | ignore
  } else {
    ^chown "www-data:root" $target_file | ignore
  }

  if $had_old and ($old_mode | str length) > 0 {
    ^chmod $old_mode $target_file | ignore
  } else {
    ^chmod "0644" $target_file | ignore
  }

  let base_label = if $base_path == null { "none" } else { $base_path }

  print $"Synced Contacts CA bundle: base=($base_label), system=($system_bundle), target=($target_file)"
}
