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

# Test runner for revad-base scripts unit tests

def main [
  --suite: string = "all"       # Which test suite to run (all, utils, shared, gateway, dataprovider, shareproviders, groupuserproviders, entrypoint)
  --verbose                      # Show detailed output
] {
  print "Running Reva Base Scripts Test Suite\n"
  
  let test_suites = if $suite == "all" {
    ["utils", "shared", "gateway", "dataprovider", "shareproviders", "groupuserproviders", "entrypoint"]
  } else {
    [$suite]
  }
  
  mut total_passed = 0
  mut total_failed = 0
  mut total_tests = 0
  
  for suite_name in $test_suites {
    print $"=== ($suite_name | str upcase) ==="
    
    let result = (if $verbose {
      nu $"($env.PWD)/services/revad-base/tests/test-($suite_name).nu" "--verbose" | complete
    } else {
      nu $"($env.PWD)/services/revad-base/tests/test-($suite_name).nu" | complete
    })
    
    if $result.exit_code == 0 {
      let output = ($result.stdout | lines)
      let summary_line = ($output | where {|line| $line | str contains "Tests:"} | get 0)
      print $summary_line
      $total_passed = ($total_passed + 1)
    } else {
      print "FAILED"
      if $verbose {
        print $result.stdout
      }
      print $result.stderr
      $total_failed = ($total_failed + 1)
    }
    print ""
  }
  
  print "================================"
  print "Test Summary"
  print "================================"
  print $"Suites:  ($test_suites | length)"
  print $"Passed: ($total_passed)"
  print $"Failed: ($total_failed)"
  
  if $total_failed == 0 {
    print "\nAll test suites passed!"
    exit 0
  } else {
    print $"\n($total_failed) test suite\(s\) failed"
    exit 1
  }
}
