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

# Main entrypoint orchestrator for Nextcloud

use ./lib/utils.nu [detect_user_group run_as]
use ./lib/apache-config.nu [configure_apache]
use ./lib/redis-config.nu [configure_redis]
use ./lib/source-prep.nu [prepare_source, merge_apps]
use ./lib/nextcloud-init.nu [version_greater get_installed_version get_image_version sync_source install_nextcloud upgrade_nextcloud]
use ./lib/hooks.nu [run_path]
use ./lib/post-install.nu [run_custom_post_install, setup_log_files]
use ./lib/ca-bundle-sync.nu [sync-ca-bundle]

def main [...cmd_args: string] {
  print "Nextcloud entrypoint initialization started"
  
  if ($cmd_args | length) > 0 {
    configure_apache $cmd_args
  }
  
  # Only initialize for apache/php-fpm commands or when NEXTCLOUD_UPDATE=1
  let should_init = if ($cmd_args | length) > 0 {
    let first_cmd = ($cmd_args | first)
    ($first_cmd | str starts-with "apache") or ($first_cmd == "php-fpm")
  } else {
    false
  }
  
  let nextcloud_update = (try { ($env.NEXTCLOUD_UPDATE? | into int) } catch { 0 })
  
  if not ($should_init or ($nextcloud_update == 1)) {
    print "Skipping initialization (not apache/php-fpm and NEXTCLOUD_UPDATE not set)"
    return
  }
  
  let user_info = (detect_user_group)
  print $"Running as user: ($user_info.user) \(($user_info.uid)\), group: ($user_info.group) \(($user_info.gid)\)"
  
  configure_redis
  
  # Must read installed_version before copying files, otherwise version.php from source
  # will be detected and installation will be skipped
  let installed_version = (get_installed_version)
  let image_version = (get_image_version)
  
  prepare_source $user_info.user $user_info.group

  # Merge baked apps before sync_source copies to /var/www/html
  merge_apps $user_info.user $user_info.group
  
  print $"Installed version: ($installed_version)"
  print $"Image version: ($image_version)"
  
  if (version_greater $installed_version $image_version) {
    print $"Error: Can't start Nextcloud because the version of the data \(($installed_version)\) is higher than the docker image version \(($image_version)\) and downgrading is not supported."
    print "Are you sure you have pulled the newest image version?"
    exit 1
  }
  
  if (version_greater $image_version $installed_version) {
    print $"Initializing nextcloud ($image_version) ..."
    
    if $installed_version != "0.0.0.0" {
      let installed_major = ($installed_version | split row "." | first | into int)
      let image_major = ($image_version | split row "." | first | into int)
      
      if $image_major > ($installed_major + 1) {
        print $"Error: Can't start Nextcloud because upgrading from ($installed_version) to ($image_version) is not supported."
        print "It is only possible to upgrade one major version at a time."
        print $"For example, if you want to upgrade from version ($installed_major) to ($image_major), you will have to upgrade from version ($installed_major) to ($installed_major + 1), then from ($installed_major + 1) to ($image_major)."
        exit 1
      }
      
      print $"Upgrading nextcloud from ($installed_version) ..."
    }
    
    sync_source $user_info.user $user_info.group
    
    if $installed_version == "0.0.0.0" {
      run_path "pre-installation" $user_info.user
      install_nextcloud $user_info.user
      run_custom_post_install $user_info.user
      run_path "post-installation" $user_info.user
    } else {
      run_path "pre-upgrade" $user_info.user
      upgrade_nextcloud $user_info.user
      run_path "post-upgrade" $user_info.user
    }
  } else {
    print "Nextcloud is up to date"
  }
  
  let nextcloud_init_htaccess = (try { $env.NEXTCLOUD_INIT_HTACCESS? } catch { null })
  
  if $nextcloud_init_htaccess != null and $installed_version != "0.0.0.0" {
    print "Updating htaccess file..."
    run_as $user_info.user "php /var/www/html/occ maintenance:update:htaccess" | ignore
  }
  
  check_config_differences
  setup_log_files

  sync-ca-bundle

  run_path "before-starting" $user_info.user

  print "Nextcloud entrypoint initialization completed"
}

def check_config_differences [] {
  let source_config_dir = "/usr/src/nextcloud/config"
  let target_config_dir = "/var/www/html/config"
  
  if not ($source_config_dir | path exists) {
    return
  }
  
  let config_files = (ls $source_config_dir | where type == file and name =~ '\.php$')
  
  for file in $config_files {
    let filename = ($file.name | path basename)
    
    if $filename == "config.sample.php" or $filename == "autoconfig.php" {
      continue
    }
    
    let source_file = $"($source_config_dir)/($filename)"
    let target_file = $"($target_config_dir)/($filename)"
    
    if not ($target_file | path exists) {
      continue
    }
    
    let result = (^cmp -s $source_file $target_file | complete)
    
    if $result.exit_code != 0 {
      print $"Warning: ($target_file) differs from the latest version of this image at ($source_file)"
    }
  }
}
