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

use ./lib/utils.nu [get_env_or_default]
use ./lib/merge-partials-ocmgo.nu [merge_partial_configs]
use ./lib/ssrf-runtime.nu [
    parse_private_cidrs
    parse_suffixes
    write_ssrf_runtime_partial
    inject_ssrf_route_policy
    cleanup_ssrf_runtime_state
]

def write_nsswitch [] {
  "hosts: files dns\n" | save -f /etc/nsswitch.conf
}

def validate_host [host: string] {
  let trimmed = ($host | str trim)

  if ($trimmed | str length) == 0 {
    error make { msg: "HOST must not be empty" }
  }

  if ($trimmed =~ '\s') {
    error make { msg: $"HOST must not contain whitespace: ($trimmed)" }
  }

  if (
    ($trimmed | str contains "://")
    or ($trimmed | str contains "/")
    or ($trimmed | str contains "?")
    or ($trimmed | str contains "#")
  ) {
    error make { msg: $"HOST format is invalid: ($trimmed)" }
  }

  $trimmed
}

def ensure_hosts [host: string] {
  if ($host | str length) == 0 {
    return
  }

  let entry = $"127.0.0.1 ($host).docker"
  let current_hosts = (if ("/etc/hosts" | path exists) {
    open --raw /etc/hosts
  } else {
    ""
  })

  if not ($current_hosts | str contains $entry) {
    mut next_hosts = $current_hosts
    if ($next_hosts | str length) > 0 and not ($next_hosts | str ends-with "\n") {
      $next_hosts = $next_hosts + "\n"
    }
    $next_hosts = $next_hosts + $entry + "\n"
    $next_hosts | save -f /etc/hosts
  }
}

def resolve_public_origin [validated_host: string] {
  let public_origin = (get_env_or_default "PUBLIC_ORIGIN" "" | str trim)
  if ($public_origin | str length) > 0 {
    return $public_origin
  }

  if ($validated_host | str length) > 0 {
    return $"https://($validated_host).docker"
  }

  error make { msg: "Either PUBLIC_ORIGIN or HOST must be set" }
}

def validate_mode [] {
  let mode = (get_env_or_default "OCM_GO_MODE" "" | str trim)
  if ($mode | str length) == 0 {
    return ""
  }

  let valid_modes = ["strict" "interop" "dev"]
  if not ($mode in $valid_modes) {
    error make { msg: $"OCM_GO_MODE must be strict, interop, or dev; got: ($mode)" }
  }

  $mode
}

def ensure_logfile [] {
  ^touch /var/log/opencloudmesh-go.log
}

def start_ocm_go [origin: string, mode: string, admin_user: string, admin_pass: string] {
  mut command = $"/app/bin/opencloudmesh-go --config /configs/config.toml --public-origin \"($origin)\""
  $command = $command + $" --admin-username \"($admin_user)\" --admin-password \"($admin_pass)\""
  if ($mode | str length) > 0 {
    $command = $command + $" --mode \"($mode)\""
  }
  $command = $command + " >> /var/log/opencloudmesh-go.log 2>&1 &"

  ^sh -c $command
}

# Resolve route intent envs and, if present, write the runtime SSRF partial
# and inject the route_policy key into config.toml before merge runs.
#
# If neither env is set, the container boots with the strict nested SSRF base
# config and no active route policy - this is valid and expected.
#
# If either env is set, both must yield non-empty lists; otherwise the
# container fails early rather than writing an invalid partial config.
# CIDRs are taken directly from OCM_GO_ROUTE_PRIVATE_CIDRS (topology-owned,
# deterministic /24 per run); no DNS resolution is performed at boot.
export def setup_ssrf_runtime_route [config_dir: string, partial_dir: string] {
    let partial_path = $"($partial_dir)/99-runtime-ssrf.toml"
    let config_path = $"($config_dir)/config.toml"

    cleanup_ssrf_runtime_state $config_path $partial_path

    let cidrs_raw = (get_env_or_default "OCM_GO_ROUTE_PRIVATE_CIDRS" "" | str trim)
    let suffixes_raw = (get_env_or_default "OCM_GO_ROUTE_SUFFIXES" "" | str trim)

    let has_cidrs = ($cidrs_raw | str length) > 0
    let has_suffixes = ($suffixes_raw | str length) > 0

    if (not $has_cidrs) and (not $has_suffixes) {
        return
    }

    let cidrs = (parse_private_cidrs $cidrs_raw)
    let suffixes = (parse_suffixes $suffixes_raw)

    if ($cidrs | is-empty) {
        error make {
            msg: (if $has_cidrs {
                "OCM_GO_ROUTE_PRIVATE_CIDRS is set but produced no valid entries (value parsed to an empty list)"
            } else {
                "OCM_GO_ROUTE_PRIVATE_CIDRS must be set (non-empty) when OCM_GO_ROUTE_SUFFIXES is provided"
            })
        }
    }
    if ($suffixes | is-empty) {
        error make {
            msg: (if $has_suffixes {
                "OCM_GO_ROUTE_SUFFIXES is set but produced no valid entries (value parsed to an empty list)"
            } else {
                "OCM_GO_ROUTE_SUFFIXES must be set (non-empty) when OCM_GO_ROUTE_PRIVATE_CIDRS is provided"
            })
        }
    }

    write_ssrf_runtime_partial $partial_path $suffixes $cidrs
    inject_ssrf_route_policy $config_path

    let cidr_count = ($cidrs | length)
    let suffix_count = ($suffixes | length)
    print $"[ocmgo-init] SSRF runtime route policy: ($cidr_count) CIDRs, ($suffix_count) suffixes"
}

def --wrapped main [...args] {
  write_nsswitch

  let host = (get_env_or_default "HOST" "" | str trim)
  let validated_host = if ($host | str length) > 0 {
    validate_host $host
  } else {
    ""
  }

  ensure_hosts $validated_host

  setup_ssrf_runtime_route "/configs" "/configs/partial"

  merge_partial_configs "/configs" "/configs/partial"

  let admin_user = (get_env_or_default "OCM_GO_ADMIN_USER" "" | str trim)
  if ($admin_user | str length) == 0 {
    error make { msg: "OCM_GO_ADMIN_USER must be set" }
  }

  let admin_pass = (get_env_or_default "OCM_GO_ADMIN_PASSWORD" "" | str trim)
  if ($admin_pass | str length) == 0 {
    error make { msg: "OCM_GO_ADMIN_PASSWORD must be set" }
  }

  ensure_logfile

  let origin = (resolve_public_origin $validated_host)
  let mode = (validate_mode)

  start_ocm_go $origin $mode $admin_user $admin_pass
}
