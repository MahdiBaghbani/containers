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

# Main entrypoint script - validates mode and routes to appropriate init script

use ./lib/shared.nu [init_shared, start_reva_daemon]
use ./lib/utils.nu [get_env_or_default]

# Valid container modes supported by this entrypoint
const VALID_MODES = ["gateway", "dataprovider-localhome", "dataprovider-ocm", "dataprovider-sciencemesh", "authprovider-oidc", "authprovider-machine", "authprovider-ocmshares", "authprovider-publicshares", "shareproviders", "groupuserproviders"]

# Validate that the provided container mode is in the list of valid modes
# Raises an error if the mode is invalid
def validate_mode [mode: string] {
  if not ($mode in $VALID_MODES) {
    let valid_modes_str = ($VALID_MODES | str join ", ")
    error make { 
      msg: $"Invalid REVAD_CONTAINER_MODE: ($mode). Valid modes: ($valid_modes_str)" 
    }
  }
}

# Extract dataprovider type from container mode string
# For example, "dataprovider-localhome" -> "localhome"
# Returns null if mode does not start with "dataprovider-"
def extract_dataprovider_type [mode: string] {
  if ($mode | str starts-with "dataprovider-") {
    # Extract substring after "dataprovider-" (13 characters)
    ($mode | str substring 13..)
  } else {
    null
  }
}

# Extract authprovider type from container mode string
# For example, "authprovider-oidc" -> "oidc"
# Returns null if mode does not start with "authprovider-"
def extract_authprovider_type [mode: string] {
  if ($mode | str starts-with "authprovider-") {
    # Extract substring after "authprovider-" (13 characters)
    ($mode | str substring 13..)
  } else {
    null
  }
}

# Main entrypoint function
# Orchestrates container initialization by validating mode, running shared setup,
# routing to mode-specific initialization, and starting the Reva daemon
def main [] {
  # Get and validate container mode from environment variable
  let container_mode = (get_env_or_default "REVAD_CONTAINER_MODE" "")
  
  if ($container_mode | str length) == 0 {
    error make { 
      msg: "REVAD_CONTAINER_MODE environment variable is required. Valid modes: gateway, dataprovider-localhome, dataprovider-ocm, dataprovider-sciencemesh, authprovider-oidc, authprovider-machine, authprovider-ocmshares, authprovider-publicshares, shareproviders, groupuserproviders" 
    }
  }
  
  validate_mode $container_mode
  
  print $"Container mode: ($container_mode)"
  
  # Run shared initialization tasks (DNS, hosts, log files, TLS, etc.)
  init_shared
  
  # Route to mode-specific initialization based on container mode
  mut config_file = ""
  if $container_mode == "gateway" {
    use ./init-gateway.nu [init_gateway]
    init_gateway
    $config_file = "gateway.toml"
  } else if ($container_mode | str starts-with "dataprovider-") {
    use ./init-dataprovider.nu [init_dataprovider]
    let dataprovider_type = (extract_dataprovider_type $container_mode)
    init_dataprovider $dataprovider_type
    $config_file = $"dataprovider-($dataprovider_type).toml"
  } else if ($container_mode | str starts-with "authprovider-") {
    use ./init-authprovider.nu [init_authprovider]
    let authprovider_type = (extract_authprovider_type $container_mode)
    init_authprovider $authprovider_type
    $config_file = $"authprovider-($authprovider_type).toml"
  } else if $container_mode == "shareproviders" {
    use ./init-shareproviders.nu [init_shareproviders]
    init_shareproviders
    $config_file = "shareproviders.toml"
  } else if $container_mode == "groupuserproviders" {
    use ./init-groupuserproviders.nu [init_groupuserproviders]
    init_groupuserproviders
    $config_file = "groupuserproviders.toml"
  } else {
    error make { msg: $"Unhandled container mode: ($container_mode)" }
  }
  
  # Start Reva daemon with specific config file
  # Uses -c flag to load only the specified config file (not --dev-dir which loads all configs)
  start_reva_daemon $config_file
  
  print "Initialization complete, Reva daemon started"
}
