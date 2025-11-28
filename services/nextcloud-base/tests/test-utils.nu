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

# Unit tests for utils.nu functions
# Tests utility functions in isolation

use ../scripts/lib/utils.nu [detect_user_group, directory_empty, file_env, get_env_or_default]

# Test detect_user_group function
# Verifies user/group detection for current user context
def test_detect_user_group [] {
  print "Testing detect_user_group..."
  mut passed = 0
  mut failed = 0
  
  # Test: Function returns a record with expected fields
  let result = (detect_user_group)
  
  # Check that result has required fields
  let has_user = (try { $result.user; true } catch { false })
  let has_group = (try { $result.group; true } catch { false })
  let has_uid = (try { $result.uid; true } catch { false })
  let has_gid = (try { $result.gid; true } catch { false })
  
  if $has_user and $has_group and $has_uid and $has_gid {
    print "  [PASS] detect_user_group returns record with all fields"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] detect_user_group missing fields"
    $failed = ($failed + 1)
  }
  
  # Test: UID/GID are integers
  let uid_is_int = (($result.uid | describe) == "int")
  let gid_is_int = (($result.gid | describe) == "int")
  
  if $uid_is_int and $gid_is_int {
    print "  [PASS] detect_user_group uid/gid are integers"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] detect_user_group uid/gid types incorrect: uid=($result.uid | describe), gid=($result.gid | describe)"
    $failed = ($failed + 1)
  }
  
  # Test: user/group are non-empty strings
  let user_valid = (($result.user | str length) > 0)
  let group_valid = (($result.group | str length) > 0)
  
  if $user_valid and $group_valid {
    print "  [PASS] detect_user_group user/group are non-empty strings"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] detect_user_group user/group empty: user='($result.user)', group='($result.group)'"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test directory_empty function
# Verifies correct detection of empty, non-empty, and non-existent directories
def test_directory_empty [] {
  print "Testing directory_empty..."
  mut passed = 0
  mut failed = 0
  
  # Create unique test directory
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  # Test 1: Empty directory returns true
  let empty_dir = $"($test_base)/empty"
  mkdir $empty_dir
  
  let result1 = (directory_empty $empty_dir)
  if $result1 {
    print "  [PASS] directory_empty: empty directory returns true"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] directory_empty: empty directory should return true"
    $failed = ($failed + 1)
  }
  
  # Test 2: Non-empty directory returns false
  let nonempty_dir = $"($test_base)/nonempty"
  mkdir $nonempty_dir
  "test content" | save $"($nonempty_dir)/file.txt"
  
  let result2 = (directory_empty $nonempty_dir)
  if not $result2 {
    print "  [PASS] directory_empty: non-empty directory returns false"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] directory_empty: non-empty directory should return false"
    $failed = ($failed + 1)
  }
  
  # Test 3: Non-existent directory returns true
  let nonexistent_dir = $"($test_base)/nonexistent"
  
  let result3 = (directory_empty $nonexistent_dir)
  if $result3 {
    print "  [PASS] directory_empty: non-existent directory returns true"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] directory_empty: non-existent directory should return true"
    $failed = ($failed + 1)
  }
  
  # Test 4: Directory with only hidden files returns false
  let hidden_dir = $"($test_base)/hidden"
  mkdir $hidden_dir
  "hidden content" | save $"($hidden_dir)/.hidden"
  
  let result4 = (directory_empty $hidden_dir)
  if not $result4 {
    print "  [PASS] directory_empty: directory with hidden files returns false"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] directory_empty: directory with hidden files should return false"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Test file_env function
