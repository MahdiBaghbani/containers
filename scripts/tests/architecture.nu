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

# Architecture enforcement tests
# Ensures CLI pattern: dockypody.nu routes through domain-local cli.nu files

use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  let verbose_flag = $verbose
  
  print "Architecture Enforcement Tests\n"
  
  # Test 1: No flat .nu files under scripts/lib/
  let test1 = (run-test "No flat .nu files in scripts/lib/" {
    let lib_path = "scripts/lib"
    
    # Get all files directly under scripts/lib/ (not in subdirectories)
    let flat_files = (ls $lib_path 
      | where type == "file" 
      | where {|f| ($f.name | str ends-with ".nu")}
      | get name)
    
    if ($flat_files | is-empty) {
      true
    } else {
      let file_list = ($flat_files | str join ", ")
      error make {msg: $"Found flat .nu files in scripts/lib/: ($file_list). All .nu files must be in domain subdirectories."}
    }
  } $verbose_flag)
  
  # Test 2: All entries in scripts/lib/ are directories
  let test2 = (run-test "scripts/lib/ contains only directories" {
    let lib_path = "scripts/lib"
    
    let non_dirs = (ls $lib_path 
      | where type != "dir"
      | get name)
    
    if ($non_dirs | is-empty) {
      true
    } else {
      let items = ($non_dirs | str join ", ")
      error make {msg: $"Found non-directory items in scripts/lib/: ($items)"}
    }
  } $verbose_flag)
  
  # Test 3: Expected domain directories exist
  let test3 = (run-test "Required domain directories exist" {
    let lib_path = "scripts/lib"
    let required_domains = ["build", "ci", "core", "docs", "manifest", "platforms", "registries", "services", "test", "tls", "validate"]
    
    let existing = (ls $lib_path | where type == "dir" | get name | each {|p| $p | path basename})
    
    let missing = ($required_domains | where {|d| not ($d in $existing)})
    
    if ($missing | is-empty) {
      true
    } else {
      let list = ($missing | str join ", ")
      error make {msg: $"Missing required domain directories: ($list)"}
    }
  } $verbose_flag)
  
  # Test 4: Only dockypody.nu at scripts/ root (no other .nu files)
  let test4 = (run-test "Only dockypody.nu at scripts/ root" {
    let scripts_path = "scripts"
    
    # Get all .nu files directly under scripts/ (not in subdirectories)
    let nu_files = (ls $scripts_path 
      | where type == "file" 
      | where {|f| ($f.name | str ends-with ".nu")}
      | get name
      | each {|p| $p | path basename})
    
    let allowed = ["dockypody.nu"]
    let extra_files = ($nu_files | where {|f| not ($f in $allowed)})
    
    if ($extra_files | is-empty) {
      true
    } else {
      let file_list = ($extra_files | str join ", ")
      error make {msg: $"Found extra .nu files at scripts/ root: ($file_list). Only dockypody.nu is allowed."}
    }
  } $verbose_flag)
  
  # Test 5: CLI domains have cli.nu files
  let test5 = (run-test "CLI domains have cli.nu files" {
    let lib_path = "scripts/lib"
    # Domains that must have CLI entrypoints
    let cli_domains = ["build", "ci", "docs", "registries", "services", "test", "tls", "validate"]
    
    let missing_clis = ($cli_domains | where {|domain|
      let cli_path = $"($lib_path)/($domain)/cli.nu"
      not ($cli_path | path exists)
    })
    
    if ($missing_clis | is-empty) {
      true
    } else {
      let list = ($missing_clis | str join ", ")
      error make {msg: $"Missing cli.nu in domains: ($list)"}
    }
  } $verbose_flag)
  
  # Collect results
  let results = [$test1, $test2, $test3, $test4, $test5]
  
  print-test-summary $results
  
  if ($results | all {|r| $r}) {
    exit 0
  } else {
    exit 1
  }
}
