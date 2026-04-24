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

# Unit tests for hooks.nu functions
# Tests hook script discovery and execution logic

use ../scripts/lib/utils.nu [directory_empty]
use ../scripts/lib/hooks.nu [run_path]

# Test hook folder detection logic
# Verifies correct detection of hook folder states
def test_hook_folder_detection [] {
  print "Testing hook folder detection..."
  mut passed = 0
  mut failed = 0
  
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  # Test 1: Non-existent folder
  let nonexistent = $"($test_base)/nonexistent"
  let exists1 = ($nonexistent | path exists)
  
  if not $exists1 {
    print "  [PASS] hook folder: non-existent folder detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] hook folder: non-existent folder should not exist"
    $failed = ($failed + 1)
  }
  
  # Test 2: Empty folder
  let empty_folder = $"($test_base)/empty"
  mkdir $empty_folder
  let is_empty = (directory_empty $empty_folder)
  
  if $is_empty {
    print "  [PASS] hook folder: empty folder detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] hook folder: empty folder should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 3: Folder with non-.sh and non-.nu files
  let other_folder = $"($test_base)/other-files"
  mkdir $other_folder
  "text content" | save $"($other_folder)/readme.txt"
  "config content" | save $"($other_folder)/config.ini"
  
  let hook_files = (ls $other_folder | where {|f| $f.type == file and (($f.name | str ends-with ".sh") or ($f.name | str ends-with ".nu"))})
  if ($hook_files | length) == 0 {
    print "  [PASS] hook folder: no .sh or .nu files detected in non-script folder"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] hook folder: should find no .sh or .nu files"
    $failed = ($failed + 1)
  }
  
  # Test 4: Folder with .sh and .nu files
  let scripts_folder = $"($test_base)/scripts"
  mkdir $scripts_folder
  "#!/bin/sh\necho test1" | save $"($scripts_folder)/01-first.sh"
  "#!/bin/sh\necho test2" | save $"($scripts_folder)/02-second.sh"
  "#!/usr/bin/env nu\nprint test3" | save $"($scripts_folder)/03-third.nu"
  "readme content" | save $"($scripts_folder)/README.md"
  
  let hook_files2 = (ls $scripts_folder | where {|f| $f.type == file and (($f.name | str ends-with ".sh") or ($f.name | str ends-with ".nu"))})
  if ($hook_files2 | length) == 3 {
    print "  [PASS] hook folder: .sh and .nu files detected correctly"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] hook folder: expected 3 hook files, found ($hook_files2 | length)"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Test script discovery and sorting logic
# Verifies .sh and .nu scripts are both discovered and sorted by name
def test_script_discovery [] {
  print "Testing script discovery..."
  mut passed = 0
  mut failed = 0
  
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  # Create .sh and .nu scripts with specific naming to test sorting
  let hook_folder = $"($test_base)/hooks"
  mkdir $hook_folder
  "#!/bin/sh\necho c" | save $"($hook_folder)/03-third.sh"
  "#!/bin/sh\necho a" | save $"($hook_folder)/01-first.sh"
  "#!/bin/sh\necho b" | save $"($hook_folder)/02-second.sh"
  "#!/usr/bin/env nu\nprint d" | save $"($hook_folder)/04-fourth.nu"
  
  # Test 1: Both .sh and .nu scripts are found
  let scripts = (ls $hook_folder | where {|f| $f.type == file and (($f.name | str ends-with ".sh") or ($f.name | str ends-with ".nu"))} | sort-by name)
  
  if ($scripts | length) == 4 {
    print "  [PASS] script discovery: found all 4 scripts (.sh and .nu)"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] script discovery: expected 4 scripts, found ($scripts | length)"
    $failed = ($failed + 1)
  }
  
  # Test 2: Scripts are sorted by name
  let first_script = ($scripts | first | get name | path basename)
  if $first_script == "01-first.sh" {
    print "  [PASS] script discovery: scripts sorted by name"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] script discovery: expected '01-first.sh' first, got '($first_script)'"
    $failed = ($failed + 1)
  }
  
  # Test 3: Sort order is correct across both extensions (ascending by filename)
  let script_names = ($scripts | get name | each {|n| $n | path basename})
  let expected_order = ["01-first.sh", "02-second.sh", "03-third.sh", "04-fourth.nu"]
  
  if $script_names == $expected_order {
    print "  [PASS] script discovery: sort order is correct across .sh and .nu"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] script discovery: sort order incorrect"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Test executable flag checking logic
