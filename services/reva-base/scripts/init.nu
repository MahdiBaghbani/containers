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

let REVA_DIR = "/reva"
let REVA_GIT_DIR = "/reva-git"
let CONFIG_DIR = "/configs/revad"
let REVA_CONFIG_DIR = "/etc/revad"
let TLS_DIR = "/tls"
let CERTS_DIR = "/certificates"
let CA_DIR = "/certificate-authority"
let DOMAIN = (env DOMAIN | default "")
let DISABLED_CONFIGS = (env DISABLED_CONFIGS | default "")

# Shared environment variables for Reva services
# Defaults are derived from REVA_TLS_ENABLED
let REVA_TLS_ENABLED = (env REVA_TLS_ENABLED | default (env TLS_ENABLED | default "false"))
let REVA_PROTOCOL = (env REVA_PROTOCOL | default (if $REVA_TLS_ENABLED == "false" { "http" } else { "https" }))
let REVA_PORT = (env REVA_PORT | default (if $REVA_TLS_ENABLED == "false" { "80" } else { "443" }))
let REVA_HOST = (env REVA_HOST | default $DOMAIN)

# External endpoint uses web frontend domain, different from Reva backend domain
# WEB_DOMAIN, if set, is used as-is. Otherwise, it falls back to DOMAIN with "reva" removed.
let WEB_DOMAIN = (env WEB_DOMAIN | default (
  if ($DOMAIN | str length) > 0 {
    let hostname = ($DOMAIN | split row "." | get 0)
    let suffix = (if ($DOMAIN | split row "." | length) > 1 {
      ($DOMAIN | split row "." | range 1.. | str join ".")
    } else {
      ""
    })
    let clean_hostname = ($hostname | str replace -a "reva" "")
    if ($suffix | str length) > 0 {
      $"($clean_hostname).($suffix)"
    } else {
      $clean_hostname
    }
  } else {
    $DOMAIN
  }
))

# Frontend TLS/protocol shoule be independent of backend
let WEB_TLS_ENABLED = (env WEB_TLS_ENABLED | default $REVA_TLS_ENABLED)
let WEB_PROTOCOL = (env WEB_PROTOCOL | default (if $WEB_TLS_ENABLED == "false" { "http" } else { "https" }))

# Frontend endpoint
let EXTERNAL_REVA_ENDPOINT = (env EXTERNAL_REVA_ENDPOINT | default $"($WEB_PROTOCOL)://($WEB_DOMAIN)")

def create_directory [dir: string] { mkdir $dir }

def populate_reva_binaries [] {
  if not ($REVA_DIR | path exists) { error make {msg: $"($REVA_DIR) does not exist"} }
  let has_files = (not ((ls -a $REVA_DIR | where {|row| $row.name != "." and $row.name != ".."} | is-empty)))
  if not $has_files {
    print "/reva is empty, populating with reva binaries..."
    cp -r $"($REVA_GIT_DIR)/cmd" $REVA_DIR
  } else {
    ls -lsa $REVA_DIR | to text | print $in
    print "/reva contains files, skipping populate"
  }
}

def disable_config_files [] {
  if ($DISABLED_CONFIGS | str length) == 0 { return }
  print "Disabling specified configuration files..."
  for config in ($DISABLED_CONFIGS | split row " ") {
    let p = $"($REVA_CONFIG_DIR)/($config)"
    if ($p | path exists) { rm -f $p }
  }
}

def replace_in_file [file: string, from: string, to: string] {
  let content = (open $file | into string)
  $content | str replace -a $from $to | save -f $file
}

