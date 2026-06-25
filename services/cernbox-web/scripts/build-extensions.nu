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

# Safe field access with default value
def safe-get [field: string, default: any = ""] {
  try {
    $in | get $field | default $default
  } catch {
    $default
  }
}

# Get last N lines from multi-line text
def last-lines [n: int] {
  $in | lines | last $n | str join "\n"
}

# Check if string contains EAGAIN error (case-insensitive)
def has-eagain-error [] {
  let text = ($in | str downcase)
  ($text | str contains "eagain") or ($text | str contains "err_pnpm_eagain")
}

# Parse comma-separated package names from CLI or Dockerfile ARG
export def parse-comma-list [raw: string] {
  if ($raw | str trim | is-empty) {
    return []
  }
  $raw
  | split row ","
  | each {|name| $name | str trim }
  | where {|name| not ($name | is-empty) }
}

export def reserved-package-names [] {
  [".", "..", ".git", ".github"]
}

def find-duplicate-names [names: list<string>] {
  mut seen = []
  mut dupes = []
  for name in $names {
    if $name in $seen {
      if not ($name in $dupes) {
        $dupes = ($dupes | append $name)
      }
    } else {
      $seen = ($seen | append $name)
    }
  }
  $dupes
}

export def discover-packages [extensions_dir: string] {
  let exclude_dirs = (reserved-package-names)
  ls -a $extensions_dir
  | where type == "dir"
  | where {|item| not ($item.name in $exclude_dirs)}
  | get name
}

# Returns {valid, reason} for unit tests and plan-packages
export def check-only-list [names: list<string>, extensions_dir: string] {
  let dupes = (find-duplicate-names $names)
  if ($dupes | length) > 0 {
    return {valid: false, reason: $"duplicate package names: ($dupes | str join ', ')"}
  }

  let reserved = (reserved-package-names)
  for name in $names {
    if $name in $reserved {
      return {valid: false, reason: $"reserved package name: ($name)"}
    }
    let pkg_path = $"($extensions_dir)/($name)"
    if not ($pkg_path | path exists) {
      return {valid: false, reason: $"missing package: ($name)"}
    }
    if (($pkg_path | path type) != "dir") {
      return {valid: false, reason: $"not a directory: ($name)"}
    }
  }

  {valid: true, reason: ""}
}

# Resolve build order; allowlist mode ignores skip
export def plan-packages [
  only_list: list<string>,
  skip_list: list<string>,
  extensions_dir: string
] {
  if ($only_list | length) > 0 {
    let check = (check-only-list $only_list $extensions_dir)
    if not $check.valid {
      return {ok: false, error: $check.reason, packages: [], skip_list: []}
    }
    return {ok: true, error: "", packages: $only_list, skip_list: []}
  }

  {
    ok: true,
    error: "",
    packages: (discover-packages $extensions_dir),
    skip_list: $skip_list
  }
}

