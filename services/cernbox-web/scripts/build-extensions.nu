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

# Build all web extensions with retry logic for pnpm install 
# (since my Iranian internet is super good and pnpm doesn't crash 6 times in a row :-) )
def retry-pnpm-install [package_dir: string, max_retries: int] {
  mut attempt = 0
  mut success = false
  mut encountered_eagain = false
  
  while ($attempt < $max_retries) and (not $success) {
    $attempt = ($attempt + 1)
    
    if $attempt > 1 {
      print $"Attempt ($attempt)/($max_retries) for pnpm install in ($package_dir)"
    }
    
    cd $package_dir
    
    # Run pnpm install and capture all output
    # The 'complete' command automatically captures both stdout and stderr
    let pnpm_result = (pnpm install | complete)
    
    cd ..
    
    if $pnpm_result.exit_code == 0 {
      $success = true
      if $attempt > 1 {
        print $"Successfully installed after ($attempt) attempts"
      }
    } else {
      # Combine stdout and stderr into single text
      # Note: stdout and stderr from 'complete' are already strings, not lists
      let stdout_text = (try {
        $pnpm_result.stdout | default ""
      } catch {
        ""
      })
      let stderr_text = (try {
        $pnpm_result.stderr | default ""
      } catch {
        ""
      })
      
      let output_text = $"($stdout_text)\n($stderr_text)"
      
      # Check for EAGAIN errors in the output (case-insensitive)
      let lower_output = ($output_text | str downcase)
      let has_eagain = ($lower_output | str contains "eagain")
      let has_err_pnpm_eagain = ($lower_output | str contains "err_pnpm_eagain")
      let is_eagain = ($has_eagain or $has_err_pnpm_eagain)
      
      if $is_eagain {
        $encountered_eagain = true
        print $"EAGAIN error detected on attempt ($attempt)/($max_retries)"
        let error_lines = ($output_text | lines | where {|l| ($l | str downcase | str contains "eagain")} | last 3)
        if ($error_lines | length) > 0 {
          print ($error_lines | str join "\n")
        }
        if $attempt < $max_retries {
          print $"Retrying in 1 second..."
          sleep 1sec
        } else {
          print $"Max retries reached, giving up"
        }
      } else {
        # Non-retryable error - show last few lines of output
        print $"Non-retryable error on attempt ($attempt)"
        let error_preview = ($output_text | lines | last 5 | str join "\n")
        if ($error_preview | str length) > 0 {
          print $error_preview
        } else {
          print $"Exit code: ($pnpm_result.exit_code)"
        }
        break
      }
    }
  }
  
  { success: $success, attempts: $attempt, was_eagain: $encountered_eagain }
}

def build-package [package_name: string, output_dir: string, retry_count: int] {
  print $"Building package: ($package_name)"
  
  let package_path = $package_name
  let makefile_path = $"($package_path)/Makefile"
  let package_json_path = $"($package_path)/package.json"
  
  # Check if Makefile exists and has release target
  let has_makefile = (try {
    if ($makefile_path | path exists) {
      let makefile_content = (open $makefile_path | lines)
      let matching_lines = ($makefile_content | each {|line| if ($line | str contains "release:") { $line } else { null }} | compact)
      ($matching_lines | length) > 0
    } else {
      false
    }
  } catch {
    false
  })
  
  if not $has_makefile {
    print $"Skipping ($package_name): No release target in Makefile"
    return
  }
  
  # Install dependencies with retry logic if package.json exists
  let has_package_json = ($package_json_path | path exists)
  if $has_package_json {
    let install_result = (retry-pnpm-install $package_path $retry_count)
    
    if not $install_result.success {
      let attempts_made = $install_result.attempts
      if $install_result.was_eagain {
        print $"Warning: Failed to install dependencies for ($package_name) after ($attempts_made) attempts due to EAGAIN errors, skipping..."
      } else {
        print "Warning: Failed to install dependencies for " + $package_name + " (non-retryable error), skipping..."
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
  
  # Find all directories, excluding .git, .github, and current dir
  let exclude_dirs = [".", "..", ".git", ".github"]
  let packages = (ls -a 
    | where type == "dir" 
    | each {|dir| 
        let is_excluded = ($exclude_dirs | each {|ex| if $ex == $dir.name { true } else { false }} | any {|v| $v == true})
        if not $is_excluded { $dir.name } else { null }
      }
    | compact)
  
  for package in $packages {
    build-package $package $output_dir $retry_count
  }
  
  cd ..
  
  print "Finished building all packages"
}