def prepare_configuration [] {
  if not ($CONFIG_DIR | path exists) { error make {msg: $"Config dir not found: ($CONFIG_DIR)"} }
  rm -rf $REVA_CONFIG_DIR
  cp -r $CONFIG_DIR $REVA_CONFIG_DIR

  if ($DOMAIN | str length) == 0 { error make { msg: "Environment variable DOMAIN is required" } }
  
  # REVA_PORT must be 443 for HTTPS or 80 for HTTP
  # @MahdiBaghbani: I think this is important to validate, but it's not a bug.
  # Anyway, If you can open PR to improve this, please do.
  if $REVA_TLS_ENABLED == "true" and $REVA_PORT != "443" {
    error make { msg: $"REVA_TLS_ENABLED=true requires REVA_PORT=443, but got ($REVA_PORT)" }
  }
  if $REVA_TLS_ENABLED == "false" and $REVA_PORT != "80" {
    error make { msg: $"REVA_TLS_ENABLED=false requires REVA_PORT=80, but got ($REVA_PORT)" }
  }
  
  for f in (ls $REVA_CONFIG_DIR | where {|row| $row.name =~ ".*\\.toml$"} | get name) {
    # Domain replacements, different domains for different purposes
    # your.revad.org -> Reva backend domain (DOMAIN, e.g., revacernbox1.docker)
    replace_in_file $f "your.revad.org" $DOMAIN
    # localhost -> Reva backend domain (DOMAIN)
    replace_in_file $f "localhost" $DOMAIN
    # your.efss.org -> Web frontend domain (WEB_DOMAIN, e.g., cernbox1.docker)
    replace_in_file $f "your.efss.org" $WEB_DOMAIN
    # your.nginx.org -> Web frontend domain (WEB_DOMAIN, e.g., cernbox1.docker)
    replace_in_file $f "your.nginx.org" $WEB_DOMAIN
    
    # External Reva endpoint with protocol, uses web frontend domain
    replace_in_file $f 'external_reva_endpoint = "https://your.nginx.org"' $"external_reva_endpoint = \"($EXTERNAL_REVA_ENDPOINT)\""
    
    # Service endpoints
    # These default values are a remnant of ocm-test-suite.
    # @MahdiBaghbani: I think it's important to keep them.
    let IDP_DOMAIN = (env IDP_DOMAIN | default "idp.docker")
    let IDP_URL = (env IDP_URL | default $"https://($IDP_DOMAIN)")
    let RCLONE_ENDPOINT = (env RCLONE_ENDPOINT | default "http://rclone.docker")
    let MESHDIR_DOMAIN = (env MESHDIR_DOMAIN | default "meshdir.docker")
    let MESHDIR_URL = (env MESHDIR_URL | default $"https://($MESHDIR_DOMAIN)/meshdir")
    replace_in_file $f "https://idp.docker" $IDP_URL
    replace_in_file $f "idp.docker" $IDP_DOMAIN
    replace_in_file $f "http://rclone.docker" $RCLONE_ENDPOINT
    replace_in_file $f "rclone.docker" $RCLONE_ENDPOINT

    # Replace mesh_directory_url template variable with actual URL
    # @MahdiBaghbani: with the introduction of Directory service, I believe this option shoulde be obsoleted.
    replace_in_file $f 'mesh_directory_url = "{{ vars.mesh_directory_url }}"' $"mesh_directory_url = \"($MESHDIR_URL)\""
    replace_in_file $f "meshdir.docker" $MESHDIR_DOMAIN

    # Replace hardcoded HTTPS protocols with REVA_PROTOCOL
    replace_in_file $f $"https://localhost" $"($REVA_PROTOCOL)://($DOMAIN)"
    replace_in_file $f 'datagateway = "https://{{' $"datagateway = \"($REVA_PROTOCOL)://{{"
    
    # Replace hardcoded port 443 with REVA_PORT in all [http.services.*].address fields
    replace_in_file $f 'address = ":443"' $"address = \":($REVA_PORT)\""
    
    # Replace data_server_url patterns with protocol scheme
    # Pattern: https://localhost:{{ ... }}
    replace_in_file $f $"https://localhost:" $"($REVA_PROTOCOL)://($DOMAIN):"
    # Pattern: https://your.revad.org:{{ ... }}
    replace_in_file $f $"https://($DOMAIN):" $"($REVA_PROTOCOL)://($DOMAIN):"

    # TLS toggle: comment out cert lines in HTTP mode
    if $REVA_TLS_ENABLED == "false" {
      replace_in_file $f 'certfile = "/tls/server.crt"' '# certfile disabled - HTTP mode'
      replace_in_file $f 'keyfile = "/tls/server.key"' '# keyfile disabled - HTTP mode'
    }
  }
  disable_config_files
}

