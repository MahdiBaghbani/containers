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

# Unit tests for merge-partials.nu and resolve-configs.nu

use ../scripts/lib/merge-partials.nu [
  parse_partial_file,
  find_partials_for_target,
  sort_partials_by_order,
  remove_old_merged_sections,
  merge_partial_with_marker,
  merge_partial_without_marker
]

use ../scripts/lib/resolve-configs.nu [resolve_configs]

const SERVICE_ROOT = (path self | path dirname | path join '..' | path expand)

const GATEWAY_ENABLE_CODE_FLOW_CORE = "enable_code_flow = {{placeholder:enable-code-flow:false}}"
const GATEWAY_ENABLE_CODE_FLOW_MASTER = "enable_code_flow = true"
const SHAREPROVIDERS_WEBAPP_TEMPLATE_CORE = 'webapp_template = "{{placeholder:external-reva-endpoint}}/external/sciencemesh/{{.Token}}/{relative-path-to-shared-resource}"'
const SHAREPROVIDERS_WEBAPP_ENDPOINT_MASTER = 'webapp_endpoint = "{{placeholder:external-reva-endpoint}}/external/sciencemesh"'
const SHAREPROVIDERS_PROVIDER_DOMAIN = 'provider_domain = "{{placeholder:provider-domain}}"'
const SHAREPROVIDERS_WEBDAV_ENDPOINT = 'webdav_endpoint = "{{placeholder:external-reva-endpoint}}"'

def extract_assignment_line [content: string, key: string] {
  $content
  | lines
  | where {|line|
      let trimmed = ($line | str trim)
      ($trimmed | str starts-with $"($key) =") or ($trimmed | str starts-with $"($key)=")
    }
  | first
}

def normalize_gateway_overlay_contract [content: string] {
  $content
  | str replace -a $GATEWAY_ENABLE_CODE_FLOW_CORE "ENABLE_CODE_FLOW_SLOT"
  | str replace -a $GATEWAY_ENABLE_CODE_FLOW_MASTER "ENABLE_CODE_FLOW_SLOT"
}

def normalize_shareproviders_overlay_contract [content: string] {
  $content
  | str replace -a $SHAREPROVIDERS_WEBAPP_TEMPLATE_CORE "WEBAPP_SLOT"
  | str replace -a $SHAREPROVIDERS_WEBAPP_ENDPOINT_MASTER "WEBAPP_SLOT"
}

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
    print $"  [FAIL] parse_partial_file valid: FAILED \(got: ($result | to json)\)"
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
    print $"  [FAIL] sort_partials_by_order: FAILED \(orders: ($first_order), ($second_order), ($third_order), ($fourth_order)\)"
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
    print $"  [FAIL] remove_old_merged_sections: FAILED \(content: ($content)\)"
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
    print $"  [FAIL] merge_partial_with_marker: FAILED \(content: ($content)\)"
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
    print $"  [FAIL] merge_partial_without_marker: FAILED \(content: ($content)\)"
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
  
  print $"  [FAIL] find_partials_for_target: FAILED \(found ($result | length) partials, expected 2\)"
  rm -rf $test_dir
  return false
}

def test_resolve_configs_missing_core_dir [] {
  print "Testing resolve_configs missing core dir..."

  let dest = "/tmp/test-resolve-configs-missing-core"
  rm -rf $dest

  let result = (try {
    resolve_configs "/nonexistent/core/dir" "/tmp/overlays" "master" $dest
    false
  } catch {|err|
    ($err.msg | str contains "Core config directory not found")
  })

  if $result {
    print "  [PASS] resolve_configs missing core dir: PASSED (error as expected)"
    return true
  } else {
    print "  [FAIL] resolve_configs missing core dir: FAILED (should have errored)"
    return false
  }
}

def test_resolve_configs_unknown_band [] {
  print "Testing resolve_configs unknown band errors..."

  let root = $SERVICE_ROOT
  let core_dir = ($root | path join "configs")
  let overlays_root = ($root | path join "configs-overlays")
  let dest = "/tmp/test-resolve-configs-unknown-band"
  rm -rf $dest

  let result = (try {
    resolve_configs $core_dir $overlays_root "not-a-real-band" $dest
    false
  } catch {|err|
    ($err.msg | str contains "Unknown or missing config overlay band")
  })

  rm -rf $dest

  if $result {
    print "  [PASS] resolve_configs unknown band: PASSED (error as expected)"
    return true
  } else {
    print "  [FAIL] resolve_configs unknown band: FAILED (should have errored)"
    return false
  }
}

