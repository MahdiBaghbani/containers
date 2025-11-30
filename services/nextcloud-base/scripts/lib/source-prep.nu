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

# Source preparation and copy-on-write for Nextcloud

use ./utils.nu [directory_empty]

export def detect_source_mount [] {
  let source_dir = "/usr/src/nextcloud"
  let target_dir = "/var/www/html"
  
  if not ($source_dir | path exists) {
    print "Source directory does not exist, skipping mount detection"
    return false
  }
  
  let source_readable = (^test -r $source_dir | complete | get exit_code) == 0
  if not $source_readable {
    print "Warning: Source directory is not readable"
    return false
  }
  
  let required_files = [
    $"($source_dir)/version.php"
    $"($source_dir)/index.php"
    $"($source_dir)/occ"
  ]
  
  mut all_files_present = true
  for file in $required_files {
    if not ($file | path exists) {
      print $"Warning: Required file missing in source: ($file)"
      $all_files_present = false
      break
    }
  }
  
  if not $all_files_present {
    return false
  }
  
  if not ($target_dir | path exists) {
    print "Target directory does not exist, creating..."
    ^mkdir -p $target_dir
    return true
  }
  
  if (directory_empty $target_dir) {
    print "Target directory is empty, copy needed"
    return true
  }
  
  let target_has_version = ($"($target_dir)/version.php" | path exists)
  let target_has_index = ($"($target_dir)/index.php" | path exists)
  
  if not ($target_has_version and $target_has_index) {
    print "Target directory missing critical Nextcloud files, copy needed"
    return true
  }
  
  print "Target directory already has Nextcloud files"
  return false
}

export def copy_source_to_html [user: string, group: string] {
  let source_dir = "/usr/src/nextcloud/"
  let target_dir = "/var/www/html/"
  
  if not ($source_dir | path exists) {
    print $"Error: Source directory does not exist: ($source_dir)"
    exit 1
  }
  
  if (directory_empty $source_dir) {
    print $"Error: Source directory is empty: ($source_dir)"
    exit 1
  }
  
  print $"Copying Nextcloud source from ($source_dir) to ($target_dir)"
  
  let uid = (^id -u | into int)
  
  let result = if $uid == 0 {
    ^rsync -rlDog --chown $"($user):($group)" $source_dir $target_dir | complete
  } else {
    ^rsync -rlD $source_dir $target_dir | complete
  }
  
  if $result.exit_code != 0 {
    print $"Error: rsync failed with exit code ($result.exit_code)"
    print $result.stderr
    exit 1
  }
  
  if (directory_empty $target_dir) {
    print $"Error: Target directory is empty after copy: ($target_dir)"
    exit 1
  }
  
  print "Source copy completed successfully"
}

export def prepare_directories [user: string, group: string] {
  let html_dir = "/var/www/html"
  let uid = (^id -u | into int)
  
  let data_dir = $"($html_dir)/data"
  if not ($data_dir | path exists) {
    print $"Creating data directory: ($data_dir)"
    ^mkdir -p $data_dir
    if $uid == 0 {
      ^chown $"($user):($group)" $data_dir
    }
  }
  
  let custom_apps_dir = $"($html_dir)/custom_apps"
  if not ($custom_apps_dir | path exists) {
    print $"Creating custom_apps directory: ($custom_apps_dir)"
    ^mkdir -p $custom_apps_dir
    if $uid == 0 {
      ^chown $"($user):($group)" $custom_apps_dir
    }
  }
  
  let occ_path = $"($html_dir)/occ"
  if ($occ_path | path exists) {
    print $"Setting occ executable: ($occ_path)"
    ^chmod +x $occ_path
  }
}

export def prepare_source [user: string, group: string] {
  if (detect_source_mount) {
    print "Detected mounted source at /usr/src/nextcloud"
    copy_source_to_html $user $group
  } else {
    print "Source already present in /var/www/html or no mount detected"
  }
  
  prepare_directories $user $group
}

# Merges apps from /usr/src/apps/ into /usr/src/nextcloud/apps/
# Uses apps/ instead of custom_apps/ so Nextcloud finds them before trying app store
# Skips apps that already exist in target (allows user Nextcloud source to include apps)
export def merge_apps [user: string, group: string] {
  let apps_dir = "/usr/src/apps"
  let nextcloud_apps_dir = "/usr/src/nextcloud/apps"

  if not ($apps_dir | path exists) {
    return
  }

  if not ($nextcloud_apps_dir | path exists) {
    print $"Creating apps directory: ($nextcloud_apps_dir)"
    ^mkdir -p $nextcloud_apps_dir
    let uid = (^id -u | into int)
    if $uid == 0 {
      ^chown $"($user):($group)" $nextcloud_apps_dir
    }
  }

  let apps = (ls $apps_dir | where type == dir)

  if ($apps | length) == 0 {
    return
  }

  for app in $apps {
    let app_name = ($app.name | path basename)
    let source_app_dir = $app.name
    let target_app_dir = $"($nextcloud_apps_dir)/($app_name)"

    if ($target_app_dir | path exists) {
      print $"Skipping ($app_name): already exists in Nextcloud apps"
      continue
    }

    let info_xml = $"($source_app_dir)/appinfo/info.xml"
    if not ($info_xml | path exists) {
      print $"Warning: Skipping ($app_name): missing appinfo/info.xml"
      continue
    }

    print $"Merging app: ($app_name)"
    ^cp -a $"($source_app_dir)/." $target_app_dir

    let uid = (^id -u | into int)
    if $uid == 0 {
      ^chown -R $"($user):($group)" $target_app_dir
    }
  }
}
