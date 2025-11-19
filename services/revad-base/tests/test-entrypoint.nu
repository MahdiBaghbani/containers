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

# Unit tests for entrypoint-init.nu functions
# Tests container mode string parsing functions

# Copy of extract_dataprovider_type from entrypoint-init.nu
# For example, "dataprovider-localhome" -> "localhome"
# Returns null if mode does not start with "dataprovider-"
def extract_dataprovider_type [mode: string] {
  if ($mode | str starts-with "dataprovider-") {
    # Extract substring after "dataprovider-" (13 characters)
    ($mode | str substring 13..)
  } else {
    null
  }
}

# Copy of extract_authprovider_type from entrypoint-init.nu
# For example, "authprovider-oidc" -> "oidc"
# Returns null if mode does not start with "authprovider-"
def extract_authprovider_type [mode: string] {
  if ($mode | str starts-with "authprovider-") {
    # Extract substring after "authprovider-" (13 characters)
    ($mode | str substring 13..)
  } else {
    null
  }
}

# Test extract_dataprovider_type function
# Verifies that dataprovider type is correctly extracted from container mode string
def test_extract_dataprovider_type [] {
  print "Testing extract_dataprovider_type..."
  
  mut passed = 0
  mut failed = 0
  
  # Test valid dataprovider types
  let test_cases = [
    {input: "dataprovider-localhome", expected: "localhome"},
    {input: "dataprovider-ocm", expected: "ocm"},
    {input: "dataprovider-sciencemesh", expected: "sciencemesh"}
  ]
  
  for test_case in $test_cases {
    let result = (extract_dataprovider_type $test_case.input)
    if $result == $test_case.expected {
      print $"  [PASS] extract_dataprovider_type('($test_case.input)') = '($result)'"
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] extract_dataprovider_type('($test_case.input)') = '($result)' (expected '($test_case.expected)')"
      $failed = ($failed + 1)
    }
  }
  
  # Test invalid inputs (should return null)
  let invalid_cases_null = [
    "gateway",
    "authprovider-oidc",
    "dataprovider",
    ""
  ]
  
  for invalid_input in $invalid_cases_null {
    let result = (extract_dataprovider_type $invalid_input)
    if $result == null {
      print $"  [PASS] extract_dataprovider_type('($invalid_input)') = null"
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] extract_dataprovider_type('($invalid_input)') = '($result)', expected null"
      $failed = ($failed + 1)
    }
  }
  
  # Test edge case: "dataprovider-" returns empty string (will be caught by validation)
  let edge_case = "dataprovider-"
  let result = (extract_dataprovider_type $edge_case)
  if $result == "" {
    print $"  [PASS] extract_dataprovider_type('($edge_case)') = '' - edge case"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] extract_dataprovider_type('($edge_case)') = '($result)', expected ''"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test extract_authprovider_type function
# Verifies that authprovider type is correctly extracted from container mode string
def test_extract_authprovider_type [] {
  print "Testing extract_authprovider_type..."
  
  mut passed = 0
  mut failed = 0
  
  # Test valid authprovider types
  let test_cases = [
    {input: "authprovider-oidc", expected: "oidc"},
    {input: "authprovider-machine", expected: "machine"},
    {input: "authprovider-ocmshares", expected: "ocmshares"}
  ]
  
  for test_case in $test_cases {
    let result = (extract_authprovider_type $test_case.input)
    if $result == $test_case.expected {
      print $"  [PASS] extract_authprovider_type('($test_case.input)') = '($result)'"
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] extract_authprovider_type('($test_case.input)') = '($result)' (expected '($test_case.expected)')"
      $failed = ($failed + 1)
    }
  }
  
  # Test invalid inputs (should return null)
  let invalid_cases_null = [
    "gateway",
    "dataprovider-localhome",
    "authprovider",
    ""
  ]
  
  for invalid_input in $invalid_cases_null {
    let result = (extract_authprovider_type $invalid_input)
    if $result == null {
      print $"  [PASS] extract_authprovider_type('($invalid_input)') = null"
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] extract_authprovider_type('($invalid_input)') = '($result)', expected null"
      $failed = ($failed + 1)
    }
  }
  
  # Test edge case: "authprovider-" returns empty string (will be caught by validation)
  let edge_case = "authprovider-"
  let result = (extract_authprovider_type $edge_case)
  if $result == "" {
    print $"  [PASS] extract_authprovider_type('($edge_case)') = '' - edge case"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] extract_authprovider_type('($edge_case)') = '($result)', expected ''"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
# Executes all entrypoint function tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_extract_dataprovider_type)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_extract_authprovider_type)
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
