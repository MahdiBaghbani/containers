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

# Canonical suite inventory for the non-Docker bundle.
# Single source of truth: test-help and test-cli both derive from this.
const suite_inventory = [
    {name: "architecture",   desc: "Architecture enforcement tests"}
    {name: "manifests",      desc: "Version manifest tests"}
    {name: "services",       desc: "Service configuration tests"}
    {name: "tls",            desc: "TLS certificate and validation tests"}
    {name: "ssh",            desc: "SSH configuration tests"}
    {name: "tag-generation", desc: "Tag generation tests"}
    {name: "build-system",   desc: "Build system tests"}
    {name: "defaults",       desc: "Default value tests"}
    {name: "pull",           desc: "Image pull tests"}
    {name: "validate",       desc: "Validation tests"}
    {name: "registries",     desc: "Registry tests"}
    {name: "ci",             desc: "CI helper and dependency resolution tests"}
    {name: "ghcr-purge",     desc: "GHCR purge desired-tag and decision logic tests"}
    {name: "docs-lint",      desc: "Documentation lint detection and autofix tests"}
    {name: "routed-smoke",   desc: "Routed CLI and Makefile dispatch smoke tests"}
    {name: "cache-shards",   desc: "CI cache shard helper tests"}
    {name: "orchestration",  desc: "Non-Docker build metadata paths (matrix-json, show-build-order)"}
    {name: "dep-contract",   desc: "Dependency tag/key contract tests (dependencies, order, hash)"}
]

# Show test CLI help
export def test-help [] {
  print "Usage: nu scripts/dockypody.nu test [options]"
  print ""
  print "Options:"
  print "  --suite <name>   Test suite to run (default: all)"
  print "  --verbose        Show detailed output"
  print ""
  print "Available suites:"
  print "  all                  Run all non-Docker test suites"
  for s in $suite_inventory {
    print $"  ($s.name | fill -a l -w 20) ($s.desc)"
  }
  print ""
  print "Opt-in suites (excluded from 'all', require Docker daemon):"
  print "  docker-integration   Docker CLI and daemon reachability tests"
  print "    Routed:  DOCKYPODY_DOCKER_INTEGRATION=1 nu scripts/dockypody.nu test --suite docker-integration"
  print "    Direct:  nu scripts/tests/docker-integration.nu --docker"
}

# Test CLI entrypoint - called from dockypody.nu
export def test-cli [
  suite: string = "all",  # Which test suite to run
  verbose: bool = false   # Show detailed output
] {
  print "Running OCM Containers Test Suite\n"

  let test_suites = if $suite == "all" {
    $suite_inventory | get name
  } else {
    [$suite]
  }

  # Run suites and collect results using reduce to avoid mutable variable scope issues
  let results = ($test_suites | reduce --fold {passed: 0, failed: 0, skipped: 0} {|suite_name, acc|
    print $"=== ($suite_name | str upcase) ==="

    let result = (if $verbose {
      nu $"scripts/tests/($suite_name).nu" "--verbose" | complete
    } else {
      nu $"scripts/tests/($suite_name).nu" | complete
    })

    # Detect suites that skipped via the SKIPPED: marker (zero exit, opt-in not set).
    let has_skip_marker = ($result.stdout | lines | any {|l| $l | str starts-with "SKIPPED:"})
    let is_skipped = ($result.exit_code == 0 and $has_skip_marker)

    let next_result = if $result.exit_code != 0 {
      print "FAILED"
      print $result.stderr
      {passed: $acc.passed, failed: ($acc.failed + 1), skipped: $acc.skipped}
    } else if $is_skipped {
      for l in ($result.stdout | str trim | lines) { print $l }
      {passed: $acc.passed, failed: $acc.failed, skipped: ($acc.skipped + 1)}
    } else {
      let counts = ($result.stdout | lines | last 2)
      print $"($counts.0)\n($counts.1)"
      {passed: ($acc.passed + 1), failed: $acc.failed, skipped: $acc.skipped}
    }
    print ""
    $next_result
  })

  print "================================"
  print "Test Summary"
  print "================================"
  print $"Suites:  ($test_suites | length)"
  print $"Passed:  ($results.passed)"
  if $results.skipped > 0 {
    print $"Skipped: ($results.skipped)"
  }
  print $"Failed:  ($results.failed)"

  if $results.failed == 0 {
    if $results.skipped > 0 {
      print $"\nNo test suites failed; ($results.skipped) suite\(s\) skipped"
    } else {
      print "\nAll test suites passed!"
    }
    exit 0
  } else {
    print $"\n($results.failed) test suite\(s\) failed"
    exit 1
  }
}
