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

# Gateway-specific initialization script
# Processes gateway configuration file with gateway-specific placeholders

use ./lib/shared.nu [create_directory, disable_config_files, copy_json_files]
use ./lib/utils.nu [replace_in_file, get_env_or_default, process_placeholders]
use ./lib/merge-partials.nu [merge_partial_configs]

const CONFIG_DIR = "/configs/revad"
const GATEWAY_CONFIG_FILE = "gateway.toml"

# Initialize gateway configuration
# Copies config template, processes placeholders, and sets up TLS based on environment
# Preserves existing config files to allow user modifications
export def init_gateway [] {
  print "Initializing gateway configuration..."
  
  # Get config directory from environment (default: /etc/revad)
  let revad_config_dir = (get_env_or_default "REVAD_CONFIG_DIR" "/etc/revad")
  
  if not ($CONFIG_DIR | path exists) { 
    error make {msg: $"Config dir not found: ($CONFIG_DIR)"} 
  }
  
  create_directory $revad_config_dir
  
  # Check if config already exists
  let config_path = $"($revad_config_dir)/($GATEWAY_CONFIG_FILE)"
  let has_config = ($config_path | path exists)
  
  if not $has_config {
    print "Gateway config not found - copying and templating from image..."
    
    # Copy gateway config template from image to runtime directory
    let source_config = $"($CONFIG_DIR)/($GATEWAY_CONFIG_FILE)"
    if not ($source_config | path exists) {
      error make { msg: $"Gateway config template not found: ($source_config)" }
    }
    ^cp $source_config $config_path
    
    # Copy all JSON files (users, groups, providers, etc.) needed by gateway config
    copy_json_files $CONFIG_DIR $revad_config_dir
  } else {
    print "Gateway config found - will process placeholders..."
  }
  
  # Merge partial configs before placeholder processing
  # Partials merge into whatever config exists (base or overridden)
  merge_partial_configs $GATEWAY_CONFIG_FILE
  
  # Always process placeholders, even if config exists
  # This ensures placeholders are replaced even if previous run was incomplete
  # Get environment variables with defaults
  let domain = (get_env_or_default "DOMAIN" "")
  if ($domain | str length) == 0 {
    error make { msg: "Environment variable DOMAIN is required" }
  }
  
  # Get gateway network configuration
  # Defaults match CERN production patterns for easier debugging
  let gateway_host = (get_env_or_default "REVAD_GATEWAY_HOST" $domain)
  let gateway_port = (get_env_or_default "REVAD_GATEWAY_PORT" "80")
  let gateway_protocol = (get_env_or_default "REVAD_GATEWAY_PROTOCOL" "http")
  let gateway_grpc_port = (get_env_or_default "REVAD_GATEWAY_GRPC_PORT" "9142")
  
  # Get logging and security configuration
  let log_level = (get_env_or_default "REVAD_LOG_LEVEL" "debug")
  let log_output = (get_env_or_default "REVAD_LOG_OUTPUT" "/var/log/revad.log")
  let jwt_secret = (get_env_or_default "REVAD_JWT_SECRET" "reva-secret")
  
  # Get [vars] section values for gateway configuration
  let internal_gateway = (get_env_or_default "REVAD_GATEWAY_HOST" $domain)
  let provider_domain = (get_env_or_default "DOMAIN" $domain)
  let web_domain = (get_env_or_default "WEB_DOMAIN" $domain)
  let web_protocol = (get_env_or_default "WEB_PROTOCOL" "http")
  let external_reva_endpoint = $"($web_protocol)://($web_domain)"
  let machine_api_key = (get_env_or_default "REVAD_JWT_SECRET" "machine-api-key")
  let ocmshares_json_file = (get_env_or_default "REVAD_OCMSHARES_JSON_FILE" "/var/tmp/reva/shares.json")
  
  # Build mesh directory URL from MESHDIR_URL or MESHDIR_DOMAIN
  # Prefer explicit URL, otherwise construct from domain
  let meshdir_url_env = (get_env_or_default "MESHDIR_URL" "")
  let meshdir_domain_env = (get_env_or_default "MESHDIR_DOMAIN" "")
  let mesh_directory_url = (if ($meshdir_url_env | str length) > 0 {
    $meshdir_url_env
  } else {
    let meshdir_domain = (if ($meshdir_domain_env | str length) > 0 {
      $meshdir_domain_env
    } else {
      "meshdir.docker"
    })
    $"https://($meshdir_domain)/meshdir"
  })
  
  # Get identity provider URL
  let idp_domain = (get_env_or_default "IDP_DOMAIN" "idp.docker")
  let idp_url = (get_env_or_default "IDP_URL" $"https://($idp_domain)")
  
  # Get Rclone endpoint for external storage operations
  let rclone_endpoint = (get_env_or_default "RCLONE_ENDPOINT" "http://rclone.docker")
  
  # Get dataprovider addresses for storage registry
  # Gateway needs these to route requests to appropriate dataproviders
  # Defaults use generic names (ports match common patterns: 9143-9147)
  let dataprovider_localhome_host = (get_env_or_default "REVAD_DATAPROVIDER_LOCALHOME_HOST" "revad-dataprovider-localhome")
  let dataprovider_localhome_grpc_port = (get_env_or_default "REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT" "9143")
  let dataprovider_ocm_host = (get_env_or_default "REVAD_DATAPROVIDER_OCM_HOST" "revad-dataprovider-ocm")
  let dataprovider_ocm_grpc_port = (get_env_or_default "REVAD_DATAPROVIDER_OCM_GRPC_PORT" "9146")
  let dataprovider_sciencemesh_host = (get_env_or_default "REVAD_DATAPROVIDER_SCIENCEMESH_HOST" "revad-dataprovider-sciencemesh")
  let dataprovider_sciencemesh_grpc_port = (get_env_or_default "REVAD_DATAPROVIDER_SCIENCEMESH_GRPC_PORT" "9147")
  
  # Get auth provider addresses for auth registry
  # Gateway needs these to route authentication requests to appropriate auth providers
  # Defaults use generic names (ports match common patterns: 9158=OIDC, 9166=Machine, 9160=Public Shares, 9278=OCM Shares)
  let authprovider_oidc_host = (get_env_or_default "REVAD_AUTHPROVIDER_OIDC_HOST" "revad-authprovider-oidc")
  let authprovider_oidc_grpc_port = (get_env_or_default "REVAD_AUTHPROVIDER_OIDC_GRPC_PORT" "9158")
  let authprovider_machine_host = (get_env_or_default "REVAD_AUTHPROVIDER_MACHINE_HOST" "revad-authprovider-machine")
  let authprovider_machine_grpc_port = (get_env_or_default "REVAD_AUTHPROVIDER_MACHINE_GRPC_PORT" "9166")
  let authprovider_publicshares_host = (get_env_or_default "REVAD_AUTHPROVIDER_PUBLICSHARES_HOST" "revad-authprovider-publicshares")
  let authprovider_publicshares_grpc_port = (get_env_or_default "REVAD_AUTHPROVIDER_PUBLICSHARES_GRPC_PORT" "9160")
  let authprovider_ocmshares_host = (get_env_or_default "REVAD_AUTHPROVIDER_OCMSHARES_HOST" "revad-authprovider-ocmshares")
  let authprovider_ocmshares_grpc_port = (get_env_or_default "REVAD_AUTHPROVIDER_OCMSHARES_GRPC_PORT" "9278")
  
  # Get share providers and user/group providers addresses
  # Gateway needs these to route requests to appropriate providers
  # Defaults use generic names (ports match common patterns: 9144=Share Providers, 9145=User/Group Providers)
  let shareproviders_host = (get_env_or_default "REVAD_SHAREPROVIDERS_HOST" "revad-shareproviders")
  let shareproviders_grpc_port = (get_env_or_default "REVAD_SHAREPROVIDERS_GRPC_PORT" "9144")
  let groupuserproviders_host = (get_env_or_default "REVAD_GROUPUSERPROVIDERS_HOST" "revad-groupuserproviders")
  let groupuserproviders_grpc_port = (get_env_or_default "REVAD_GROUPUSERPROVIDERS_GRPC_PORT" "9145")
  
  # Build placeholder map
  let placeholder_map = {
    "log-level": $log_level
    "log-output": $log_output
    "jwt-secret": $jwt_secret
    "gateway-svc": $"($gateway_host):($gateway_grpc_port)"
    "grpc-address": $":($gateway_grpc_port)"
    "http-address": $":($gateway_port)"
    "internal-gateway": $internal_gateway
    "provider-domain": $provider_domain
    "external-reva-endpoint": $external_reva_endpoint
    "machine-api-key": $machine_api_key
    "ocmshares-json-file": $ocmshares_json_file
    "mesh-directory-url": $mesh_directory_url
    "idp-url": $idp_url
    "rclone-endpoint": $rclone_endpoint
    "config-dir": $revad_config_dir
    "storageprovider.localhome": $"($dataprovider_localhome_host):($dataprovider_localhome_grpc_port)"
    "storageprovider.ocm": $"($dataprovider_ocm_host):($dataprovider_ocm_grpc_port)"
    "storageprovider.sciencemesh": $"($dataprovider_sciencemesh_host):($dataprovider_sciencemesh_grpc_port)"
    "authprovider.oidc.address": $"($authprovider_oidc_host):($authprovider_oidc_grpc_port)"
    "authprovider.machine.address": $"($authprovider_machine_host):($authprovider_machine_grpc_port)"
    "authprovider.publicshares.address": $"($authprovider_publicshares_host):($authprovider_publicshares_grpc_port)"
    "authprovider.ocmshares.address": $"($authprovider_ocmshares_host):($authprovider_ocmshares_grpc_port)"
    "shareproviders.address": $"($shareproviders_host):($shareproviders_grpc_port)"
    "groupuserproviders.address": $"($groupuserproviders_host):($groupuserproviders_grpc_port)"
  }
  
  # Process all placeholders in the config file using the placeholder map
  # Always process placeholders to ensure they're replaced even if file exists
  if not ($config_path | path exists) {
    error make { msg: $"Config file does not exist: ($config_path)" }
  }
  print $"Processing placeholders in config file: ($config_path)"
  process_placeholders $config_path $placeholder_map
  # Verify no placeholders remain
  let remaining_placeholders = (open --raw $config_path | str contains "{{placeholder:")
  if $remaining_placeholders {
    print "Warning: Some placeholders were not replaced. Check placeholder map and config file."
  } else {
    print "All placeholders processed successfully"
  }
  
  # Disable TLS certificate configuration in HTTP mode
  # Comment out certfile and keyfile lines when TLS is disabled
  let revad_tls_enabled = (get_env_or_default "REVAD_TLS_ENABLED" "false")
  if $revad_tls_enabled == "false" {
    replace_in_file $config_path 'certfile = "/tls/server.crt"' '# certfile disabled - HTTP mode'
    replace_in_file $config_path 'keyfile = "/tls/server.key"' '# keyfile disabled - HTTP mode'
  }
  
  # Remove any config files listed in DISABLED_CONFIGS
  disable_config_files
  print "Gateway configuration initialized"
}
