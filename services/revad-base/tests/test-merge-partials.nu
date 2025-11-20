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

# Unit tests for merge-partials.nu functions
# Tests partial configuration merge functionality

use ../scripts/lib/merge-partials.nu [
  parse_partial_file,
  find_partials_for_target,
  sort_partials_by_order,
  remove_old_merged_sections,
  merge_partial_with_marker,
  merge_partial_without_marker
]

mut tests_passed = 0
mut tests_failed = 0

# Test parse_partial_file with valid partial
def test_parse_partial_file_valid [] {
  print "Testing parse_partial_file with valid partial..."
  
  let test_file = "/tmp/test-partial.toml"
  "[target]
file = 'gateway.toml'
order = 10

[http.services.thumbnails]
cache = 'lru'" | save -f $test_file
  
  let result = (parse_partial_file $test_file)
  
  if $result.target == "gateway.toml" and $result.order == 10 and ($result.content | str contains "thumbnails") {
    print "  [PASS] parse_partial_file valid: PASSED"
    rm -f $test_file
    return true
  } else {
    print $"  [FAIL] parse_partial_file valid: FAILED (got: ($result | to json))"
    rm -f $test_file
    return false
  }
}

# Test parse_partial_file with missing [target] section
def test_parse_partial_file_missing_target [] {
  print "Testing parse_partial_file with missing [target]..."
  
  let test_file = "/tmp/test-partial-no-target.toml"
  "[http.services.test]
value = 1" | save -f $test_file
  
  let result = (try {
    parse_partial_file $test_file
    false
  } catch {
    true
  })
  
  if $result {
    print "  [PASS] parse_partial_file missing target: PASSED (error as expected)"
    rm -f $test_file
    return true
  } else {
    print "  [FAIL] parse_partial_file missing target: FAILED (should have errored)"
    rm -f $test_file
    return false
  }
}

# Test sort_partials_by_order
def test_sort_partials_by_order [] {
  print "Testing sort_partials_by_order..."
  
  let partials = [
    {file: "/tmp/c.toml", target: "gateway.toml", order: null, content: "c"},
    {file: "/tmp/b.toml", target: "gateway.toml", order: 2, content: "b"},
    {file: "/tmp/a.toml", target: "gateway.toml", order: 1, content: "a"},
    {file: "/tmp/d.toml", target: "gateway.toml", order: null, content: "d"}
  ]
  
  let sorted = (sort_partials_by_order $partials)
  
  # Should be: a (order 1), b (order 2), c (auto 3, alphabetical first), d (auto 4)
  let first_order = ($sorted | get 0 | get order)
  let second_order = ($sorted | get 1 | get order)
  let third_order = ($sorted | get 2 | get order)
  let fourth_order = ($sorted | get 3 | get order)
  
  if $first_order == 1 and $second_order == 2 and $third_order == 3 and $fourth_order == 4 {
    print "  [PASS] sort_partials_by_order: PASSED"
    return true
  } else {
    print $"  [FAIL] sort_partials_by_order: FAILED (orders: ($first_order), ($second_order), ($third_order), ($fourth_order))"
    return false
  }
}

# Test remove_old_merged_sections
def test_remove_old_merged_sections [] {
  print "Testing remove_old_merged_sections..."
  
  let test_file = "/tmp/test-target.toml"
  "[http.services.base]
value = 1

# === Merged from: test.toml (order: 10) ===
# This section was automatically merged from a partial config file.
# DO NOT EDIT MANUALLY - changes will be lost on container restart.
# To modify, edit the source partial file instead.

[http.services.merged]
value = 2

# === End of merge from: test.toml ===

[http.services.after]
value = 3" | save -f $test_file
  
  remove_old_merged_sections $test_file
  
  let content = (open --raw $test_file)
  
  if ($content | str contains "base") and ($content | str contains "after") and not ($content | str contains "merged") {
    print "  [PASS] remove_old_merged_sections: PASSED"
    rm -f $test_file
    return true
  } else {
    print $"  [FAIL] remove_old_merged_sections: FAILED (content: ($content))"
    rm -f $test_file
    return false
  }
}

