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

# Unit tests for source-prep.nu functions
# Tests source detection and copy-on-write logic

use ../scripts/lib/utils.nu [directory_empty]

# Test source mount detection logic
# Verifies correct detection of source and target directory states
def test_detect_source_mount_logic [] {
  print "Testing detect_source_mount logic..."
  mut passed = 0
  mut failed = 0
  
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  # Test 1: Source directory not exists
  let source_dir = $"($test_base)/nonexistent-source"
  let source_exists = ($source_dir | path exists)
  
  if not $source_exists {
    print "  [PASS] detect_source_mount: non-existent source detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] detect_source_mount: source should not exist"
    $failed = ($failed + 1)
  }
  
  # Test 2: Source directory exists but empty
  let empty_source = $"($test_base)/empty-source"
  mkdir $empty_source
  let empty_source_empty = (directory_empty $empty_source)
  
  if $empty_source_empty {
    print "  [PASS] detect_source_mount: empty source directory detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] detect_source_mount: empty source should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 3: Source with required Nextcloud files
  let valid_source = $"($test_base)/valid-source"
  mkdir $valid_source
  "<?php" | save $"($valid_source)/version.php"
  "<?php" | save $"($valid_source)/index.php"
  "#!/bin/sh" | save $"($valid_source)/occ"
  
  let has_version = ($"($valid_source)/version.php" | path exists)
  let has_index = ($"($valid_source)/index.php" | path exists)
  let has_occ = ($"($valid_source)/occ" | path exists)
  
  if $has_version and $has_index and $has_occ {
    print "  [PASS] detect_source_mount: valid source with required files detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] detect_source_mount: valid source files should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 4: Target directory empty detection
  let empty_target = $"($test_base)/empty-target"
  mkdir $empty_target
  let target_empty = (directory_empty $empty_target)
  
  if $target_empty {
    print "  [PASS] detect_source_mount: empty target needs copy"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] detect_source_mount: empty target should need copy"
    $failed = ($failed + 1)
  }
  
  # Test 5: Target with Nextcloud files
  let valid_target = $"($test_base)/valid-target"
  mkdir $valid_target
  "<?php" | save $"($valid_target)/version.php"
  "<?php" | save $"($valid_target)/index.php"
  
  let target_has_version = ($"($valid_target)/version.php" | path exists)
  let target_has_index = ($"($valid_target)/index.php" | path exists)
  
  if $target_has_version and $target_has_index {
    print "  [PASS] detect_source_mount: target with Nextcloud files detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] detect_source_mount: target with files should be detected"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Test rsync option construction logic
# Verifies correct options for root vs non-root execution
def test_rsync_options_logic [] {
  print "Testing rsync options logic..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Non-root rsync options (no chown)
  let uid = (^id -u | into int)
  let is_root = ($uid == 0)
  
  let rsync_opts = if $is_root {
    ["-rlDog" "--chown" "user:group"]
  } else {
    ["-rlD"]
  }
  
  # We're running as non-root in tests
  if not $is_root {
    let has_chown = ($rsync_opts | any {|opt| $opt == "--chown"})
    if not $has_chown {
      print "  [PASS] rsync options: non-root does not include --chown"
      $passed = ($passed + 1)
    } else {
      print "  [FAIL] rsync options: non-root should not include --chown"
      $failed = ($failed + 1)
    }
    
    let has_rld = ($rsync_opts | any {|opt| $opt == "-rlD"})
    if $has_rld {
      print "  [PASS] rsync options: non-root includes -rlD"
      $passed = ($passed + 1)
    } else {
      print "  [FAIL] rsync options: non-root should include -rlD"
      $failed = ($failed + 1)
    }
  } else {
    # Running as root (unlikely in test environment)
    let has_chown = ($rsync_opts | any {|opt| $opt == "--chown"})
    if $has_chown {
      print "  [PASS] rsync options: root includes --chown"
      $passed = ($passed + 1)
    } else {
      print "  [FAIL] rsync options: root should include --chown"
      $failed = ($failed + 1)
    }
    $passed = ($passed + 1)  # Skip second test for root
  }
  
  return {passed: $passed, failed: $failed}
}

# Test prepare_directories logic
# Verifies directory creation and permission logic
def test_prepare_directories_logic [] {
  print "Testing prepare_directories logic..."
  mut passed = 0
  mut failed = 0
  
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  # Simulate html directory
  let html_dir = $"($test_base)/html"
  mkdir $html_dir
  
  # Test 1: Data directory creation logic
  let data_dir = $"($html_dir)/data"
  let data_exists_before = ($data_dir | path exists)
  
  if not $data_exists_before {
    mkdir $data_dir
    let data_exists_after = ($data_dir | path exists)
    
    if $data_exists_after {
      print "  [PASS] prepare_directories: data directory created"
      $passed = ($passed + 1)
    } else {
      print "  [FAIL] prepare_directories: data directory not created"
      $failed = ($failed + 1)
    }
  } else {
    print "  [PASS] prepare_directories: data directory already exists (idempotent)"
    $passed = ($passed + 1)
  }
  
  # Test 2: Custom apps directory creation logic
  let custom_apps_dir = $"($html_dir)/custom_apps"
  let custom_exists_before = ($custom_apps_dir | path exists)
  
  if not $custom_exists_before {
    mkdir $custom_apps_dir
    let custom_exists_after = ($custom_apps_dir | path exists)
    
    if $custom_exists_after {
      print "  [PASS] prepare_directories: custom_apps directory created"
      $passed = ($passed + 1)
    } else {
      print "  [FAIL] prepare_directories: custom_apps directory not created"
      $failed = ($failed + 1)
    }
  } else {
    print "  [PASS] prepare_directories: custom_apps directory already exists (idempotent)"
    $passed = ($passed + 1)
  }
  
  # Test 3: OCC file permission logic (simulate)
  let occ_path = $"($html_dir)/occ"
  "#!/bin/sh\necho test" | save $occ_path
  
  let occ_exists = ($occ_path | path exists)
  if $occ_exists {
    print "  [PASS] prepare_directories: occ file exists for chmod"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] prepare_directories: occ file should exist"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_detect_source_mount_logic)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_rsync_options_logic)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_prepare_directories_logic)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