def test_resolve_configs_empty_band [] {
  print "Testing resolve_configs empty band errors..."

  let root = $SERVICE_ROOT
  let core_dir = ($root | path join "configs")
  let overlays_root = ($root | path join "configs-overlays")
  let dest = "/tmp/test-resolve-configs-empty-band"
  rm -rf $dest

  let result = (try {
    resolve_configs $core_dir $overlays_root "" $dest
    false
  } catch {|err|
    ($err.msg | str contains "must not be empty")
  })

  rm -rf $dest

  if $result {
    print "  [PASS] resolve_configs empty band: PASSED (error as expected)"
    return true
  } else {
    print "  [FAIL] resolve_configs empty band: FAILED (should have errored)"
    return false
  }
}

def test_overlay_gateway_contract [] {
  print "Testing master gateway overlay contract (pinned diffs only)..."

  let root = $SERVICE_ROOT
  let core_path = ($root | path join "configs" "gateway.toml")
  let overlay_path = ($root | path join "configs-overlays" "master" "gateway.toml")

  let core = (open --raw $core_path)
  let overlay = (open --raw $overlay_path)
  let normalized_core = (normalize_gateway_overlay_contract $core)
  let normalized_overlay = (normalize_gateway_overlay_contract $overlay)

  if $normalized_core != $normalized_overlay {
    print "  [FAIL] master gateway overlay contract: FAILED (unexpected drift)"
    return false
  }

  let core_line = (extract_assignment_line $core "enable_code_flow")
  let overlay_line = (extract_assignment_line $overlay "enable_code_flow")
  let diff_ok = ($core_line == $GATEWAY_ENABLE_CODE_FLOW_CORE) and ($overlay_line == $GATEWAY_ENABLE_CODE_FLOW_MASTER)

  if $diff_ok {
    print "  [PASS] master gateway overlay contract: PASSED"
    return true
  } else {
    print "  [FAIL] master gateway overlay contract: FAILED (allowed diff changed)"
    return false
  }
}

def test_overlay_shareproviders_contract [] {
  print "Testing master shareproviders overlay contract (pinned diffs only)..."

  let root = $SERVICE_ROOT
  let core_path = ($root | path join "configs" "shareproviders.toml")
  let overlay_path = ($root | path join "configs-overlays" "master" "shareproviders.toml")

  let core = (open --raw $core_path)
  let overlay = (open --raw $overlay_path)
  let normalized_core = (normalize_shareproviders_overlay_contract $core)
  let normalized_overlay = (normalize_shareproviders_overlay_contract $overlay)

  if $normalized_core != $normalized_overlay {
    print "  [FAIL] master shareproviders overlay contract: FAILED (unexpected drift)"
    return false
  }

  let core_has_template = ((extract_assignment_line $core "webapp_template") == $SHAREPROVIDERS_WEBAPP_TEMPLATE_CORE)
  let overlay_has_endpoint = ((extract_assignment_line $overlay "webapp_endpoint") == $SHAREPROVIDERS_WEBAPP_ENDPOINT_MASTER)
  let preserved = (
    (extract_assignment_line $core "provider_domain") == $SHAREPROVIDERS_PROVIDER_DOMAIN
    and (extract_assignment_line $overlay "provider_domain") == $SHAREPROVIDERS_PROVIDER_DOMAIN
    and (extract_assignment_line $core "webdav_endpoint") == $SHAREPROVIDERS_WEBDAV_ENDPOINT
    and (extract_assignment_line $overlay "webdav_endpoint") == $SHAREPROVIDERS_WEBDAV_ENDPOINT
  )

  if $core_has_template and $overlay_has_endpoint and $preserved {
    print "  [PASS] master shareproviders overlay contract: PASSED"
    return true
  } else {
    print "  [FAIL] master shareproviders overlay contract: FAILED (allowed diff changed)"
    return false
  }
}

