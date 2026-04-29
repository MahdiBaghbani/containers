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

def validate_ssrf_mode [] {
  let raw = (get_env_or_default "OCM_GO_SSRF_MODE" "" | str trim)
  if ($raw | str length) == 0 {
    return ""
  }

  let valid = ["strict" "off"]
  if not ($raw in $valid) {
    error make { msg: $"OCM_GO_SSRF_MODE must be strict or off; got: ($raw)" }
  }

  let help_result = (^/app/bin/opencloudmesh-go -h | complete)
  let help_text = $"($help_result.stdout)($help_result.stderr)"
  if not ($help_text | str contains "-ssrf-mode") {
    error make {
      msg: (
        [
          "OCM_GO_SSRF_MODE is set but the installed binary does not support"
          " -ssrf-mode; bump the image tag to a version that includes this flag"
        ] | str join
      )
    }
  }

  $raw
}

def ensure_logfile [] {
  ^touch /var/log/opencloudmesh-go.log
}

def start_ocm_go [origin: string, mode: string, ssrf_mode: string, admin_user: string, admin_pass: string] {
  mut command = $"/app/bin/opencloudmesh-go --config /configs/config.toml --public-origin \"($origin)\""
  $command = $command + $" --admin-username \"($admin_user)\" --admin-password \"($admin_pass)\""
  if ($mode | str length) > 0 {
    $command = $command + $" --mode \"($mode)\""
  }
  if ($ssrf_mode | str length) > 0 {
    $command = $command + $" -ssrf-mode \"($ssrf_mode)\""
  }
  $command = $command + " >> /var/log/opencloudmesh-go.log 2>&1 &"

  ^sh -c $command
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
  let ssrf_mode = (validate_ssrf_mode)

  let ssrf_display = if ($ssrf_mode | str length) > 0 { $ssrf_mode } else { "default" }
  let ssrf_flag_status = if ($ssrf_mode | str length) > 0 { "applied" } else { "not applied" }
  print $"[ocmgo-init] ssrf-mode=($ssrf_display) -ssrf-mode flag: ($ssrf_flag_status)"

  start_ocm_go $origin $mode $ssrf_mode $admin_user $admin_pass
}
