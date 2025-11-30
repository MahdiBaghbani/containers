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

# Auth provider-specific initialization script
# Processes auth provider configuration file based on type (oidc, machine, ocmshares, publicshares)

use ./lib/shared.nu [create_directory, disable_config_files, copy_json_files]
use ./lib/utils.nu [replace_in_file, get_env_or_default, process_placeholders]
use ./lib/merge-partials.nu [merge_partial_configs]

const CONFIG_DIR = "/configs/revad"

# Initialize auth provider configuration for the specified type
# Copies config template, processes placeholders, and sets up TLS based on environment
# Preserves existing config files to allow user modifications
export def init_authprovider [authprovider_type: string] {
  print $"Initializing authprovider configuration for type: ($authprovider_type)"
  
  # Validate that authprovider type is one of the supported types
  let valid_types = ["oidc", "machine", "ocmshares", "publicshares"]
  if not ($authprovider_type in $valid_types) {
    let valid_types_str = ($valid_types | str join ", ")
    error make { msg: $"Invalid authprovider type: ($authprovider_type). Valid types: ($valid_types_str)" }
  }
  
  # Get config directory from environment (default: /etc/revad)
  let revad_config_dir = (get_env_or_default "REVAD_CONFIG_DIR" "/etc/revad")
  
  if not ($CONFIG_DIR | path exists) { 
    error make {msg: $"Config dir not found: ($CONFIG_DIR)"} 
  }
  
  create_directory $revad_config_dir
  
  # Determine config file name
  let config_file = $"authprovider-($authprovider_type).toml"
  let config_path = $"($revad_config_dir)/($config_file)"
  
  # Check if config already exists
  let has_config = ($config_path | path exists)
  
  if not $has_config {
    print $"Authprovider config not found - copying and templating from image..."
    
    # Copy authprovider config template
    let source_config = $"($CONFIG_DIR)/($config_file)"
    if not ($source_config | path exists) {
      error make { msg: $"Authprovider config template not found: ($source_config)" }
    }
    ^cp $source_config $config_path
    
    # Copy all JSON files (users, groups, providers, etc.) if needed by authprovider config
    copy_json_files $CONFIG_DIR $revad_config_dir
  } else {
    print $"Authprovider config found - will process placeholders..."
  }
  
  # Merge partial configs before placeholder processing
  # Partials merge into whatever config exists (base or overridden)
  merge_partial_configs $config_file
  
  # Always process placeholders, even if config exists
  # This ensures placeholders are replaced even if previous run was incomplete
  # Get environment variables with defaults
  let domain = (get_env_or_default "DOMAIN" "")
  if ($domain | str length) == 0 {
    error make { msg: "Environment variable DOMAIN is required" }
  }
  
  # Get authprovider-specific environment variables
  # Environment variable names are constructed using uppercase type (e.g., REVAD_AUTHPROVIDER_OIDC_HOST)
  # Defaults use generic names (ports match common patterns: 9158=OIDC, 9166=Machine, 9160=Public Shares, 9278=OCM Shares)
  let type_upper = ($authprovider_type | str upcase)
  let authprovider_host = (get_env_or_default $"REVAD_AUTHPROVIDER_($type_upper)_HOST" $"revad-authprovider-($authprovider_type)")
  
  # Set production-like default ports based on type
  mut default_port = "9158"  # OIDC default
  if $authprovider_type == "machine" {
    $default_port = "9166"
  } else if $authprovider_type == "publicshares" {
    $default_port = "9160"
  } else if $authprovider_type == "ocmshares" {
    $default_port = "9278"
  }
  
  let authprovider_grpc_port = (get_env_or_default $"REVAD_AUTHPROVIDER_($type_upper)_GRPC_PORT" $default_port)
  
  # Get gateway address for gRPC communication
  # Auth providers need to communicate with gateway via gRPC
  # Default uses generic name (port matches common pattern: 9142)
  let gateway_host = (get_env_or_default "REVAD_GATEWAY_HOST" "revad-gateway")
  let gateway_grpc_port = (get_env_or_default "REVAD_GATEWAY_GRPC_PORT" "9142")
  let gateway_svc = $"($gateway_host):($gateway_grpc_port)"
  
  # Get shared configuration variables
  let log_level = (get_env_or_default "REVAD_LOG_LEVEL" "debug")
  let log_output = (get_env_or_default "REVAD_LOG_OUTPUT" "/var/log/revad.log")
  let jwt_secret = (get_env_or_default "REVAD_JWT_SECRET" "reva-secret")
  
  # Get type-specific environment variables
  mut idp_url = ""
  mut idp_domain = ""
  mut machine_api_key = ""
  
  if $authprovider_type == "oidc" {
    $idp_url = (get_env_or_default "IDP_URL" "")
    if ($idp_url | str length) == 0 {
      error make { msg: "IDP_URL is required for OIDC authprovider" }
    }
    # Extract domain from IDP_URL if IDP_DOMAIN not provided
    $idp_domain = (get_env_or_default "IDP_DOMAIN" (
      if ($idp_url | str contains "://") {
        ($idp_url | split row "://" | get 1 | split row "/" | get 0)
      } else {
        "idp.docker"
      }
    ))
  } else if $authprovider_type == "machine" {
    $machine_api_key = (get_env_or_default "REVAD_JWT_SECRET" "reva-secret")
  }
  # OCM Shares and Public Shares types need no additional variables
  
  # Build placeholder map
  mut placeholder_map = {
    "log-level": $log_level
    "log-output": $log_output
    "jwt-secret": $jwt_secret
    "gateway-svc": $gateway_svc
    "grpc-address": $":($authprovider_grpc_port)"
    "config-dir": $revad_config_dir
  }
  
  # Add type-specific placeholders
  if $authprovider_type == "oidc" {
    $placeholder_map = ($placeholder_map | merge {
      "idp-url": $idp_url
      "idp-domain": $idp_domain
    })
  } else if $authprovider_type == "machine" {
    $placeholder_map = ($placeholder_map | merge {
      "machine-api-key": $machine_api_key
    })
  }
  # OCM Shares and Public Shares types need no additional placeholders
  
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
  print $"Authprovider ($authprovider_type) configuration initialized"
}
