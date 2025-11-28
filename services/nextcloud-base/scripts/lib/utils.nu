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

# Utility functions for Nextcloud container initialization

# Detect user/group for container execution
# Handles www-data for root, current user for non-root
# Supports Apache user/group environment variables
export def detect_user_group [] {
  let uid = (^id -u | into int)
  let gid = (^id -g | into int)
  
  mut user = ""
  mut group = ""
  
  if $uid == 0 {
    # Root user - use Apache environment variables or default to www-data
    let apache_user = (try { $env.APACHE_RUN_USER? } catch { "www-data" })
    let apache_group = (try { $env.APACHE_RUN_GROUP? } catch { "www-data" })
    
    # Strip '#' prefix from user/group (Apache syntax support)
    $user = ($apache_user | str replace --regex "^#" "")
    $group = ($apache_group | str replace --regex "^#" "")
  } else {
    # Non-root user - use current UID/GID
    $user = ($uid | into string)
    $group = ($gid | into string)
  }
  
  {
    user: $user,
    group: $group,
    uid: $uid,
    gid: $gid
  }
}

# Execute command as specified user
# If root: uses su to switch user, if non-root: runs directly
export def run_as [user: string, command: string] {
  let uid = (^id -u | into int)
  
  if $uid == 0 {
    # Root - switch user with su
    ^su -p $user -s /bin/sh -c $command
  } else {
    # Non-root - execute directly
    ^sh -c $command
  }
}

# Check if directory is empty
export def directory_empty [dir: string] {
  if not ($dir | path exists) {
    return true
  }
  
  let contents = (ls -a $dir | where name != $"($dir)/." and name != $"($dir)/..")
  ($contents | length) == 0
}

# Get environment variable with Docker secrets support
# Supports ${VAR}_FILE pattern for reading secrets from files
# Priority: VAR_FILE (read from file) > VAR (direct value) > default
export def file_env [var_name: string, default: string = ""] {
  let file_var_name = $"($var_name)_FILE"
  
  # Get both variable values
  let var_value = (try { $env | get $var_name } catch { null })
  let file_var_value = (try { $env | get $file_var_name } catch { null })
  
  # Check for conflict - both set is an error
  if $var_value != null and $file_var_value != null {
    print $"error: both ($var_name) and ($file_var_name) are set \(but are exclusive\)"
    exit 1
  }
  
  # Return value based on priority
  if $var_value != null {
    $var_value
  } else if $file_var_value != null {
    # Read from file
    open --raw $file_var_value | str trim
  } else {
    $default
  }
}

# Get environment variable or return default value
# Safe wrapper for environment variable access
export def get_env_or_default [var_name: string, default: string = ""] {
  (try { $env | get $var_name } catch { $default })
}
