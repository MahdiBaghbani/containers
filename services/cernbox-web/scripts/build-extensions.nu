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

# Build a single package
def build-package [package_name: string, output_dir: string, retry_count: int] {
  print $"Building package: ($package_name)"
  
  let package_path = $package_name
  
  # Check if package has release target
  if not (has-release-target $package_path) {
    print $"Skipping ($package_name): No release target in Makefile"
    return
  }
  
  # Install dependencies with retry logic if package.json exists
  let package_json_path = $"($package_path)/package.json"
  if ($package_json_path | path exists) {
    let install_result = (retry-pnpm-install $package_path $retry_count)
    
    if not $install_result.success {
      let attempts_made = $install_result.attempts
      if $install_result.was_eagain {
        print $"Warning: Failed to install dependencies for ($package_name) after ($attempts_made) attempts due to EAGAIN errors, skipping..."
      } else {
        print $"Warning: Failed to install dependencies for ($package_name) \(non-retryable error\), skipping..."
      }
      return
    }
  }
  
  # Build the package
  let build_result = (try {
    cd $package_path
    make release
    cd ..
    true
  } catch {|err|
    cd ..
    print $"Warning: Failed to build ($package_name), skipping..."
    false
  })
  
  if not $build_result {
    return
  }
  
  # Extract the release archive if it exists
  let release_file = $"($package_path)/release/($package_name).tar.gz"
  if ($release_file | path exists) {
    let output_package_dir = $"($output_dir)/($package_name)"
    mkdir $output_package_dir
    
    try {
      tar -xzf $release_file -C $output_package_dir --strip-components=0
      print $"Successfully built and extracted ($package_name)"
    } catch {|err|
      print $"Error extracting ($package_name): ($err)"
    }
  }
}

def main [
  extensions_dir: string = ".",
  output_dir: string = "/build/cernbox",
  --retry-count: int = 10
] {
  mkdir $output_dir
  cd $extensions_dir
  
  # Find all directories, excluding special directories
  let exclude_dirs = [".", "..", ".git", ".github"]
  let packages = (
    ls -a
    | where type == "dir"
    | where {|item| not ($item.name in $exclude_dirs)}
    | get name
  )

  for package in $packages {
    build-package $package $output_dir $retry_count
  }
  
  cd ..
  print "Finished building all packages"
}
