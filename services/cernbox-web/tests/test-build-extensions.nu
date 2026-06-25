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

# Unit tests for build-extensions.nu list parsing and allowlist selection

use ../scripts/build-extensions.nu [
  parse-comma-list
  check-only-list
  plan-packages
  discover-packages
]

def make-fixture [] {
  let root = (mktemp -d)
  mkdir $"($root)/alpha"
  mkdir $"($root)/beta"
  mkdir $"($root)/gamma"
  mkdir $"($root)/.git"
  "not-a-dir" | save -f $"($root)/delta"
  $root
}

def test_parse_comma_list_empty [] {
  print "Testing parse-comma-list empty input..."
  mut passed = 0
  mut failed = 0

  let empty = (parse-comma-list "")
  if ($empty | length) == 0 {
    print "  [PASS] empty string returns empty list"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] empty string should return empty list"
    $failed = ($failed + 1)
  }

  let whitespace = (parse-comma-list "   ")
  if ($whitespace | length) == 0 {
    print "  [PASS] whitespace-only returns empty list"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] whitespace-only should return empty list"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

def test_parse_comma_list_trim [] {
  print "Testing parse-comma-list trimming..."
  mut passed = 0
  mut failed = 0

  let result = (parse-comma-list " alpha , , beta ,  gamma ")
  let expected = ["alpha" "beta" "gamma"]
  if $result == $expected {
    print "  [PASS] trims tokens and drops empty entries"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] expected ($expected | to json), got ($result | to json)"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

def test_check_only_list_duplicates [] {
  print "Testing check-only-list duplicate rejection..."
  mut passed = 0
  mut failed = 0

  let root = (make-fixture)
  let check = (check-only-list ["alpha" "beta" "alpha"] $root)
  rm -rf $root

  if (not $check.valid) and ($check.reason | str contains "duplicate") {
    print "  [PASS] duplicate names rejected"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] expected duplicate rejection, got ($check | to json)"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

def test_check_only_list_missing [] {
  print "Testing check-only-list missing member rejection..."
  mut passed = 0
  mut failed = 0

  let root = (make-fixture)
  let check = (check-only-list ["alpha" "missing-pkg"] $root)
  rm -rf $root

  if (not $check.valid) and ($check.reason | str contains "missing") {
    print "  [PASS] missing allowlist member rejected"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] expected missing rejection, got ($check | to json)"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

def test_plan_packages_allowlist_order [] {
  print "Testing plan-packages allowlist order..."
  mut passed = 0
  mut failed = 0

  let root = (make-fixture)
  let plan = (plan-packages ["gamma" "alpha"] [] $root)
  rm -rf $root

  if $plan.ok and $plan.packages == ["gamma" "alpha"] {
    print "  [PASS] allowlist order preserved"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] expected ordered allowlist, got ($plan | to json)"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

def test_plan_packages_only_ignores_skip [] {
  print "Testing plan-packages --only ignores --skip..."
  mut passed = 0
  mut failed = 0

  let root = (make-fixture)
  let plan = (plan-packages ["alpha" "beta"] ["alpha"] $root)
  rm -rf $root

  if $plan.ok and $plan.packages == ["alpha" "beta"] and ($plan.skip_list | length) == 0 {
    print "  [PASS] allowlist mode ignores skip list"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] skip should be ignored in allowlist mode, got ($plan | to json)"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

def test_plan_packages_discovery_skip [] {
  print "Testing plan-packages discovery mode keeps skip..."
  mut passed = 0
  mut failed = 0

  let root = (make-fixture)
  let plan = (plan-packages [] ["alpha"] $root)
  let discovered = (discover-packages $root)
  rm -rf $root

  if $plan.ok and ($plan.skip_list == ["alpha"]) and ($plan.packages == $discovered) {
    print "  [PASS] discovery mode passes skip list through"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] discovery plan mismatch, got ($plan | to json)"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0

  for result in [
    (test_parse_comma_list_empty)
    (test_parse_comma_list_trim)
    (test_check_only_list_duplicates)
    (test_check_only_list_missing)
    (test_plan_packages_allowlist_order)
    (test_plan_packages_only_ignores_skip)
    (test_plan_packages_discovery_skip)
  ] {
    $total_passed = ($total_passed + $result.passed)
    $total_failed = ($total_failed + $result.failed)
    print ""
  }

  print $"Tests: ($total_passed) passed, ($total_failed) failed"

  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
