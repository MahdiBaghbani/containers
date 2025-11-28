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

# Test runner for nextcloud-base scripts unit tests

def main [
  --suite: string = "all"       # Which test suite to run (all, utils, nextcloud-init, entrypoint, source-prep, apache-config, redis-config, hooks, post-install)
  --verbose                      # Show detailed output
] {
  print "Running Nextcloud Base Scripts Test Suite\n"
  
  # Get test directory path (works from project root or tests directory)
  let test_dir = (try {
    if ("./services/nextcloud-base/tests" | path exists) {
      "./services/nextcloud-base/tests"
    } else if ("./test-runner.nu" | path exists) {
      "."
    } else {
      error make { msg: "Could not find test directory. Run from project root or tests directory." }
    }
  } catch {
    error make { msg: "Could not determine test directory path" }
  })
  
  let test_suites = if $suite == "all" {
    ["utils", "nextcloud-init", "entrypoint", "source-prep", "apache-config", "redis-config", "hooks", "post-install"]
  } else {
    [$suite]
  }
  
  mut total_passed = 0
  mut total_failed = 0
  mut suites_passed = 0
  mut suites_failed = 0
  
  for suite_name in $test_suites {
    print $"=== ($suite_name | str upcase) ==="
    
    let test_file = $"($test_dir)/test-($suite_name).nu"
    
    # Check if test file exists
    if not ($test_file | path exists) {
      print $"ERROR: Test file not found: ($test_file)"
      $suites_failed = ($suites_failed + 1)
      print ""
      continue
    }
    
    # Run test suite
    let result = (try {
      if $verbose {
        nu $test_file "--verbose" | complete
      } else {
        nu $test_file | complete
      }
    } catch {
      error make { msg: $"Failed to execute test file: ($test_file)" }
    })
    
    if $result.exit_code == 0 {
      # Parse output for summary line
      let output = ($result.stdout | lines)
      let summary_lines = ($output | where {|line| $line | str contains "Tests:"})
      
      if ($summary_lines | length) > 0 {
        let summary_line = ($summary_lines | get 0)
        print $summary_line
        
        # Extract passed/failed counts from summary line
        # Format: "Tests: X passed, Y failed"
        try {
          let parts = ($summary_line | split row " ")
          mut passed_count = 0
          mut failed_count = 0
          
          mut i = 0
          while $i < ($parts | length) {
            if ($parts | get $i) == "passed," {
              $passed_count = (try { ($parts | get ($i - 1) | into int) } catch { 0 })
            } else if ($parts | get $i) == "failed" {
              $failed_count = (try { ($parts | get ($i - 1) | into int) } catch { 0 })
            }
            $i = ($i + 1)
          }
          
          $total_passed = ($total_passed + $passed_count)
          $total_failed = ($total_failed + $failed_count)
        } catch {
          # If parsing fails, just count suite as passed
          print "  (Could not parse test counts)"
        }
      } else {
        print "  (No summary line found)"
      }
      
      $suites_passed = ($suites_passed + 1)
    } else {
      print "FAILED"
      if $verbose {
        print $result.stdout
      }
      if ($result.stderr | str length) > 0 {
        print $result.stderr
      }
      $suites_failed = ($suites_failed + 1)
    }
    print ""
  }
  
  print "================================"
  print "Test Summary"
  print "================================"
  print $"Suites:  ($test_suites | length)"
  print $"Passed: ($suites_passed)"
  print $"Failed: ($suites_failed)"
  if $total_passed > 0 or $total_failed > 0 {
    print $"Tests:  ($total_passed) passed, ($total_failed) failed"
  }
  
  if $suites_failed == 0 {
    print "\nAll test suites passed!"
    exit 0
  } else {
    print $"\n($suites_failed) test suite\(s\) failed"
    exit 1
  }
}
