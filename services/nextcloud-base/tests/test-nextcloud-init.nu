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

# Unit tests for nextcloud-init.nu functions
# Tests Nextcloud installation and upgrade logic

use ../scripts/lib/nextcloud-init.nu [version_greater]

# Test version_greater function
# Verifies semantic version comparison for upgrade detection
def test_version_greater [] {
  print "Testing version_greater..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Higher version returns true
  let result1 = (version_greater "30.0.0.0" "29.0.0.0")
  if $result1 {
    print "  [PASS] version_greater: 30.0.0.0 > 29.0.0.0"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: 30.0.0.0 should be > 29.0.0.0"
    $failed = ($failed + 1)
  }
  
  # Test 2: Lower version returns false
  let result2 = (version_greater "29.0.0.0" "30.0.0.0")
  if not $result2 {
    print "  [PASS] version_greater: 29.0.0.0 not > 30.0.0.0"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: 29.0.0.0 should not be > 30.0.0.0"
    $failed = ($failed + 1)
  }
  
  # Test 3: Equal versions returns false
  let result3 = (version_greater "30.0.0.0" "30.0.0.0")
  if not $result3 {
    print "  [PASS] version_greater: equal versions return false"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: equal versions should return false"
    $failed = ($failed + 1)
  }
  
  # Test 4: Minor version difference
  let result4 = (version_greater "30.1.0.0" "30.0.0.0")
  if $result4 {
    print "  [PASS] version_greater: 30.1.0.0 > 30.0.0.0"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: 30.1.0.0 should be > 30.0.0.0"
    $failed = ($failed + 1)
  }
  
  # Test 5: Patch version difference
  let result5 = (version_greater "30.0.11.0" "30.0.0.0")
  if $result5 {
    print "  [PASS] version_greater: 30.0.11.0 > 30.0.0.0"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: 30.0.11.0 should be > 30.0.0.0"
    $failed = ($failed + 1)
  }
  
  # Test 6: Build version difference
  let result6 = (version_greater "30.0.0.1" "30.0.0.0")
  if $result6 {
    print "  [PASS] version_greater: 30.0.0.1 > 30.0.0.0"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: 30.0.0.1 should be > 30.0.0.0"
    $failed = ($failed + 1)
  }
  
  # Test 7: Fresh install comparison (0.0.0.0)
  let result7 = (version_greater "30.0.0.0" "0.0.0.0")
  if $result7 {
    print "  [PASS] version_greater: 30.0.0.0 > 0.0.0.0 (fresh install)"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: 30.0.0.0 should be > 0.0.0.0"
    $failed = ($failed + 1)
  }
  
  # Test 8: 0.0.0.0 not greater than anything
  let result8 = (version_greater "0.0.0.0" "30.0.0.0")
  if not $result8 {
    print "  [PASS] version_greater: 0.0.0.0 not > 30.0.0.0"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: 0.0.0.0 should not be > 30.0.0.0"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test version comparison edge cases
# Documents behavior of sort -n based comparison
def test_version_greater_edge_cases [] {
  print "Testing version_greater edge cases..."
  mut passed = 0
  mut failed = 0
  
  # Edge case 1: Single digit vs double digit component
  # Note: sort -n handles this correctly (2 < 10)
  let result1 = (version_greater "30.10.0.0" "30.2.0.0")
  if $result1 {
    print "  [PASS] version_greater: 30.10.0.0 > 30.2.0.0 (numeric sort)"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: 30.10.0.0 should be > 30.2.0.0"
    $failed = ($failed + 1)
  }
  
  # Edge case 2: Leading zeros (if any)
  let result2 = (version_greater "30.0.1.0" "30.0.0.0")
  if $result2 {
    print "  [PASS] version_greater: handles component comparison correctly"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version_greater: component comparison failed"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_version_greater)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_version_greater_edge_cases)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