# Verifies Docker secrets support and environment variable handling
def test_file_env [] {
  print "Testing file_env..."
  mut passed = 0
  mut failed = 0
  
  # Create test directory for file-based secrets
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  # Test 1: Direct env var retrieval
  $env.TEST_FILE_ENV_VAR = "direct-value"
  let result1 = (file_env "TEST_FILE_ENV_VAR" "default")
  if $result1 == "direct-value" {
    print "  [PASS] file_env: direct env var retrieval"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] file_env: direct env var expected 'direct-value', got '($result1)'"
    $failed = ($failed + 1)
  }
  
  # Clean up env var
  hide-env TEST_FILE_ENV_VAR
  
  # Test 2: File-based secret retrieval (VAR_FILE pattern)
  let secret_file = $"($test_base)/secret.txt"
  "file-secret-value" | save $secret_file
  $env.TEST_SECRET_FILE = $secret_file
  
  let result2 = (file_env "TEST_SECRET" "default")
  if $result2 == "file-secret-value" {
    print "  [PASS] file_env: file-based secret retrieval"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] file_env: file-based secret expected 'file-secret-value', got '($result2)'"
    $failed = ($failed + 1)
  }
  
  # Clean up env var
  hide-env TEST_SECRET_FILE
  
  # Test 3: Default value fallback
  let result3 = (file_env "NONEXISTENT_VAR" "fallback-default")
  if $result3 == "fallback-default" {
    print "  [PASS] file_env: default value fallback"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] file_env: default fallback expected 'fallback-default', got '($result3)'"
    $failed = ($failed + 1)
  }
  
  # Test 4: Empty default works
  let result4 = (file_env "ANOTHER_NONEXISTENT" "")
  if $result4 == "" {
    print "  [PASS] file_env: empty default works"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] file_env: empty default expected '', got '($result4)'"
    $failed = ($failed + 1)
  }
  
  # Test 5: File content is trimmed
  let secret_file_whitespace = $"($test_base)/secret-whitespace.txt"
  "  trimmed-value  \n" | save $secret_file_whitespace
  $env.TEST_TRIM_FILE = $secret_file_whitespace
  
  let result5 = (file_env "TEST_TRIM" "default")
  if $result5 == "trimmed-value" {
    print "  [PASS] file_env: file content is trimmed"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] file_env: trimmed expected 'trimmed-value', got '($result5)'"
    $failed = ($failed + 1)
  }
  
  # Clean up env var
  hide-env TEST_TRIM_FILE
  
  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Test get_env_or_default function
# Verifies environment variable retrieval with default fallback
def test_get_env_or_default [] {
  print "Testing get_env_or_default..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Existing env var returns value
  $env.TEST_GET_ENV = "test-value"
  let result1 = (get_env_or_default "TEST_GET_ENV" "default")
  if $result1 == "test-value" {
    print "  [PASS] get_env_or_default: existing env var returns value"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] get_env_or_default: expected 'test-value', got '($result1)'"
    $failed = ($failed + 1)
  }
  
  # Clean up env var
  hide-env TEST_GET_ENV
  
  # Test 2: Non-existing env var returns default
  let result2 = (get_env_or_default "NONEXISTENT_ENV_VAR" "default-value")
  if $result2 == "default-value" {
    print "  [PASS] get_env_or_default: non-existing env var returns default"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] get_env_or_default: expected 'default-value', got '($result2)'"
    $failed = ($failed + 1)
  }
  
  # Test 3: Empty default works
  let result3 = (get_env_or_default "ANOTHER_NONEXISTENT" "")
  if $result3 == "" {
    print "  [PASS] get_env_or_default: empty default works"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] get_env_or_default: expected '', got '($result3)'"
    $failed = ($failed + 1)
  }
  
  # Test 4: Empty env var value is returned (not default)
  $env.TEST_EMPTY_VAR = ""
  let result4 = (get_env_or_default "TEST_EMPTY_VAR" "default")
  if $result4 == "" {
    print "  [PASS] get_env_or_default: empty env var returns empty (not default)"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] get_env_or_default: expected '', got '($result4)'"
    $failed = ($failed + 1)
  }
  
  # Clean up env var
  hide-env TEST_EMPTY_VAR
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_detect_user_group)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_directory_empty)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_file_env)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_get_env_or_default)
  $total_passed = ($total_passed + $test4.passed)
  $total_failed = ($total_failed + $test4.failed)
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
