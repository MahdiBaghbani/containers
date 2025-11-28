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

# Apache configuration for Nextcloud

# Configure Apache based on environment variables and command arguments
export def configure_apache [cmd_args: list<string>] {
  # Check if command starts with "apache"
  let cmd = ($cmd_args | first)
  
  if ($cmd | str starts-with "apache") {
    # Check for APACHE_DISABLE_REWRITE_IP environment variable
    let disable_rewrite = (try { $env.APACHE_DISABLE_REWRITE_IP? } catch { null })
    
    if $disable_rewrite != null {
      print "Disabling Apache remoteip module"
      ^a2disconf remoteip
    }
    
    # Set ServerName from environment variable if provided
    let server_name = (try { $env.APACHE_SERVER_NAME? } catch { null })
    
    if $server_name != null and ($server_name | str length) > 0 {
      print $"Setting Apache ServerName to: ($server_name)"
      $"ServerName ($server_name)" | save -f /etc/apache2/conf-available/servername.conf
    }
  }
}