# Build all web extensions with retry logic for pnpm install
# Handles network reliability issues and EAGAIN errors
def retry-pnpm-install [package_dir: string, max_retries: int] {
  # Ensure pnpm uses the shared store (BuildKit cache mount will persist this)
  try {
    pnpm config set store-dir /root/.local/share/pnpm/store | ignore
  }
  
  mut attempt = 0
  mut success = false
  mut encountered_eagain = false
  
  while ($attempt < $max_retries) and (not $success) {
    $attempt = ($attempt + 1)
    
    if $attempt > 1 {
      print $"Attempt ($attempt)/($max_retries) for pnpm install in ($package_dir)"
    }
    
    cd $package_dir
    let pnpm_result = (pnpm install | complete)
    cd ..
    
    if $pnpm_result.exit_code == 0 {
      $success = true
      if $attempt > 1 {
        print $"Successfully installed after ($attempt) attempts"
      }
    } else {
      # Combine stdout and stderr
      let stdout_text = ($pnpm_result | safe-get stdout)
      let stderr_text = ($pnpm_result | safe-get stderr)
      let output_text = $"($stdout_text)\n($stderr_text)"
      
      # Check for EAGAIN errors
      let is_eagain = ($output_text | has-eagain-error)
      
      if $is_eagain {
        $encountered_eagain = true
        print $"EAGAIN error detected on attempt ($attempt)/($max_retries)"

        let error_preview = ($output_text | lines | where {|l| ($l | str downcase | str contains "eagain")} | last 3 | str join "\n")
        if ($error_preview | str length) > 0 {
          print $error_preview
        }
        
        if $attempt < $max_retries {
          print "Retrying in 1 second..."
          sleep 1sec
        } else {
          print "Max retries reached, giving up"
        }
      } else {
        print $"Non-retryable error on attempt ($attempt)"
        let error_preview = ($output_text | last-lines 5)
        
        if ($error_preview | str length) > 0 {
          print $error_preview
        } else {
          print $"Exit code: ($pnpm_result.exit_code)"
        }
        break
      }
    }
  }
  
  {
    success: $success,
    attempts: $attempt,
    was_eagain: $encountered_eagain
  }
}

# Check if directory has Makefile with release target
def has-release-target [package_path: string] {
  let makefile_path = $"($package_path)/Makefile"
  
  if not ($makefile_path | path exists) {
    return false
  }
  
  try {
    let makefile_content = (open $makefile_path)
    let release_lines = ($makefile_content | lines | where {|line| $line | str contains "release:"})
    ($release_lines | length) > 0
  } catch {
    false
  }
}

def fail-required [package_name: string, reason: string] {
  print $"Error: required extension ($package_name) failed: ($reason)"
  exit 1
}

# Build a single package; returns true when built or intentionally skipped
def build-package [
  package_name: string,
  output_dir: string,
  retry_count: int,
  skip_list: list<string>
] {
  if $package_name in $skip_list {
    print $"Skipping ($package_name): listed in --skip"
    return true
  }

  print $"Building package: ($package_name)"
  
  let package_path = $package_name
  
  if not (has-release-target $package_path) {
    fail-required $package_name "no release target in Makefile"
  }
  
  let package_json_path = $"($package_path)/package.json"
  if ($package_json_path | path exists) {
    let install_result = (retry-pnpm-install $package_path $retry_count)
    
    if not $install_result.success {
      let attempts_made = $install_result.attempts
      if $install_result.was_eagain {
        fail-required $package_name $"pnpm install failed after ($attempts_made) attempts due to EAGAIN errors"
      } else {
        fail-required $package_name "pnpm install failed (non-retryable error)"
      }
    }
  }
  
  try {
    cd $package_path
    make release
    cd ..
  } catch {|err|
    cd ..
    fail-required $package_name $"make release failed: ($err.msg)"
  }
  
  let release_file = $"($package_path)/release/($package_name).tar.gz"
  if not ($release_file | path exists) {
    fail-required $package_name $"release archive missing after make release: ($release_file)"
  }

  let output_package_dir = $"($output_dir)/($package_name)"
  mkdir $output_package_dir

  try {
    tar -xzf $release_file -C $output_package_dir --strip-components=0
    print $"Successfully built and extracted ($package_name)"
  } catch {|err|
    fail-required $package_name $"failed to extract release archive: ($err.msg)"
  }

  true
}

def main [
  extensions_dir: string = ".",
  output_dir: string = "/build/cernbox",
  --retry-count: int = 10,
  --skip: string = "",
  --only: string = ""
] {
  let only_list = (parse-comma-list $only)
  let skip_list = (parse-comma-list $skip)

  let plan = (plan-packages $only_list $skip_list $extensions_dir)
  if not $plan.ok {
    print $"Error: ($plan.error)"
    exit 1
  }

  mkdir $output_dir
  cd $extensions_dir

  for package in $plan.packages {
    build-package $package $output_dir $retry_count $plan.skip_list
  }

  cd ..
  print "Finished building all packages"
}