def prepare_tls_certificates [] {
  if $REVA_TLS_ENABLED == "false" {
    print "TLS disabled (REVA_TLS_ENABLED=false) - skipping certificate setup"
    return
  }
  
  # If TLS is enabled, certs must exist
  if ($DOMAIN | str length) == 0 { error make { msg: "Environment variable DOMAIN is required when REVA_TLS_ENABLED=true" } }
  
  create_directory $TLS_DIR
  if ($CERTS_DIR | path exists) {
    (ls $CERTS_DIR | where {|row| $row.name =~ ".*\\.(crt|key)$"} | get name | each {|n| cp -f $"($CERTS_DIR)/($n)" $TLS_DIR } ) | ignore
  }
  if ($CA_DIR | path exists) {
    (ls $CA_DIR | where {|row| $row.name =~ ".*\\.(crt|key)$"} | get name | each {|n| cp -f $"($CA_DIR)/($n)" $TLS_DIR } ) | ignore
  }
  (ls $TLS_DIR | where {|row| $row.name =~ ".*\\.crt$"} | get name | each {|n| cp -f $"($TLS_DIR)/($n)" "/usr/local/share/ca-certificates/" } ) | ignore
  ^update-ca-certificates | ignore
  
  # Find certificate using REVA_HOST hostname first, then DOMAIN hostname,
  # then reva.crt (for SAN-based certs), then generic.
  # @MahdiBaghbani: In most cases, REVA_HOST is the same as DOMAIN. 
  # but maybe some people want to use different hostnames for different purposes.
  # reva.crt is a generic certificate for ocm-test-suite tests.
  let reva_hostpart = (if ($REVA_HOST | str length) > 0 { ($REVA_HOST | split row "." | get 0) } else { "" })
  let domain_hostpart = ($DOMAIN | split row "." | get 0)
  
  # Priority: REVA_HOST hostname > DOMAIN hostname > reva.crt > server.crt
  let cert_src = (if ($reva_hostpart | str length) > 0 and ($"($TLS_DIR)/($reva_hostpart).crt" | path exists) {
    $"($TLS_DIR)/($reva_hostpart).crt"
  } else if ($"($TLS_DIR)/($domain_hostpart).crt" | path exists) {
    $"($TLS_DIR)/($domain_hostpart).crt"
  } else if ($"($TLS_DIR)/reva.crt" | path exists) {
    $"($TLS_DIR)/reva.crt"
  } else {
    $"($TLS_DIR)/server.crt"
  })
  
  let key_src = (if ($reva_hostpart | str length) > 0 and ($"($TLS_DIR)/($reva_hostpart).key" | path exists) {
    $"($TLS_DIR)/($reva_hostpart).key"
  } else if ($"($TLS_DIR)/($domain_hostpart).key" | path exists) {
    $"($TLS_DIR)/($domain_hostpart).key"
  } else if ($"($TLS_DIR)/reva.key" | path exists) {
    $"($TLS_DIR)/reva.key"
  } else {
    $"($TLS_DIR)/server.key"
  })
  
  if not ($cert_src | path exists) { error make { msg: "REVA_TLS_ENABLED=true but certificate not found in /tls" } }
  if not ($key_src | path exists) { error make { msg: "REVA_TLS_ENABLED=true but key not found in /tls" } }

  # Only create symlinks if the selected cert/key are not already server.crt/server.key
  let server_crt_path = $"($TLS_DIR)/server.crt"
  let server_key_path = $"($TLS_DIR)/server.key"
  
  if $cert_src != $server_crt_path {
    ln -sf $cert_src $server_crt_path
  }
  if $key_src != $server_key_path {
    ln -sf $key_src $server_key_path
  }
}

def start_reva_daemon [] {
  let found = (not ((which revad | is-empty)))
  if not $found { error make {msg: "revad not found in PATH"} }
  print "Starting Reva daemon..."
  ^revad --dev-dir $REVA_CONFIG_DIR &
}

def main [] {
  create_directory $REVA_DIR
  populate_reva_binaries
  prepare_configuration
  prepare_tls_certificates
  start_reva_daemon
}
