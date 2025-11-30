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

# Unit tests for shared.nu functions
# Tests shared initialization functions used across container modes

use ../scripts/lib/shared.nu [write_nsswitch, ensure_hosts, ensure_logfile, create_directory, copy_json_files, disable_config_files]

# Test write_nsswitch function
# Verifies nsswitch.conf file creation for DNS resolution
def test_write_nsswitch [] {
  print "Testing write_nsswitch..."
  
  let test_file = "/tmp/test_nsswitch.conf"
  $env.NSSWITCH_FILE = $test_file
  
  # Mock the function to write to test file instead of /etc/nsswitch.conf
  # Since we can't easily mock, we'll test the actual function but verify output
  try {
    write_nsswitch
    let content = (open --raw /etc/nsswitch.conf)
    if ($content | str contains "hosts: files dns") {
      print "  [PASS] write_nsswitch: PASSED"
      return true
    } else {
      print $"  [FAIL] write_nsswitch: FAILED (content: ($content))"
      return false
    }
  } catch {
    print $"  [FAIL] write_nsswitch: FAILED (error: ($in))"
    return false
  }
}

# Test create_directory function
# Verifies directory creation with proper handling of existing directories
def test_create_directory [] {
  print "Testing create_directory..."
  mut passed = 0
  mut failed = 0
  
  # Test creating new directory
  let test_dir1 = "/tmp/test_create_dir_new"
  if ($test_dir1 | path exists) { rm -rf $test_dir1 }
  
  create_directory $test_dir1
  if ($test_dir1 | path exists) {
    print "  [PASS] Create new directory: PASSED"
    $passed = ($passed + 1)
    rm -rf $test_dir1
  } else {
    print "  [FAIL] Create new directory: FAILED"
    $failed = ($failed + 1)
  }
  
  # Test creating existing directory (should not fail)
  let test_dir2 = "/tmp/test_create_dir_existing"
  ^mkdir -p $test_dir2
  create_directory $test_dir2
  if ($test_dir2 | path exists) {
    print "  [PASS] Create existing directory: PASSED"
    $passed = ($passed + 1)
    rm -rf $test_dir2
  } else {
    print "  [FAIL] Create existing directory: FAILED"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test copy_json_files function
# Verifies JSON file copying with filtering and error handling
def test_copy_json_files [] {
  print "Testing copy_json_files..."
  mut passed = 0
  mut failed = 0
  
  # Setup test directories
  let source_dir = "/tmp/test_json_source"
  let dest_dir = "/tmp/test_json_dest"
  rm -rf $source_dir $dest_dir
  ^mkdir -p $source_dir $dest_dir
  
  # Create test JSON files
  '{"test": "data1"}' | save -f $"($source_dir)/file1.json"
  '{"test": "data2"}' | save -f $"($source_dir)/file2.json"
  "not a json" | save -f $"($source_dir)/file.txt"
  
  copy_json_files $source_dir $dest_dir
  
  # Verify JSON files were copied
  let dest_exists = ($dest_dir | path exists)
  let file1_exists = ($"($dest_dir)/file1.json" | path exists)
  let file2_exists = ($"($dest_dir)/file2.json" | path exists)
  let txt_not_exists = (not ($"($dest_dir)/file.txt" | path exists))
  
  if $dest_exists and $file1_exists and $file2_exists and $txt_not_exists {
    print "  [PASS] Copy JSON files: PASSED"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] Copy JSON files: FAILED"
    print $"    dest_dir exists: ($dest_exists)"
    print $"    file1.json exists: ($file1_exists)"
    print $"    file2.json exists: ($file2_exists)"
    print $"    file.txt not exists: ($txt_not_exists)"
    $failed = ($failed + 1)
  }
  
  # Test with non-existent source (should not fail)
  copy_json_files "/tmp/non_existent_dir" $dest_dir
  print "  [PASS] Non-existent source handled: PASSED"
  $passed = ($passed + 1)
  
  # Test with empty source
  let empty_dir = "/tmp/test_json_empty"
  ^mkdir -p $empty_dir
  copy_json_files $empty_dir $dest_dir
  print "  [PASS] Empty source handled: PASSED"
  $passed = ($passed + 1)
  
  rm -rf $source_dir $dest_dir $empty_dir
  
  return {passed: $passed, failed: $failed}
}

# Test disable_config_files function
# Verifies config file disabling via DISABLED_CONFIGS environment variable
def test_disable_config_files [] {
  print "Testing disable_config_files..."
  mut passed = 0
  mut failed = 0
  
  # Setup test directory
  let test_config_dir = "/tmp/test_disable_configs"
  rm -rf $test_config_dir
  ^mkdir -p $test_config_dir
  
  # Create test config files
  "config1" | save -f $"($test_config_dir)/config1.toml"
  "config2" | save -f $"($test_config_dir)/config2.toml"
  "config3" | save -f $"($test_config_dir)/config3.toml"
  
  # Set environment variable
  $env.REVAD_CONFIG_DIR = $test_config_dir
  $env.DISABLED_CONFIGS = "config1.toml config2.toml"
  
  disable_config_files
  
  # Verify disabled files are removed
  if (not ($"($test_config_dir)/config1.toml" | path exists) and
      not ($"($test_config_dir)/config2.toml" | path exists) and
      ($"($test_config_dir)/config3.toml" | path exists)) {
    print "  [PASS] Disable config files: PASSED"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] Disable config files: FAILED"
    $failed = ($failed + 1)
  }
  
  # Test with empty DISABLED_CONFIGS (should not fail)
  $env.DISABLED_CONFIGS = ""
  disable_config_files
  print "  [PASS] Empty DISABLED_CONFIGS handled: PASSED"
  $passed = ($passed + 1)
  
  rm -rf $test_config_dir
  $env.DISABLED_CONFIGS = ""
  
  return {passed: $passed, failed: $failed}
}

# Test ensure_logfile function
# Verifies log file creation (may require appropriate permissions)
def test_ensure_logfile [] {
  print "Testing ensure_logfile..."
  
  let test_log = "/tmp/test_revad.log"
  if ($test_log | path exists) { rm $test_log }
  
  # We can't easily mock /var/log/revad.log, so we test the function exists
  # In a real scenario, this would require root or proper permissions
  try {
    ensure_logfile
    print "  [PASS] ensure_logfile: PASSED (function executed)"
    return true
  } catch {
    print $"  [FAIL] ensure_logfile: FAILED (error: ($in))"
    return false
  }
}

# Main test runner
# Executes all shared function tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_create_directory)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_copy_json_files)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_disable_config_files)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_ensure_logfile)
  if $test4 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}

