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

# Minimal partial config merge for ocm-go
# Simplified from services/revad-base/scripts/lib/merge-partials.nu
#
# SCOPE: this merger is SSRF-only and marker-based. Every partial file it
# processes MUST contain a [target] section that names the destination config
# file. Partials without [target] are rejected with an error. Do not relax
# this requirement into generic markerless merging; the SSRF partial writer
# (write_ssrf_runtime_partial) is the only caller and always emits [target].
# Regression: tests/ssrf-runtime-test.nu::test_merge_partial_requires_target_marker.

def fail_invalid_ssrf_partial [file: string, detail: string] {
  error make {msg: $"SSRF partial ($file) is invalid: ($detail)"}
}

def ensure_exact_record_keys [
  file: string
  scope: string
  value: record
  allowed_keys: list<string>
] {
  let keys = ($value | columns)
  let unexpected = ($keys | where {|key| not ($key in $allowed_keys)})
  let missing = ($allowed_keys | where {|key| not ($key in $keys)})

  if not ($unexpected | is-empty) {
    fail_invalid_ssrf_partial $file $"scope ($scope) has unexpected keys: ($unexpected | str join ', ')"
  }

  if not ($missing | is-empty) {
    fail_invalid_ssrf_partial $file $"scope ($scope) is missing required keys: ($missing | str join ', ')"
  }
}

def validate_ssrf_partial_shape [file: string, parsed: record] {
  ensure_exact_record_keys $file "top-level" $parsed ["target" "outbound_http"]

  let target = (try {
    $parsed.target
  } catch {
    fail_invalid_ssrf_partial $file "missing [target] section"
  })
  ensure_exact_record_keys $file "[target]" $target ["file"]

  let target_file = (try {
    $target.file
  } catch {
    fail_invalid_ssrf_partial $file "missing file key in [target]"
  })
  if $target_file != "config.toml" {
    fail_invalid_ssrf_partial $file $"[target].file must be config.toml, got: ($target_file)"
  }

  let outbound_http = (try {
    $parsed.outbound_http
  } catch {
    fail_invalid_ssrf_partial $file "missing [outbound_http] subtree"
  })
  ensure_exact_record_keys $file "[outbound_http]" $outbound_http ["ssrf"]

  let ssrf = (try {
    $outbound_http.ssrf
  } catch {
    fail_invalid_ssrf_partial $file "missing [outbound_http.ssrf] subtree"
  })
  ensure_exact_record_keys $file "[outbound_http.ssrf]" $ssrf ["route_policies"]

  let route_policies = (try {
    $ssrf.route_policies
  } catch {
    fail_invalid_ssrf_partial $file "missing [outbound_http.ssrf.route_policies] subtree"
  })
  ensure_exact_record_keys $file "[outbound_http.ssrf.route_policies]" $route_policies ["runtime"]

  let runtime = (try {
    $route_policies.runtime
  } catch {
    fail_invalid_ssrf_partial $file "missing [outbound_http.ssrf.route_policies.runtime] subtree"
  })
  ensure_exact_record_keys $file "[outbound_http.ssrf.route_policies.runtime]" $runtime [
    "allow_private_host_suffixes"
    "allow_private_cidrs"
    "allowed_ports"
    "allow_ip_literals"
  ]

  let allowed_ports = (try {
    $runtime.allowed_ports
  } catch {
    fail_invalid_ssrf_partial $file "missing allowed_ports in runtime route policy"
  })
  if $allowed_ports != [443] {
    fail_invalid_ssrf_partial $file $"runtime allowed_ports must be [443], got: ($allowed_ports | to nuon)"
  }

  let allow_ip_literals = (try {
    $runtime.allow_ip_literals
  } catch {
    fail_invalid_ssrf_partial $file "missing allow_ip_literals in runtime route policy"
  })
  if $allow_ip_literals != false {
    fail_invalid_ssrf_partial $file $"runtime allow_ip_literals must be false, got: ($allow_ip_literals | to nuon)"
  }
}

export def merge_partial_configs [config_dir: string, partials_dir: string] {
  if not ($partials_dir | path exists) {
    return
  }

  let files = (try {
    ls $partials_dir | where type == file | where {|f| ($f.name | str ends-with ".toml")} | get name
  } catch {
    []
  })

  if ($files | length) == 0 {
    return
  }

  mut merged_count = 0

  for file in $files {
    let content = (open --raw $file)

    let parsed = (try {
      open $file
    } catch {|err|
      error make {msg: $"Failed to parse TOML partial ($file): (try { $err.msg } catch { 'unknown error' })"}
    })

    validate_ssrf_partial_shape $file $parsed

    let target_section = $parsed.target

    let target_file = (try {
      $target_section | get "file"
    } catch {
      error make {msg: $"Missing 'file' key in [target] section: ($file)"}
    })

    let target_path = $"($config_dir)/($target_file)"
    if not ($target_path | path exists) {
      error make {msg: $"Target config file not found: ($target_path)"}
    }

    # Strip [target] section from raw content after the parsed structure check
    # proved this partial is limited to the single SSRF runtime subtree emitted
    # by write_ssrf_runtime_partial.
    let lines = ($content | split row "\n")
    mut result_lines = []
    mut in_target_section = false

    for line in $lines {
      let trimmed = ($line | str trim)

      if ($trimmed == "[target]") {
        $in_target_section = true
        continue
      }

      if $in_target_section {
        if ($trimmed | str starts-with "[") {
          $in_target_section = false
          $result_lines = ($result_lines | append $line)
        } else if ($trimmed | is-empty) {
          continue
        } else {
          continue
        }
      } else {
        $result_lines = ($result_lines | append $line)
      }
    }

    let partial_content = ($result_lines | str join "\n" | str trim)
    if ($partial_content | str length) == 0 {
      continue
    }

    let existing = (open --raw $target_path)
    let new_content = ($existing + "\n" + $partial_content + "\n")
    $new_content | save -f $target_path

    $merged_count = $merged_count + 1
  }

  if $merged_count > 0 {
    print $"Merged ($merged_count) partial config\(s\) into ($config_dir)"
  }
}
