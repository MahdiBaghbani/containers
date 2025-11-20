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

# Test utilities

export def print-test-summary [results: list] {
  let total = ($results | length)
  let passed = ($results | where {|r| $r} | length)
  let failed = ($total - $passed)
  
  print "\n================================"
  print "Test Summary"
  print "================================"
  print $"Total:  ($total)"
  print $"Passed: ($passed)"
  print $"Failed: ($failed)"
  
  if $failed == 0 {
    print "\nAll tests passed!"
  } else {
    print $"\n($failed) test\(s\) failed"
  }
}

export def run-test [name: string, test_block: closure, verbose: bool] {
  if $verbose {
    print $"Test: ($name) ..."
  }
  
  let result = (try {
    let block_result = (do $test_block)
    if $block_result == null {
      if not $verbose {
        print $"Test: ($name) ... FAIL (returned null)"
      }
      false
    } else {
      $block_result
    }
  } catch {|err|
    print $"Test: ($name) ... FAIL"
    print $"  Error: ($err.msg)"
    false
  })
  
  if ($result == true) and $verbose {
    print $"  PASS"
  } else if ($result != true) and not $verbose {
    print $"Test: ($name) ... FAIL"
  }
  
  $result
}