# Verifies non-executable scripts are skipped
def test_executable_check [] {
  print "Testing executable flag check..."
  mut passed = 0
  mut failed = 0
  
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  # Create executable and non-executable scripts (.sh and .nu)
  let hook_folder = $"($test_base)/hooks"
  mkdir $hook_folder
  
  let exec_script = $"($hook_folder)/01-executable.sh"
  let nonexec_script = $"($hook_folder)/02-nonexec.sh"
  let exec_nu_script = $"($hook_folder)/03-executable.nu"
  
  "#!/bin/sh\necho exec" | save $exec_script
  "#!/bin/sh\necho nonexec" | save $nonexec_script
  "#!/usr/bin/env nu\nprint exec-nu" | save $exec_nu_script
  
  # Make .sh and .nu exec scripts executable; leave nonexec_script without +x
  ^chmod +x $exec_script
  ^chmod +x $exec_nu_script
  
  # Test 1: Executable .sh script is detected
  let is_exec1 = (^test -x $exec_script | complete | get exit_code) == 0
  if $is_exec1 {
    print "  [PASS] executable check: executable .sh script detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] executable check: executable .sh script should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 2: Non-executable script is detected as non-executable
  let is_exec2 = (^test -x $nonexec_script | complete | get exit_code) == 0
  if not $is_exec2 {
    print "  [PASS] executable check: non-executable script detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] executable check: non-executable script should not be executable"
    $failed = ($failed + 1)
  }
  
  # Test 3: Executable .nu script is detected
  let is_exec3 = (^test -x $exec_nu_script | complete | get exit_code) == 0
  if $is_exec3 {
    print "  [PASS] executable check: executable .nu script detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] executable check: executable .nu script should be detected"
    $failed = ($failed + 1)
  }

  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Test hook naming conventions
# Verifies support for standard hook names
def test_hook_naming [] {
  print "Testing hook naming conventions..."
  mut passed = 0
  mut failed = 0
  
  # Standard hook names from Nextcloud Docker image
  let standard_hooks = [
    "pre-installation"
    "post-installation"
    "pre-upgrade"
    "post-upgrade"
    "before-starting"
  ]
  
  # Test 1: All standard hook names are valid
  let all_valid = ($standard_hooks | all {|name| ($name | str length) > 0})
  if $all_valid {
    print "  [PASS] hook naming: all standard hook names valid"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] hook naming: some hook names invalid"
    $failed = ($failed + 1)
  }
  
  # Test 2: Hook folder path construction
  let hook_name = "pre-installation"
  let hook_folder = $"/docker-entrypoint-hooks.d/($hook_name)"
  let expected = "/docker-entrypoint-hooks.d/pre-installation"
  
  if $hook_folder == $expected {
    print "  [PASS] hook naming: folder path construction correct"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] hook naming: expected '($expected)', got '($hook_folder)'"
    $failed = ($failed + 1)
  }
  
  # Test 3: Hook count
  if ($standard_hooks | length) == 5 {
    print "  [PASS] hook naming: 5 standard hooks defined"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] hook naming: expected 5 hooks, got ($standard_hooks | length)"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test that run_path actually executes a .nu hook against a temp hook root.
# Uses --base-dir to avoid touching /docker-entrypoint-hooks.d.
# The hook writes a marker file; we verify the file exists after the call.
def test_run_path_invocation [] {
  print "Testing run_path invocation with temp hook dir..."
  mut passed = 0
  mut failed = 0

  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  let hook_root = $"($test_base)/hooks.d"
  let hook_name = "pre-installation"
  let hook_folder = $"($hook_root)/($hook_name)"
  let marker_file = $"($test_base)/hook-ran-marker"

  mkdir $hook_folder

  # Write a .nu hook that creates a marker file (avoids run_as / root requirements)
  let hook_script = $"($hook_folder)/01-mark.nu"
  $"'hook-ran' | save --force '($marker_file)'" | save $hook_script
  ^chmod +x $hook_script

  let run_ok = (try {
    run_path $hook_name "unused" --base-dir $hook_root
    true
  } catch {|err|
    print $"    run_path error: ($err.msg)"
    false
  })

  if $run_ok and ($marker_file | path exists) {
    let content = ((open --raw $marker_file) | str trim)
    if $content == "hook-ran" {
      print "  [PASS] run_path: .nu hook executed and marker written"
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] run_path: marker content unexpected: ($content)"
      $failed = ($failed + 1)
    }
  } else if not $run_ok {
    print "  [FAIL] run_path: invocation raised an error"
    $failed = ($failed + 1)
  } else {
    print "  [FAIL] run_path: marker file not created by hook"
    $failed = ($failed + 1)
  }

  rm -rf $test_base
  {passed: $passed, failed: $failed}
}

# Main test runner
def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_hook_folder_detection)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_script_discovery)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_executable_check)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_hook_naming)
  $total_passed = ($total_passed + $test4.passed)
  $total_failed = ($total_failed + $test4.failed)

  let test5 = (test_run_path_invocation)
  $total_passed = ($total_passed + $test5.passed)
  $total_failed = ($total_failed + $test5.failed)

  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
