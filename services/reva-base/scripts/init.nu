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
let HOST = (env HOST | default "localhost")
let DISABLED_CONFIGS = (env DISABLED_CONFIGS | default "")

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
  for f in (ls $REVA_CONFIG_DIR | where {|row| $row.name =~ ".*\\.toml$"} | get name) {
    replace_in_file $f "your.revad.org" $"($HOST).docker"
    replace_in_file $f "localhost" $"($HOST).docker"
    let base = ($HOST | str replace -r "reva" "")
    replace_in_file $f "your.efss.org" $"($base).docker"
    replace_in_file $f "your.nginx.org" $"($base).docker"
  }
  disable_config_files
}

def prepare_tls_certificates [] {
  create_directory $TLS_DIR
  if ($CERTS_DIR | path exists) {
    (ls $CERTS_DIR | where {|row| $row.name =~ ".*\\.crt$"} | get name | each {|n| cp -f $"($CERTS_DIR)/($n)" $TLS_DIR } ) | ignore
    (ls $CERTS_DIR | where {|row| $row.name =~ ".*\\.key$"} | get name | each {|n| cp -f $"($CERTS_DIR)/($n)" $TLS_DIR } ) | ignore
  }
  if ($CA_DIR | path exists) {
    (ls $CA_DIR | where {|row| $row.name =~ ".*\\.crt$"} | get name | each {|n| cp -f $"($CA_DIR)/($n)" $TLS_DIR } ) | ignore
    (ls $CA_DIR | where {|row| $row.name =~ ".*\\.key$"} | get name | each {|n| cp -f $"($CA_DIR)/($n)" $TLS_DIR } ) | ignore
  }
  (ls $TLS_DIR | where {|row| $row.name =~ ".*\\.crt$"} | get name | each {|n| cp -f $"($TLS_DIR)/($n)" "/usr/local/share/ca-certificates/" } ) | ignore
  ^update-ca-certificates | ignore
  ln -sf $"($TLS_DIR)/($HOST).crt" $"($TLS_DIR)/server.crt"
  ln -sf $"($TLS_DIR)/($HOST).key" $"($TLS_DIR)/server.key"
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

main
