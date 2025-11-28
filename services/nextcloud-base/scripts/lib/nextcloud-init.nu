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

# Nextcloud installation and upgrade logic

use ./utils.nu [run_as file_env directory_empty]

# Compare two version strings (semantic versioning)
# Returns true if version1 > version2
export def version_greater [version1: string, version2: string] {
  # Sort versions and check if first sorted version != version1
  # If version1 is greater, it won't be first after sorting
  let sorted = ([$version1, $version2] | sort -n)
  let first = ($sorted | first)
  $first != $version1
}

# Get installed Nextcloud version from /var/www/html/version.php
export def get_installed_version [] {
  let version_file = "/var/www/html/version.php"
  
  if not ($version_file | path exists) {
    return "0.0.0.0"
  }
  
  # Use PHP to extract version from version.php
  let result = (^php -r 'require "/var/www/html/version.php"; echo implode(".", $OC_Version);' | complete)
  
  if $result.exit_code == 0 {
    $result.stdout | str trim
  } else {
    "0.0.0.0"
  }
}

# Get image Nextcloud version from /usr/src/nextcloud/version.php
export def get_image_version [] {
  let version_file = "/usr/src/nextcloud/version.php"
  
  if not ($version_file | path exists) {
    print $"Error: Image version file not found: ($version_file)"
    exit 1
  }
  
  # Use PHP to extract version from version.php
  let result = (^php -r 'require "/usr/src/nextcloud/version.php"; echo implode(".", $OC_Version);' | complete)
  
  if $result.exit_code == 0 {
    $result.stdout | str trim
  } else {
    print "Error: Could not read image version"
    exit 1
  }
}

# Sync source files from /usr/src/nextcloud to /var/www/html
# Handles upgrade exclusions and selective directory syncing
export def sync_source [user: string, group: string] {
  let source_dir = "/usr/src/nextcloud/"
  let target_dir = "/var/www/html/"
  
  let uid = (^id -u | into int)
  let rsync_opts = if $uid == 0 {
    ["-rlDog" "--chown" $"($user):($group)"]
  } else {
    ["-rlD"]
  }
  
  print "Syncing Nextcloud source files..."
  
  # Main sync with exclusions
  ^rsync ...$rsync_opts --delete --exclude-from=/upgrade.exclude $source_dir $target_dir
  
  # Sync config, data, custom_apps, themes only if empty
  for dir in ["config", "data", "custom_apps", "themes"] {
    let target_path = $"($target_dir)($dir)"
    if not ($target_path | path exists) or (directory_empty $target_path) {
      print $"Syncing ($dir) directory..."
      ^rsync ...$rsync_opts --include $"/($dir)/" --exclude "/*" $source_dir $target_dir
    }
  }
  
  # Always sync version.php
  ^rsync ...$rsync_opts --include "/version.php" --exclude "/*" $source_dir $target_dir
}

# Install Nextcloud with provided admin credentials and database config
export def install_nextcloud [user: string] {
  print "New nextcloud instance"
  
  # Get admin credentials
  let admin_user = (file_env "NEXTCLOUD_ADMIN_USER" "")
  let admin_password = (file_env "NEXTCLOUD_ADMIN_PASSWORD" "")
  
  if $admin_user == "" or $admin_password == "" {
    print "Hint: You can specify NEXTCLOUD_ADMIN_USER and NEXTCLOUD_ADMIN_PASSWORD and the database variables prior to first launch to fully automate initial installation."
    return
  }
  
  mut install_options = ["-n" "--admin-user" $admin_user "--admin-pass" $admin_password]
  
  # Data directory
  let data_dir = (try { $env.NEXTCLOUD_DATA_DIR? } catch { null })
  if $data_dir != null {
    $install_options = ($install_options | append ["--data-dir" $data_dir])
  }
  
  # Database configuration
  mut install = false
  
  # Check SQLite
  let sqlite_db = (try { $env.SQLITE_DATABASE? } catch { null })
  if $sqlite_db != null {
    print "Installing with SQLite database"
    $install_options = ($install_options | append ["--database-name" $sqlite_db])
    $install = true
  }
  
  # Check MySQL
  let mysql_db = (file_env "MYSQL_DATABASE" "")
  let mysql_user = (file_env "MYSQL_USER" "")
  let mysql_password = (file_env "MYSQL_PASSWORD" "")
  let mysql_host = (try { $env.MYSQL_HOST? } catch { null })
  
  if $mysql_db != "" and $mysql_user != "" and $mysql_password != "" and $mysql_host != null {
    print "Installing with MySQL database"
    $install_options = ($install_options | append ["--database" "mysql" "--database-name" $mysql_db "--database-user" $mysql_user "--database-pass" $mysql_password "--database-host" $mysql_host])
    $install = true
  }
  
  # Check PostgreSQL
  let postgres_db = (file_env "POSTGRES_DB" "")
  let postgres_user = (file_env "POSTGRES_USER" "")
  let postgres_password = (file_env "POSTGRES_PASSWORD" "")
  let postgres_host = (try { $env.POSTGRES_HOST? } catch { null })
  
  if $postgres_db != "" and $postgres_user != "" and $postgres_password != "" and $postgres_host != null {
    print "Installing with PostgreSQL database"
    $install_options = ($install_options | append ["--database" "pgsql" "--database-name" $postgres_db "--database-user" $postgres_user "--database-pass" $postgres_password "--database-host" $postgres_host])
    $install = true
  }
  
  if not $install {
    print "Next step: Access your instance to finish the web-based installation!"
    return
  }
  
  # Build install command
  let install_cmd = (["php" "/var/www/html/occ" "maintenance:install"] | append $install_options | str join " ")
  
  print "Starting nextcloud installation"
  
  # Retry logic (max 10 attempts)
  mut try_count = 0
  let max_retries = 10
  mut success = false
  
  while $try_count <= $max_retries and (not $success) {
    let result = (run_as $user $install_cmd | complete)
    
    if $result.exit_code == 0 {
      $success = true
    } else {
      if $try_count < $max_retries {
        print "Retrying install..."
        $try_count = ($try_count + 1)
        sleep 10sec
      } else {
        print "Installing of nextcloud failed!"
        exit 1
      }
    }
  }
  
  # Set trusted domains
  let trusted_domains = (try { $env.NEXTCLOUD_TRUSTED_DOMAINS? } catch { null })
  if $trusted_domains != null {
    print "Setting trusted domains..."
    let domains = ($trusted_domains | split row " " | where $it != "")
    mut idx = 1
    for domain in $domains {
      let domain_trimmed = ($domain | str trim)
      run_as $user $"php /var/www/html/occ config:system:set trusted_domains ($idx) --value=\"($domain_trimmed)\""
      $idx = ($idx + 1)
    }
  }
}

# Upgrade Nextcloud to new version
export def upgrade_nextcloud [user: string] {
  print "Upgrading nextcloud..."
  
  # Save list of enabled apps before upgrade
  run_as $user "php /var/www/html/occ app:list" | ^sed -n "/Enabled:/,/Disabled:/p" | save -f /tmp/list_before
  
  # Run upgrade
  run_as $user "php /var/www/html/occ upgrade"
  
  # Save list of enabled apps after upgrade
  run_as $user "php /var/www/html/occ app:list" | ^sed -n "/Enabled:/,/Disabled:/p" | save -f /tmp/list_after
  
  # Compare and show disabled apps
  print "Checking for newly disabled apps..."
  let result = (^diff /tmp/list_before /tmp/list_after | complete)
  if $result.exit_code != 0 {
    print "Some apps were disabled during upgrade:"
    print $result.stdout
  }
}
