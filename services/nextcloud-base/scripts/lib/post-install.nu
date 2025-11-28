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
  
  # Step 6: Create and configure log files
  print "Setting up log files..."
  setup_log_files
  
  print "Custom post-installation logic completed"
}

# Setup log files with proper permissions
def setup_log_files [] {
  let apache_log_access = "/var/log/apache2/access.log"
  let apache_log_error = "/var/log/apache2/error.log"
  let nextcloud_log = "/var/www/html/data/nextcloud.log"
  
  # Remove old log files if they exist
  for log_file in [$apache_log_access, $apache_log_error, $nextcloud_log] {
    if ($log_file | path exists) {
      print $"Removing old log file: ($log_file)"
      ^rm -f $log_file
    }
  }
  
  # Create new empty log files
  print "Creating new log files..."
  ^touch $apache_log_access
  ^touch $apache_log_error
  ^touch $nextcloud_log
  
  # Set ownership and permissions (www-data:root with g=u)
  print "Setting log file permissions..."
  
  # Apache logs
  ^chown -R www-data:root /var/log/apache2
  ^chmod -R g=u /var/log/apache2
  
  # Nextcloud data directory (including logs)
  ^chown -R www-data:root /var/www/html/data
  ^chmod -R g=u /var/www/html/data
}
