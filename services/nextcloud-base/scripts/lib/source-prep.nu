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

# Source preparation and copy-on-write for Nextcloud

use ./utils.nu [directory_empty]

# Detect if /usr/src/nextcloud is mounted and needs copying
# Returns true if source should be copied to target
export def detect_source_mount [] {
  let source_dir = "/usr/src/nextcloud"
  let target_dir = "/var/www/html"
  
  # Check if source directory exists and is populated
  if not ($source_dir | path exists) {
    print "Source directory does not exist, skipping mount detection"
    return false
  }
  
  # Check if source directory is readable
  let source_readable = (^test -r $source_dir | complete | get exit_code) == 0
  if not $source_readable {
    print "Warning: Source directory is not readable"
    return false
  }
  
  # Check for key Nextcloud files in source (more comprehensive)
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
  
  # Check if target directory exists
  if not ($target_dir | path exists) {
    print "Target directory does not exist, creating..."
    ^mkdir -p $target_dir
    return true
  }
  
  # Check if target is empty or missing Nextcloud files
  if (directory_empty $target_dir) {
    print "Target directory is empty, copy needed"
    return true
  }
  
  # Check for critical Nextcloud files in target
  let target_has_version = ($"($target_dir)/version.php" | path exists)
  let target_has_index = ($"($target_dir)/index.php" | path exists)
  
  if not ($target_has_version and $target_has_index) {
    print "Target directory missing critical Nextcloud files, copy needed"
    return true
  }
  
  print "Target directory already has Nextcloud files"
  return false
}

# Copy source from /usr/src/nextcloud to /var/www/html using rsync
# Handles both root and non-root execution with error handling
export def copy_source_to_html [user: string, group: string] {
  let source_dir = "/usr/src/nextcloud/"
  let target_dir = "/var/www/html/"
  
  # Verify source directory is readable
  if not ($source_dir | path exists) {
    print $"Error: Source directory does not exist: ($source_dir)"
    exit 1
  }
  
  # Check if source directory is empty
  if (directory_empty $source_dir) {
    print $"Error: Source directory is empty: ($source_dir)"
    exit 1
  }
  
  print $"Copying Nextcloud source from ($source_dir) to ($target_dir)"
  
  let uid = (^id -u | into int)
  
  # Execute rsync with appropriate options
  let result = if $uid == 0 {
    # Root - use rsync with chown
    ^rsync -rlDog --chown $"($user):($group)" $source_dir $target_dir | complete
  } else {
    # Non-root - rsync without chown
    ^rsync -rlD $source_dir $target_dir | complete
  }
  
  # Check rsync exit code
  if $result.exit_code != 0 {
    print $"Error: rsync failed with exit code ($result.exit_code)"
    print $result.stderr
    exit 1
  }
  
  # Verify target directory now has content
  if (directory_empty $target_dir) {
    print $"Error: Target directory is empty after copy: ($target_dir)"
    exit 1
  }
  
  print "Source copy completed successfully"
}

# Prepare directories and permissions after source copy
# Creates data and custom_apps directories, sets occ executable
export def prepare_directories [] {
  let html_dir = "/var/www/html"
  
  # Create data directory
  let data_dir = $"($html_dir)/data"
  if not ($data_dir | path exists) {
    print $"Creating data directory: ($data_dir)"
    ^mkdir -p $data_dir
  }
  
  # Create custom_apps directory
  let custom_apps_dir = $"($html_dir)/custom_apps"
  if not ($custom_apps_dir | path exists) {
    print $"Creating custom_apps directory: ($custom_apps_dir)"
    ^mkdir -p $custom_apps_dir
  }
  
  # Make occ executable
  let occ_path = $"($html_dir)/occ"
  if ($occ_path | path exists) {
    print $"Setting occ executable: ($occ_path)"
    ^chmod +x $occ_path
  }
}

# Orchestrate all source preparation steps
# Main entry point for source preparation module
export def prepare_source [user: string, group: string] {
  # Check if source mount needs to be copied
  if (detect_source_mount) {
    print "Detected mounted source at /usr/src/nextcloud"
    copy_source_to_html $user $group
  } else {
    print "Source already present in /var/www/html or no mount detected"
  }
  
  # Always prepare directories (idempotent)
  prepare_directories
}
