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

# Custom post-installation logic for Open Cloud Mesh

use ./utils.nu [run_as]

# Run custom post-installation operations
# Includes database indices, maintenance repair, config modifications, log setup
export def run_custom_post_install [user: string] {
  print "Running custom post-installation logic..."
  
  # Step 1: Add missing database indices
  print "Adding missing database indices..."
  run_as $user "php /var/www/html/occ db:add-missing-indices"
  
  # Step 2: Run maintenance repair with expensive operations
  print "Running maintenance repair (with expensive operations)..."
  run_as $user "php /var/www/html/occ maintenance:repair --include-expensive"
  
  # Step 3: Set maintenance window start time
  print "Setting maintenance window start time..."
  run_as $user "php /var/www/html/occ config:system:set maintenance_window_start --type=integer --value=1"
  
  # Step 4: Add allow_local_remote_servers to config.php
  print "Configuring allow_local_remote_servers..."
  let config_file = "/var/www/html/config/config.php"
  
  if ($config_file | path exists) {
    # Use sed to insert the line after line 2 (after the opening php tag and array start)
    ^sed -i "3 i\\  'allow_local_remote_servers' => true," $config_file
  } else {
    print $"Warning: Config file not found: ($config_file)"
  }
  
  # Step 5: Disable firstrunwizard app
  # Note: Legacy script uses console.php, which might be an alias for occ
  print "Disabling firstrunwizard app..."
  let result = (run_as $user "php /var/www/html/occ app:disable firstrunwizard" | complete)
  
  if $result.exit_code != 0 {
    print "Note: firstrunwizard app disable returned non-zero exit code (may already be disabled)"
  }
  
  # Step 6: Set admin user email (required for OCM invite acceptance)
  print "Setting admin user email..."
  set_admin_email $user
  
  # Step 7: Create and configure log files
  print "Setting up log files..."
  setup_log_files
  
  print "Custom post-installation logic completed"
}

# Set admin user email address
# Uses NEXTCLOUD_ADMIN_EMAIL env var, or constructs from admin user and trusted domain
export def set_admin_email [user: string] {
  # Get admin username from env
  let admin_user = (try { $env.NEXTCLOUD_ADMIN_USER? } catch { "admin" })
  
  # Check for explicit admin email env var
  let admin_email = (try { $env.NEXTCLOUD_ADMIN_EMAIL? } catch { null })
  
  mut email_to_set = ""
  
  if $admin_email != null and $admin_email != "" {
    $email_to_set = $admin_email
  } else {
    # Construct email from admin user and first trusted domain
    let trusted_domains = (try { $env.NEXTCLOUD_TRUSTED_DOMAINS? } catch { null })
    if $trusted_domains != null and $trusted_domains != "" {
      let first_domain = ($trusted_domains | split row " " | where $it != "" | first)
      $email_to_set = $"($admin_user)@($first_domain)"
    } else {
      # Fallback to localhost
      $email_to_set = $"($admin_user)@localhost"
    }
  }
  
  print $"Setting admin email to: ($email_to_set)"
  let result = (run_as $user $"php /var/www/html/occ user:setting ($admin_user) settings email ($email_to_set)" | complete)
  
  if $result.exit_code != 0 {
    print $"Warning: Failed to set admin email: ($result.stderr)"
  } else {
    print "Admin email set successfully"
  }
}

# Setup log files with proper permissions
# Only removes logs on first install, preserves on subsequent starts
export def setup_log_files [] {
  let apache_log_access = "/var/log/apache2/access.log"
  let apache_log_error = "/var/log/apache2/error.log"
  let nextcloud_log = "/var/www/html/data/nextcloud.log"

  # Check if this is first install (config.php doesn't exist)
  let is_first_install = not ("/var/www/html/config/config.php" | path exists)

  if $is_first_install {
    # First install: remove old log files if they exist
    for log_file in [$apache_log_access, $apache_log_error, $nextcloud_log] {
      if ($log_file | path exists) {
        print $"Removing old log file: ($log_file)"
        ^rm -f $log_file
      }
    }
  } else {
    # Subsequent start: preserve logs, only create if missing
    print "Preserving existing log files (not first install)"
  }

  # Create log files if they don't exist
  for log_file in [$apache_log_access, $apache_log_error, $nextcloud_log] {
    if not ($log_file | path exists) {
      print $"Creating log file: ($log_file)"
      ^touch $log_file
    }
  }

  # Set ownership and permissions (www-data:root with g=u)
  print "Setting log file permissions..."

  # Apache logs
  ^chown -R www-data:root /var/log/apache2
  ^chmod -R g=u /var/log/apache2

  # Nextcloud data directory (including logs)
  ^chown -R www-data:root /var/www/html/data
  ^chmod -R g=u /var/www/html/data
}
