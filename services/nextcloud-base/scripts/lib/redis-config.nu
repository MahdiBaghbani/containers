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

# Redis session handler configuration

use ./utils.nu [file_env]

# Configure Redis as PHP session handler
# Supports Unix socket and TCP connections with authentication
export def configure_redis [] {
  # Check if REDIS_HOST is set
  let redis_host = (try { $env.REDIS_HOST? } catch { null })
  
  if $redis_host == null {
    return
  }
  
  print "Configuring Redis as session handler"
  
  # Get Redis credentials using file_env (Docker secrets support)
  let redis_password = (file_env "REDIS_HOST_PASSWORD" "")
  let redis_user = (file_env "REDIS_HOST_USER" "")
  
  # Build session save path
  mut save_path = ""
  
  # Check if Redis host is a Unix socket (starts with /)
  if ($redis_host | str starts-with "/") {
    # Unix socket path
    if $redis_password != "" {
      if $redis_user != "" {
        $save_path = $"unix://($redis_host)?auth[]=($redis_user)&auth[]=($redis_password)"
      } else {
        $save_path = $"unix://($redis_host)?auth=($redis_password)"
      }
    } else {
      $save_path = $"unix://($redis_host)"
    }
  } else {
    # TCP connection
    let redis_port = (try { $env.REDIS_HOST_PORT? } catch { "6379" })
    
    if $redis_password != "" {
      if $redis_user != "" {
        $save_path = $"tcp://($redis_host):($redis_port)?auth[]=($redis_user)&auth[]=($redis_password)"
      } else {
        $save_path = $"tcp://($redis_host):($redis_port)?auth=($redis_password)"
      }
    } else {
      $save_path = $"tcp://($redis_host):($redis_port)"
    }
  }
  
  # Generate PHP configuration
  let config = [
    "session.save_handler = redis"
    $"session.save_path = \"($save_path)\""
    "redis.session.locking_enabled = 1"
    "redis.session.lock_retries = -1"
    "redis.session.lock_wait_time = 10000"
  ]
  
  # Write configuration to PHP conf.d directory
  $config | str join "\n" | save -f /usr/local/etc/php/conf.d/redis-session.ini
}
