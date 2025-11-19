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

# Shared initialization functions used by all container modes

use ./utils.nu [replace_in_file, get_env_or_default]

# Constants
const REVAD_DIR = "/revad"
const REVAD_GIT_DIR = "/revad-git"
const CONFIG_DIR = "/configs/revad"
# REVAD_CONFIG_DIR is now configurable via REVAD_CONFIG_DIR environment variable (default: /etc/revad)
const TLS_DIR = "/tls"
const CERTS_DIR = "/certificates"
const CA_DIR = "/certificate-authority"

# Write nsswitch.conf file to enable DNS resolution
# Configures the Name Service Switch to use files first, then DNS
export def write_nsswitch [] {
  let content = "hosts: files dns\n"
  $content | save -f /etc/nsswitch.conf
}

# Ensure /etc/hosts file contains an entry for the domain
# Adds 127.0.0.1 mapping for the domain specified in DOMAIN environment variable
export def ensure_hosts [] {
  let domain = (get_env_or_default "DOMAIN" "")
  if ($domain | str length) == 0 {
    error make { msg: "Environment variable DOMAIN is required" }
  }
  let line = $"127.0.0.1 ($domain)\n"
  let content = (open /etc/hosts)
  ($content | append $line) | save -f /etc/hosts
}

# Ensure Reva log file exists at /var/log/revad.log
# Creates the file if it does not exist
export def ensure_logfile [] {
  touch /var/log/revad.log
}

# Create directory if it does not exist
# Uses mkdir -p to create parent directories as needed
export def create_directory [dir: string] {
  if not ($dir | path exists) {
    ^mkdir -p $dir
  }
}

# Copy all JSON files from config source directory to runtime config directory
# This ensures JSON data files (users, groups, providers, etc.) are available to Reva
export def copy_json_files [source_dir: string, dest_dir: string] {
  if not ($source_dir | path exists) {
    return  # Source directory doesn't exist, skip silently
  }
  
  # Find all JSON files in source directory
  let json_files = (try {
    ls $source_dir | where {|row| $row.name | str ends-with ".json"} | get name
  } catch {
    []
  })
  
  if ($json_files | is-empty) {
    return  # No JSON files found, skip silently
  }
  
  let file_count = ($json_files | length)
  let file_word = (if $file_count == 1 { "file" } else { "files" })
  print $"Copying ($file_count) JSON ($file_word) to runtime config directory..."
  for json_file in $json_files {
    # json_file might be a full path or just filename - extract just the filename
    let filename = ($json_file | path basename)
    let source_path = $"($source_dir)/($filename)"
    let dest_path = $"($dest_dir)/($filename)"
    if ($source_path | path exists) {
      ^cp $source_path $dest_path
      print $"  Copied: ($filename)"
    }
  }
}

# Copy Reva binaries from git directory to /revad if /revad is empty
# This is used during development when binaries are built from source
export def populate_reva_binaries [] {
  if not ($REVAD_DIR | path exists) { error make {msg: $"($REVAD_DIR) does not exist"} }
  let has_files = (not ((ls -a $REVAD_DIR | where {|row| $row.name != "." and $row.name != ".."} | is-empty)))
  if not $has_files {
    print "/revad is empty, populating with reva binaries..."
    cp -r $"($REVAD_GIT_DIR)/cmd" $REVAD_DIR
  } else {
    ls -lsa $REVAD_DIR | to text | print $in
    print "/revad contains files, skipping populate"
  }
}

# Remove configuration files listed in DISABLED_CONFIGS environment variable
# Files are specified as space-separated list of filenames (e.g., "config1.toml config2.toml")
export def disable_config_files [] {
  let disabled_configs = (get_env_or_default "DISABLED_CONFIGS" "")
  if ($disabled_configs | str length) == 0 { return }
  # Get config directory from environment (default: /etc/revad)
  let revad_config_dir = (get_env_or_default "REVAD_CONFIG_DIR" "/etc/revad")
  print "Disabling specified configuration files..."
  for config in ($disabled_configs | split row " ") {
    let p = $"($revad_config_dir)/($config)"
    if ($p | path exists) { rm -f $p }
  }
}

