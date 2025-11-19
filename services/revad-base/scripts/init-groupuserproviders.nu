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

# User/Group providers-specific initialization script
# Processes user/group providers configuration file (userprovider, groupprovider)

use ./lib/shared.nu [create_directory, disable_config_files, copy_json_files]
use ./lib/utils.nu [replace_in_file, get_env_or_default, process_placeholders]

const CONFIG_DIR = "/configs/revad"

# Initialize user/group providers configuration
# Copies config template, processes placeholders, and sets up TLS based on environment
# Preserves existing config files to allow user modifications
export def init_groupuserproviders [] {
  print "Initializing user/group providers configuration..."
  
  # Get config directory from environment (default: /etc/revad)
  let revad_config_dir = (get_env_or_default "REVAD_CONFIG_DIR" "/etc/revad")
  
  if not ($CONFIG_DIR | path exists) { 
    error make {msg: $"Config dir not found: ($CONFIG_DIR)"} 
  }
  
  create_directory $revad_config_dir
  
  # Determine config file name
  let config_file = "cernbox-groupuserproviders.toml"
  let config_path = $"($revad_config_dir)/($config_file)"
  
  # Check if config already exists
  let has_config = ($config_path | path exists)
  
  if not $has_config {
    print $"User/group providers config not found - copying and templating from image..."
    
    # Copy user/group providers config template
    let source_config = $"($CONFIG_DIR)/($config_file)"
    if not ($source_config | path exists) {
      error make { msg: $"User/group providers config template not found: ($source_config)" }
    }
    ^cp $source_config $config_path
    
    # Copy all JSON files (users, groups, providers, etc.) if needed by user/group providers config
    copy_json_files $CONFIG_DIR $revad_config_dir
  } else {
    print $"User/group providers config found - will process placeholders..."
  }
  
  # Always process placeholders, even if config exists
  # This ensures placeholders are replaced even if previous run was incomplete
  # Get environment variables with defaults
  let domain = (get_env_or_default "DOMAIN" "")
  if ($domain | str length) == 0 {
    error make { msg: "Environment variable DOMAIN is required" }
  }
  
  # Get groupuserproviders-specific environment variables
  # Defaults match CERN production pattern (9145) for easier debugging
  let groupuserproviders_host = (get_env_or_default "REVAD_GROUPUSERPROVIDERS_HOST" "cernbox-1-test-revad-groupuserproviders")
  let groupuserproviders_grpc_port = (get_env_or_default "REVAD_GROUPUSERPROVIDERS_GRPC_PORT" "9145")
  
  # Get gateway address for gRPC communication
  # User/group providers need to communicate with gateway via gRPC
  # Default matches CERN production pattern (9142) for easier debugging
  let gateway_host = (get_env_or_default "REVAD_GATEWAY_HOST" "cernbox-1-test-revad-gateway")
  let gateway_grpc_port = (get_env_or_default "REVAD_GATEWAY_GRPC_PORT" "9142")
  let gateway_svc = $"($gateway_host):($gateway_grpc_port)"
  
  # Get shared configuration variables
  let log_level = (get_env_or_default "REVAD_LOG_LEVEL" "debug")
  let log_output = (get_env_or_default "REVAD_LOG_OUTPUT" "/var/log/revad.log")
  let jwt_secret = (get_env_or_default "REVAD_JWT_SECRET" "reva-secret")
  
  # Build placeholder map
  mut placeholder_map = {
    "log-level": $log_level
    "log-output": $log_output
    "jwt-secret": $jwt_secret
    "gateway-svc": $gateway_svc
    "grpc-address": $":($groupuserproviders_grpc_port)"
    "config-dir": $revad_config_dir
  }
  
  # Process all placeholders in the config file using the placeholder map
  # Always process placeholders to ensure they're replaced even if file exists
  process_placeholders $config_path $placeholder_map
  
  # Disable TLS certificate configuration in HTTP mode
  # Comment out certfile and keyfile lines when TLS is disabled
  let revad_tls_enabled = (get_env_or_default "REVAD_TLS_ENABLED" "false")
  if $revad_tls_enabled == "false" {
    replace_in_file $config_path 'certfile = "/tls/server.crt"' '# certfile disabled - HTTP mode'
    replace_in_file $config_path 'keyfile = "/tls/server.key"' '# keyfile disabled - HTTP mode'
  }
  
  # Remove any config files listed in DISABLED_CONFIGS
  disable_config_files
  print "User/group providers configuration initialized"
}
