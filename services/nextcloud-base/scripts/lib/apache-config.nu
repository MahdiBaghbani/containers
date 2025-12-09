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
    
    # Configure HTTPS modes
    configure_https_mode
  }
}

# Configure HTTPS mode based on NEXTCLOUD_HTTPS_MODE environment variable
def configure_https_mode [] {
  # Read NEXTCLOUD_HTTPS_MODE, default to "off"
  let https_mode = (try { $env.NEXTCLOUD_HTTPS_MODE? } catch { null })
  let mode = if $https_mode == null {
    "off"
  } else {
    $https_mode | str trim | str downcase
  }
  
  # Validate mode
  let valid_modes = ["off", "https-only", "http-and-https"]
  if not ($mode in $valid_modes) {
    print $"Warning: Unknown NEXTCLOUD_HTTPS_MODE value '($https_mode)', treating as 'off'"
    let mode = "off"
  }
  
  print $"Configuring Apache HTTPS mode: ($mode)"
  
  # Disable default Apache sites
  print "Disabling default Apache sites"
  try {
    ^a2dissite 000-default 2>/dev/null | complete | ignore
  } catch { }
  try {
    ^a2dissite default-ssl 2>/dev/null | complete | ignore
  } catch { }
  
  # Configure based on mode
  if $mode == "off" {
    # HTTP-only: disable HTTPS site, enable HTTP site
    print "Enabling HTTP-only mode"
    try {
      ^a2dissite nextcloud-https 2>/dev/null | complete | ignore
    } catch { }
    try {
      ^a2ensite nextcloud-http | complete | ignore
    } catch { |err|
      print $"Error enabling nextcloud-http: ($err)"
      exit 1
    }
    # Remove redirect from HTTP vhost if present
    remove_http_redirect
  } else if $mode == "https-only" {
    # HTTPS-only: enable HTTPS site, enable HTTP site with redirect
    print "Enabling HTTPS-only mode"
    try {
      ^a2ensite nextcloud-https | complete | ignore
    } catch { |err|
      print $"Error enabling nextcloud-https: ($err)"
      exit 1
    }
    try {
      ^a2ensite nextcloud-http | complete | ignore
    } catch { |err|
      print $"Error enabling nextcloud-http: ($err)"
      exit 1
    }
    # Add redirect to HTTP vhost
    add_http_redirect
  } else if $mode == "http-and-https" {
    # Both HTTP and HTTPS: enable both sites, no redirect
    print "Enabling HTTP and HTTPS mode"
    try {
      ^a2ensite nextcloud-https | complete | ignore
    } catch { |err|
      print $"Error enabling nextcloud-https: ($err)"
      exit 1
    }
    try {
      ^a2ensite nextcloud-http | complete | ignore
    } catch { |err|
      print $"Error enabling nextcloud-http: ($err)"
      exit 1
    }
    # Remove redirect from HTTP vhost if present
    remove_http_redirect
  }
  
  # Run Apache configtest
  let configtest = (^apachectl configtest | complete)
  if $configtest.exit_code != 0 {
    let stderr_msg = (try { $configtest.stderr } catch { "Unknown error" })
    print $"Warning: Apache configuration test failed: ($stderr_msg)"
  } else {
    print "Apache configuration test passed"
  }
}

# Add redirect rule to HTTP vhost for https-only mode using mod_rewrite
def add_http_redirect [] {
  let http_conf = "/etc/apache2/sites-available/nextcloud-http.conf"
  if not ($http_conf | path exists) {
    return
  }
  
  let content = (open $http_conf)
  # Check if redirect already exists
  if ($content | str contains "RewriteEngine on") {
    return
  }
  
  # Add RewriteEngine and redirect rule after DocumentRoot line
  let lines = ($content | lines)
  mut new_lines = []
  mut redirect_added = false
  
  for line in $lines {
    $new_lines = ($new_lines | append $line)
    if ($line | str contains "DocumentRoot") and (not $redirect_added) {
      $new_lines = ($new_lines | append "")
      $new_lines = ($new_lines | append "    RewriteEngine on")
      $new_lines = ($new_lines | append "    RewriteCond %{HTTPS} off")
      $new_lines = ($new_lines | append "    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]")
      $redirect_added = true
    }
  }
  
  ($new_lines | str join "\n") | save -f $http_conf
  print "Added redirect rule to HTTP vhost"
}

# Remove redirect rule from HTTP vhost
def remove_http_redirect [] {
  let http_conf = "/etc/apache2/sites-available/nextcloud-http.conf"
  if not ($http_conf | path exists) {
    return
  }
  
  let content = (open $http_conf)
  # Check if redirect exists
  if not ($content | str contains "RewriteEngine on") {
    return
  }
  
  # Remove redirect lines (RewriteEngine, RewriteCond, RewriteRule)
  let lines = ($content | lines)
  mut new_lines = []
  mut skip_next = false
  
  for line in $lines {
    if ($line | str contains "RewriteEngine on") {
      $skip_next = true
      continue
    } else if $skip_next and (($line | str contains "RewriteCond") or ($line | str contains "RewriteRule")) {
      continue
    } else {
      $skip_next = false
      $new_lines = ($new_lines | append $line)
    }
  }
  
  ($new_lines | str join "\n") | save -f $http_conf
  print "Removed redirect rule from HTTP vhost"
}