# Test merge_partial_with_marker
def test_merge_partial_with_marker [] {
  print "Testing merge_partial_with_marker..."
  
  let test_file = "/tmp/test-merge-target.toml"
  "[http.services.base]
value = 1" | save -f $test_file
  
  let partial = {
    file: "/tmp/test-partial.toml",
    target: "gateway.toml",
    order: 10,
    content: "[http.services.test]\nvalue = 2"
  }
  
  merge_partial_with_marker $test_file $partial
  
  let content = (open --raw $test_file)
  
  if ($content | str contains "base") and ($content | str contains "test") and ($content | str contains "Merged from:") {
    print "  [PASS] merge_partial_with_marker: PASSED"
    rm -f $test_file
    return true
  } else {
    print $"  [FAIL] merge_partial_with_marker: FAILED (content: ($content))"
    rm -f $test_file
    return false
  }
}

# Test merge_partial_without_marker
def test_merge_partial_without_marker [] {
  print "Testing merge_partial_without_marker..."
  
  let test_file = "/tmp/test-merge-no-marker.toml"
  "[http.services.base]
value = 1" | save -f $test_file
  
  let partial = {
    file: "/tmp/test-partial.toml",
    target: "gateway.toml",
    order: 10,
    content: "[http.services.test]\nvalue = 2"
  }
  
  merge_partial_without_marker $test_file $partial
  
  let content = (open --raw $test_file)
  
  if ($content | str contains "base") and ($content | str contains "test") and not ($content | str contains "Merged from:") {
    print "  [PASS] merge_partial_without_marker: PASSED"
    rm -f $test_file
    return true
  } else {
    print $"  [FAIL] merge_partial_without_marker: FAILED (content: ($content))"
    rm -f $test_file
    return false
  }
}

# Test find_partials_for_target
def test_find_partials_for_target [] {
  print "Testing find_partials_for_target..."
  
  let test_dir = "/tmp/test-partials-dir"
  mkdir $test_dir
  
  let partial1 = "[target]
file = \"gateway.toml\"
order = 1

[http.services.test1]
value = 1"
  ($partial1 | save -f $"($test_dir)/partial1.toml")
  
  let partial2 = "[target]
file = \"gateway.toml\"
order = 2

[http.services.test2]
value = 2"
  ($partial2 | save -f $"($test_dir)/partial2.toml")
  
  let partial3 = "[target]
file = \"other.toml\"
order = 1

[http.services.test3]
value = 3"
  ($partial3 | save -f $"($test_dir)/partial3.toml")
  
  let result = (find_partials_for_target "gateway.toml" --partials-dirs [$test_dir])
  
  if ($result | length) == 2 {
    let targets = ($result | get target | uniq)
    if ($targets | length) == 1 and ($targets | get 0) == "gateway.toml" {
      print "  [PASS] find_partials_for_target: PASSED"
      rm -rf $test_dir
      return true
    }
  }
  
  print $"  [FAIL] find_partials_for_target: FAILED (found ($result | length) partials, expected 2)"
  rm -rf $test_dir
  return false
}

# Main test runner
def main [--verbose] {
  print "Running merge-partials.nu tests...\n"
  
  mut results = []
  
  $results = ($results | append (test_parse_partial_file_valid))
  $results = ($results | append (test_parse_partial_file_missing_target))
  $results = ($results | append (test_sort_partials_by_order))
  $results = ($results | append (test_remove_old_merged_sections))
  $results = ($results | append (test_merge_partial_with_marker))
  $results = ($results | append (test_merge_partial_without_marker))
  $results = ($results | append (test_find_partials_for_target))
  
  let passed = ($results | where $it == true | length)
  let failed = ($results | where $it == false | length)
  
  print "\n================================"
  print "Test Summary"
  print "================================"
  print $"Tests: ($passed) passed, ($failed) failed"
  
  if $failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