# Setup TLS certificates and CA trust store
# See docs/concepts/tls-management.md for details
export def prepare_tls_certificates [] {
  let revad_tls_enabled = (get_env_or_default "REVAD_TLS_ENABLED" "false")
  if $revad_tls_enabled == "false" {
    print "TLS disabled (REVAD_TLS_ENABLED=false) - skipping certificate setup"
    return
  }
  
  let domain = (get_env_or_default "DOMAIN" "")
  if ($domain | str length) == 0 { 
    error make { msg: "Environment variable DOMAIN is required when REVAD_TLS_ENABLED=true" } 
  }
  
  let revad_host = (get_env_or_default "REVAD_HOST" $domain)
  
  create_directory $TLS_DIR
  if ($CERTS_DIR | path exists) {
    (ls $CERTS_DIR | where {|row| $row.name =~ ".*\\.(crt|key)$"} | get name | each {|n| cp -f $"($CERTS_DIR)/($n)" $TLS_DIR } ) | ignore
  }
  if ($CA_DIR | path exists) {
    (ls $CA_DIR | where {|row| $row.name =~ ".*\\.(crt|key)$"} | get name | each {|n| cp -f $"($CA_DIR)/($n)" $TLS_DIR } ) | ignore
  }
  (ls $TLS_DIR | where {|row| $row.name =~ ".*\\.crt$"} | get name | each {|n| cp -f $"($TLS_DIR)/($n)" "/usr/local/share/ca-certificates/" } ) | ignore
  ^update-ca-certificates | ignore
  
  # Certificate selection priority: REVAD_HOST hostname > DOMAIN hostname > reva.crt > server.crt
  # Extract hostname part (first component before dot) for certificate matching
  let revad_hostpart = (if ($revad_host | str length) > 0 { ($revad_host | split row "." | get 0) } else { "" })
  let domain_hostpart = ($domain | split row "." | get 0)
  let cert_src = (if ($revad_hostpart | str length) > 0 and ($"($TLS_DIR)/($revad_hostpart).crt" | path exists) {
    $"($TLS_DIR)/($revad_hostpart).crt"
  } else if ($"($TLS_DIR)/($domain_hostpart).crt" | path exists) {
    $"($TLS_DIR)/($domain_hostpart).crt"
  } else if ($"($TLS_DIR)/reva.crt" | path exists) {
    $"($TLS_DIR)/reva.crt"
  } else {
    $"($TLS_DIR)/server.crt"
  })
  
  let key_src = (if ($revad_hostpart | str length) > 0 and ($"($TLS_DIR)/($revad_hostpart).key" | path exists) {
    $"($TLS_DIR)/($revad_hostpart).key"
  } else if ($"($TLS_DIR)/($domain_hostpart).key" | path exists) {
    $"($TLS_DIR)/($domain_hostpart).key"
  } else if ($"($TLS_DIR)/reva.key" | path exists) {
    $"($TLS_DIR)/reva.key"
  } else {
    $"($TLS_DIR)/server.key"
  })
  
  if not ($cert_src | path exists) { error make { msg: "REVAD_TLS_ENABLED=true but certificate not found in /tls" } }
  if not ($key_src | path exists) { error make { msg: "REVAD_TLS_ENABLED=true but key not found in /tls" } }

  # Create symlinks to server.crt/server.key for Reva to find certificates
  let server_crt_path = $"($TLS_DIR)/server.crt"
  let server_key_path = $"($TLS_DIR)/server.key"
  
  if $cert_src != $server_crt_path {
    ln -sf $cert_src $server_crt_path
  }
  if $key_src != $server_key_path {
    ln -sf $key_src $server_key_path
  }
}

# Start Reva daemon with specific config file
# Uses -c flag to load only the specified config file (not all configs in directory)
export def start_reva_daemon [config_file: string] {
  let found = (not ((which revad | is-empty)))
  if not $found { 
    error make {msg: "revad not found in PATH"} 
  }
  
  # Get config directory from environment (default: /etc/revad)
  let revad_config_dir = (get_env_or_default "REVAD_CONFIG_DIR" "/etc/revad")
  
  let config_path = $"($revad_config_dir)/($config_file)"
  if not ($config_path | path exists) {
    error make {msg: $"Config file not found: ($config_path)"}
  }
  
  print $"Starting Reva daemon with config: ($config_file)..."
  # Start revad in background with specific config file (matches production Dockerfile.revad pattern)
  # Redirect stderr to stdout and both to log file so we can see errors via tail
  # The process will be reparented to PID 1 when Nushell exits, keeping it running
  let log_output = (get_env_or_default "REVAD_LOG_OUTPUT" "/var/log/revad.log")
  # Use sh -c to handle shell redirection for background process
  ^sh -c $"revad -c ($config_path) >> ($log_output) 2>&1 &"
  
  # Wait a moment for revad to start
  sleep 0.5sec
  
  print $"Reva daemon started in background. Check logs at ($log_output)"
}

# Shared initialization function - processes common setup tasks for all container modes
# Sets up DNS resolution, hosts file, log files, directories, binaries, and TLS certificates
export def init_shared [] {
  write_nsswitch
  ensure_hosts
  ensure_logfile
  create_directory $REVAD_DIR
  populate_reva_binaries
  # Get config directory from environment (default: /etc/revad)
  let revad_config_dir = (get_env_or_default "REVAD_CONFIG_DIR" "/etc/revad")
  create_directory $revad_config_dir
  prepare_tls_certificates
}
