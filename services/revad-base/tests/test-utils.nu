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
# Tests individual utility functions in isolation to verify correct behavior

use ../scripts/lib/utils.nu [replace_in_file, validate_placeholder, get_env_or_default, process_placeholders]

# Test replace_in_file function
# Verifies that string replacement works correctly in files
def test_replace_in_file [] {
  print "Testing replace_in_file..."
  
  let test_file = "/tmp/test_replace.txt"
  "hello world\nfoo bar\nhello again" | save -f $test_file
  
  replace_in_file $test_file "hello" "hi"
  
  let content = (open --raw $test_file)
  let expected = "hi world\nfoo bar\nhi again"
  
  if $content == $expected {
    print "  [PASS] replace_in_file: PASSED"
    rm -f $test_file
    return true
  } else {
    print $"  [FAIL] replace_in_file: FAILED (expected: ($expected), got: ($content))"
    rm -f $test_file
    return false
  }
}

# Test validate_placeholder function
# Verifies placeholder syntax validation for various formats
def test_validate_placeholder [] {
  print "Testing validate_placeholder..."
  mut passed = 0
  mut failed = 0
  
  # Test simple placeholder
  let result1 = (validate_placeholder "{{placeholder:name}}")
  if $result1 != null and $result1.name == "name" and $result1.subname == null {
    print "  [PASS] Simple placeholder: PASSED"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Simple placeholder: FAILED (got: " + ($result1 | to json) + ")"
    $failed = ($failed + 1)
  }
  
  # Test placeholder with subname
  let result2 = (validate_placeholder "{{placeholder:name.subname}}")
  if $result2 != null and $result2.name == "name" and $result2.subname == "subname" {
    print "  [PASS] Placeholder with subname: PASSED"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Placeholder with subname: FAILED (got: " + ($result2 | to json) + ")"
    $failed = ($failed + 1)
  }
  
  # Test placeholder with default
  let result3 = (validate_placeholder "{{placeholder:name:default-value}}")
  if $result3 != null and $result3.name == "name" and $result3.default == "default-value" {
    print "  [PASS] Placeholder with default: PASSED"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Placeholder with default: FAILED (got: " + ($result3 | to json) + ")"
    $failed = ($failed + 1)
  }
  
  # Test placeholder with subname and default
  let result4 = (validate_placeholder "{{placeholder:name.subname:default-value}}")
  if $result4 != null and $result4.name == "name" and $result4.subname == "subname" and $result4.default == "default-value" {
    print "  [PASS] Placeholder with subname and default: PASSED"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Placeholder with subname and default: FAILED (got: " + ($result4 | to json) + ")"
    $failed = ($failed + 1)
  }
  
  # Test invalid placeholder (no prefix)
  let result5 = (validate_placeholder "{{name}}")
  if $result5 == null {
    print "  [PASS] Invalid placeholder (no prefix): PASSED"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Invalid placeholder (no prefix): FAILED (should be null, got: " + ($result5 | to json) + ")"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test get_env_or_default function
# Verifies environment variable retrieval with default fallback values
def test_get_env_or_default [] {
  print "Testing get_env_or_default..."
  mut passed = 0
  mut failed = 0
  
  # Test with existing env var
  $env.TEST_VAR = "test-value"
  let result1 = (get_env_or_default "TEST_VAR" "default")
  if $result1 == "test-value" {
    print "  [PASS] Existing env var: PASSED"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Existing env var: FAILED (expected: test-value, got: ($result1))"
    $failed = ($failed + 1)
  }
  
  # Test with non-existing env var
  let result2 = (get_env_or_default "NON_EXISTENT_VAR" "default-value")
  if $result2 == "default-value" {
    print "  [PASS] Non-existing env var: PASSED"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Non-existing env var: FAILED (expected: default-value, got: ($result2))"
    $failed = ($failed + 1)
  }
  
  # Test with empty default
  let result3 = (get_env_or_default "ANOTHER_NON_EXISTENT" "")
  if $result3 == "" {
    print "  [PASS] Empty default: PASSED"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Empty default: FAILED (expected: empty, got: ($result3))"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test process_placeholders function
# Verifies placeholder processing and replacement in configuration files
def test_process_placeholders [] {
  print "Testing process_placeholders..."
  
  let test_file = "/tmp/test_placeholders.txt"
  # Create file with actual newlines
  let content = "host = {{placeholder:host:localhost}}
port = {{placeholder:port:8080}}
name = {{placeholder:name.subname:default}}
missing = {{placeholder:missing}}"
  $content | save -f $test_file
  
  let placeholder_map = {
    "host": "example.com"
    "port": "443"
    "name.subname": "custom-value"
  }
  
  process_placeholders $test_file $placeholder_map
  
  let result = (open --raw $test_file)
  let expected = "host = example.com
port = 443
name = custom-value
missing = {{placeholder:missing}}"
  
  # Normalize line endings for comparison
  let result_norm = ($result | str replace -a "\r\n" "\n")
  let expected_norm = ($expected | str replace -a "\r\n" "\n")
  
  if $result_norm == $expected_norm {
    print "  [PASS] process_placeholders: PASSED"
    rm -f $test_file
    return true
  } else {
    print "  [FAIL] process_placeholders: FAILED"
    print "    Expected: " + $expected_norm
    print "    Got:      " + $result_norm
    rm -f $test_file
    return false
  }
}

# Main test runner
# Executes all utility function tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_replace_in_file)
  if $test1 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  let test2 = (test_validate_placeholder)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_get_env_or_default)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_process_placeholders)
  if $test4 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}

