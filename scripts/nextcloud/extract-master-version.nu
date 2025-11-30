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

# Extract Nextcloud master version from GitHub and update versions.nuon
# Fetches version.php from master branch, parses version, and updates manifest

def main [] {
  print "Fetching Nextcloud master version from GitHub..."
  
  # Step 1: Fetch version.php from GitHub
  let version_url = "https://raw.githubusercontent.com/nextcloud/server/master/version.php"
  
  let result = (http get $version_url | complete)
  
  if $result.exit_code != 0 {
    print $"Error: Failed to fetch version.php from GitHub: ($result.stderr)"
    exit 1
  }
  
  let version_php = $result.stdout
  
  # Step 2: Parse version from PHP file
  # Look for $OC_Version = array(31, 0, 0, 5);
  let version = (parse_version $version_php)
  
  if $version == null {
    print "Error: Could not parse version from version.php"
    print "Expected format: $OC_Version = array(...);"
    exit 1
  }
  
  print $"Extracted version: ($version)"
  
  # Step 3: Update versions.nuon manifest
  let manifest_path = "services/nextcloud/versions.nuon"
  
  if not ($manifest_path | path exists) {
    print $"Error: Manifest file not found: ($manifest_path)"
    exit 1
  }
  
  # Read and parse current manifest
  let manifest = (open $manifest_path)
  
  # Find master version entry
  let master_version = ($manifest.versions | where name == "master" | first)
  
  if ($master_version | length) == 0 {
    print "Error: Master version entry not found in manifest"
    exit 1
  }
  
  # Get current version from master overrides
  let current_ref = (try {
    $master_version.overrides.sources.nextcloud.ref
  } catch {
    "master"
  })
  
  # Check if version changed
  if $current_ref == $version {
    print $"Master version is already up to date: ($version)"
    return
  }
  
  print $"WARNING: Master version changed from ($current_ref) to ($version)"
  print "Updating versions.nuon manifest..."
  
  # Update manifest
  let updated_versions = ($manifest.versions | each {|v|
    if $v.name == "master" {
      $v | upsert overrides.sources.nextcloud.ref $version
    } else {
      $v
    }
  })
  
  let updated_manifest = ($manifest | upsert versions $updated_versions)
  
  # Write updated manifest
  $updated_manifest | save -f $manifest_path
  
  print $"Successfully updated manifest: ($manifest_path)"
  print $"Master version is now: ($version)"
}

# Parse version from version.php content
# Extracts $OC_Version array and converts to dotted version string
def parse_version [content: string] {
  # Look for $OC_Version = array(...);
  # Example: $OC_Version = array(31, 0, 0, 5);
  
  # Find the line with $OC_Version
  let oc_version_line = ($content | lines | where $it =~ '\$OC_Version' | first)
  
  if ($oc_version_line | length) == 0 {
    return null
  }
  
  # Extract the array contents
  # Pattern: $OC_Version = array(31, 0, 0, 5);
  # Extract what's between array( and );
  
  let array_start = ($oc_version_line | str index-of "array(")
  if $array_start < 0 {
    return null
  }
  
  let array_end = ($oc_version_line | str index-of ");")
  if $array_end < 0 {
    return null
  }
  
  # Extract the content between array( and )
  let array_content_start = ($array_start + 6)  # length of "array("
  let array_content = ($oc_version_line | str substring $array_content_start..$array_end | str trim)
  
  # Split by comma and trim whitespace
  let version_parts = ($array_content | split row "," | each {|p| $p | str trim})
  
  # Convert to version string
  let version = ($version_parts | str join ".")
  
  # Add 'v' prefix
  $"v($version)"
}