def test_resolve_configs_v3_10_1_core_only [] {
  print "Testing resolve_configs v3.10.1 band uses core only..."

  let root = $SERVICE_ROOT
  let core_dir = ($root | path join "configs")
  let overlays_root = ($root | path join "configs-overlays")
  let dest = "/tmp/test-resolve-configs-v3-10-1"
  rm -rf $dest

  resolve_configs $core_dir $overlays_root "v3.10.1" $dest

  let shareproviders = (open --raw ($dest | path join "shareproviders.toml"))
  let gateway = (open --raw ($dest | path join "gateway.toml"))
  let core_groupuserproviders = (open --raw ($core_dir | path join "groupuserproviders.toml"))
  let resolved_groupuserproviders = (open --raw ($dest | path join "groupuserproviders.toml"))

  let share_ok = (
    (extract_assignment_line $shareproviders "webapp_template") == $SHAREPROVIDERS_WEBAPP_TEMPLATE_CORE
    and (extract_assignment_line $shareproviders "webapp_endpoint" | is-empty)
    and (extract_assignment_line $shareproviders "provider_domain") == $SHAREPROVIDERS_PROVIDER_DOMAIN
    and (extract_assignment_line $shareproviders "webdav_endpoint") == $SHAREPROVIDERS_WEBDAV_ENDPOINT
  )
  let gateway_ok = (
    (extract_assignment_line $gateway "enable_code_flow") == $GATEWAY_ENABLE_CODE_FLOW_CORE
    and (extract_assignment_line $gateway "enable_webapp") == "enable_webapp = true"
  )
  let copied_ok = $core_groupuserproviders == $resolved_groupuserproviders

  rm -rf $dest

  if $share_ok and $gateway_ok and $copied_ok {
    print "  [PASS] resolve_configs v3.10.1 core only: PASSED"
    return true
  } else {
    print "  [FAIL] resolve_configs v3.10.1 core only: FAILED"
    return false
  }
}

def test_resolve_configs_master_shareproviders_webapp_endpoint [] {
  print "Testing resolve_configs master band shareproviders overlay..."

  let root = $SERVICE_ROOT
  let core_dir = ($root | path join "configs")
  let overlays_root = ($root | path join "configs-overlays")
  let dest = "/tmp/test-resolve-configs-master-shareproviders"
  rm -rf $dest

  resolve_configs $core_dir $overlays_root "master" $dest

  let shareproviders = (open --raw ($dest | path join "shareproviders.toml"))
  let ok = (
    (extract_assignment_line $shareproviders "webapp_endpoint") == $SHAREPROVIDERS_WEBAPP_ENDPOINT_MASTER
    and (extract_assignment_line $shareproviders "webapp_template" | is-empty)
    and (extract_assignment_line $shareproviders "provider_domain") == $SHAREPROVIDERS_PROVIDER_DOMAIN
    and (extract_assignment_line $shareproviders "webdav_endpoint") == $SHAREPROVIDERS_WEBDAV_ENDPOINT
  )

  rm -rf $dest

  if $ok {
    print "  [PASS] resolve_configs master shareproviders: PASSED"
    return true
  } else {
    print "  [FAIL] resolve_configs master shareproviders: FAILED"
    return false
  }
}

def test_resolve_configs_master_gateway_enable_code_flow [] {
  print "Testing resolve_configs master band gateway overlay..."

  let root = $SERVICE_ROOT
  let core_dir = ($root | path join "configs")
  let overlays_root = ($root | path join "configs-overlays")
  let dest = "/tmp/test-resolve-configs-master-gateway"
  rm -rf $dest

  resolve_configs $core_dir $overlays_root "master" $dest

  let gateway = (open --raw ($dest | path join "gateway.toml"))
  let core_groupuserproviders = (open --raw ($core_dir | path join "groupuserproviders.toml"))
  let resolved_groupuserproviders = (open --raw ($dest | path join "groupuserproviders.toml"))
  let ok = (
    (extract_assignment_line $gateway "enable_code_flow") == $GATEWAY_ENABLE_CODE_FLOW_MASTER
    and (extract_assignment_line $gateway "enable_webapp") == "enable_webapp = true"
    and $core_groupuserproviders == $resolved_groupuserproviders
  )

  rm -rf $dest

  if $ok {
    print "  [PASS] resolve_configs master gateway: PASSED"
    return true
  } else {
    print "  [FAIL] resolve_configs master gateway: FAILED"
    return false
  }
}

# Main test runner
def main [--verbose] {
  print "Running merge-partials.nu and resolve-configs.nu tests...\n"
  
  mut results = []
  
  $results = ($results | append (test_parse_partial_file_valid))
  $results = ($results | append (test_parse_partial_file_missing_target))
  $results = ($results | append (test_sort_partials_by_order))
  $results = ($results | append (test_remove_old_merged_sections))
  $results = ($results | append (test_merge_partial_with_marker))
  $results = ($results | append (test_merge_partial_without_marker))
  $results = ($results | append (test_find_partials_for_target))
  $results = ($results | append (test_resolve_configs_missing_core_dir))
  $results = ($results | append (test_resolve_configs_unknown_band))
  $results = ($results | append (test_resolve_configs_empty_band))
  $results = ($results | append (test_overlay_gateway_contract))
  $results = ($results | append (test_overlay_shareproviders_contract))
  $results = ($results | append (test_resolve_configs_v3_10_1_core_only))
  $results = ($results | append (test_resolve_configs_master_shareproviders_webapp_endpoint))
  $results = ($results | append (test_resolve_configs_master_gateway_enable_code_flow))

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
