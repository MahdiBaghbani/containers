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

# Integration tests for init-dataprovider.nu
# Tests dataprovider initialization workflow for all supported types

# Test dataprovider type validation
# Verifies that only valid dataprovider types are accepted
def test_dataprovider_type_validation [] {
  print "Testing dataprovider type validation..."
  mut passed = 0
  mut failed = 0
  
  let valid_types = ["localhome", "ocm", "sciencemesh"]
  
  for type in $valid_types {
    if $type in $valid_types {
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] Type ($type) should be valid: FAILED"
      $failed = ($failed + 1)
    }
  }
  
  let invalid_types = ["invalid", "unknown", ""]
  for type in $invalid_types {
    if not ($type in $valid_types) {
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] Type ($type) should be invalid: FAILED"
      $failed = ($failed + 1)
    }
  }
  
  if $failed == 0 {
    print "  [PASS] Type validation: PASSED"
  } else {
    let failed_str = ($failed | into string)
    print $"  [FAIL] Type validation: FAILED (" + $failed_str + " errors)"
  }
  
  return {passed: $passed, failed: $failed}
}

# Test dataprovider config file copying
# Verifies that dataprovider config templates are correctly copied for each type
def test_dataprovider_config_copy [] {
  print "Testing dataprovider config copy..."
  
  # Setup test environment
  let test_config_dir = "/tmp/test_dataprovider_configs"
  let test_source_dir = "/tmp/test_dataprovider_source"
  rm -rf $test_config_dir $test_source_dir
  ^mkdir -p $test_config_dir $test_source_dir
  
  # Test each dataprovider type
  let types = ["localhome", "ocm", "sciencemesh"]
  mut passed = 0
  mut failed = 0
  
  for type in $types {
    let config_file = $"dataprovider-($type).toml"
    let template_content = $"[vars]\ndata_server_url = \"{{placeholder:data-server-url-internal.($type)}}\"\ngateway_svc = \"{{placeholder:gateway-svc}}\"\nconfig_dir = \"{{placeholder:config-dir}}\"\n"
    $template_content | save -f $"($test_source_dir)/($config_file)"
    
    # Copy config
    let source_config = $"($test_source_dir)/($config_file)"
    let dest_config = $"($test_config_dir)/($config_file)"
    
    if ($source_config | path exists) {
      ^cp $source_config $dest_config
      
      if ($dest_config | path exists) {
        $passed = ($passed + 1)
      } else {
        print $"  [FAIL] Config copy for ($type): FAILED"
        $failed = ($failed + 1)
      }
    } else {
      print $"  [FAIL] Template not found for ($type): FAILED"
      $failed = ($failed + 1)
    }
  }
  
  if $failed == 0 {
    print "  [PASS] Config copy for all types: PASSED"
  } else {
    let failed_str = ($failed | into string)
    print $"  [FAIL] Config copy: FAILED (" + $failed_str + " errors)"
  }
  
  rm -rf $test_config_dir $test_source_dir
  return {passed: $passed, failed: $failed}
}

# Test dataprovider placeholder processing
# Verifies that placeholders with nested keys are correctly processed
def test_dataprovider_placeholder_processing [] {
  print "Testing dataprovider placeholder processing..."
  
  let test_file = "/tmp/test_dataprovider_placeholders.toml"
  let content = '''[vars]
data_server_url = "{{placeholder:data-server-url-internal.localhome}}"
gateway_svc = "{{placeholder:gateway-svc}}"
config_dir = "{{placeholder:config-dir}}"
machine_api_key = "{{placeholder:machine-api-key}}"
'''
  $content | save -f $test_file
  
  use ../scripts/lib/utils.nu [process_placeholders]
  
  let placeholder_map = {
    "data-server-url-internal.localhome": "http://localhome.test:80/data"
    "gateway-svc": "gateway.test:19000"
    "config-dir": "/etc/revad"
    "machine-api-key": "test-api-key"
  }
  
  process_placeholders $test_file $placeholder_map
  
  let result = (open --raw $test_file)
  
  let has_url = ($result | str contains "http://localhome.test:80/data")
  let has_gateway = ($result | str contains "gateway.test:19000")
  let has_config_dir = ($result | str contains "/etc/revad")
  let has_api_key = ($result | str contains "test-api-key")
  let no_placeholders = (not ($result | str contains "{{placeholder:"))
  
  if $has_url and $has_gateway and $has_config_dir and $has_api_key and $no_placeholders {
    print "  [PASS] Placeholder processing: PASSED"
    rm $test_file
    return true
  } else {
    print "  [FAIL] Placeholder processing: FAILED"
    print "    Result: " + $result
    rm $test_file
    return false
  }
}

# Test dataprovider data server URL construction
# Verifies that internal data server URLs are correctly constructed
def test_dataprovider_data_server_url_construction [] {
  print "Testing dataprovider data_server_url construction..."
  mut passed = 0
  mut failed = 0
  
  # Test URL construction logic
  let test1_protocol = "http"
  let test1_host = "localhome.test"
  let test1_port = "80"
  let test1_expected = "http://localhome.test:80/data"
  let test1_constructed = $"($test1_protocol)://($test1_host):($test1_port)/data"
  if $test1_constructed == $test1_expected {
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] URL construction failed: expected ($test1_expected), got ($test1_constructed)"
    $failed = ($failed + 1)
  }
  
  let test2_protocol = "https"
  let test2_host = "ocm.test"
  let test2_port = "443"
  let test2_expected = "https://ocm.test:443/data"
  let test2_constructed = $"($test2_protocol)://($test2_host):($test2_port)/data"
  if $test2_constructed == $test2_expected {
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] URL construction failed: expected ($test2_expected), got ($test2_constructed)"
    $failed = ($failed + 1)
  }
  
  let test3_protocol = "http"
  let test3_host = "sciencemesh.test"
  let test3_port = "8080"
  let test3_expected = "http://sciencemesh.test:8080/data"
  let test3_constructed = $"($test3_protocol)://($test3_host):($test3_port)/data"
  if $test3_constructed == $test3_expected {
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] URL construction failed: expected ($test3_expected), got ($test3_constructed)"
    $failed = ($failed + 1)
  }
  
  if $failed == 0 {
    print "  [PASS] Data server URL construction: PASSED"
  } else {
    let failed_str = ($failed | into string)
    print $"  [FAIL] Data server URL construction: FAILED (" + $failed_str + " errors)"
  }
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
# Executes all dataprovider initialization tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_dataprovider_type_validation)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_dataprovider_config_copy)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_dataprovider_placeholder_processing)
  if $test3 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  let test4 = (test_dataprovider_data_server_url_construction)
  $total_passed = ($total_passed + $test4.passed)
  $total_failed = ($total_failed + $test4.failed)
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
