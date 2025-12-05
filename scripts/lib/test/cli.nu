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

# Test CLI facade - runs test suites
# See docs/reference/cli-reference.md for usage

# Show test CLI help
export def test-help [] {
  print "Usage: nu scripts/dockypody.nu test [options]"
  print ""
  print "Options:"
  print "  --suite <name>   Test suite to run (default: all)"
  print "  --verbose        Show detailed output"
  print ""
  print "Available suites:"
  print "  all              Run all test suites"
  print "  architecture     Architecture enforcement tests"
  print "  manifests        Version manifest tests"
  print "  services         Service configuration tests"
  print "  tls              TLS certificate tests"
  print "  tag-generation   Tag generation tests"
  print "  build-system     Build system tests"
  print "  defaults         Default value tests"
  print "  pull             Image pull tests"
  print "  validate         Validation tests"
  print "  registries       Registry tests"
  print "  ci               CI helper tests"
}

# Test CLI entrypoint - called from dockypody.nu
export def test-cli [
  suite: string = "all",  # Which test suite to run
  verbose: bool = false   # Show detailed output
] {
  print "Running OCM Containers Test Suite\n"
  
  let test_suites = if $suite == "all" {
    ["architecture", "manifests", "services", "tls", "tag-generation", "build-system", "defaults", "pull", "validate", "registries", "ci"]
  } else {
    [$suite]
  }
  
  # Run suites and collect results using reduce to avoid mutable variable scope issues
  let results = ($test_suites | reduce --fold {passed: 0, failed: 0} {|suite_name, acc|
    print $"=== ($suite_name | str upcase) ==="
    
    let result = (if $verbose {
      nu $"scripts/tests/($suite_name).nu" "--verbose" | complete
    } else {
      nu $"scripts/tests/($suite_name).nu" | complete
    })
    
    if $result.exit_code == 0 {
      let counts = ($result.stdout | lines | last 2)
      print $"($counts.0)\n($counts.1)"
      {passed: ($acc.passed + 1), failed: $acc.failed}
    } else {
      print "FAILED"
      print $result.stderr
      {passed: $acc.passed, failed: ($acc.failed + 1)}
    }
    | do {|r| print ""; $r}  # Print newline and return record
  })
  
  print "================================"
  print "Test Summary"
  print "================================"
  print $"Suites:  ($test_suites | length)"
  print $"Passed: ($results.passed)"
  print $"Failed: ($results.failed)"
  
  if $results.failed == 0 {
    print "\nAll test suites passed!"
    exit 0
  } else {
    print $"\n($results.failed) test suite\(s\) failed"
    exit 1
  }
}
