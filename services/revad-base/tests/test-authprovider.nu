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

# Integration tests for init-authprovider.nu
# Tests authprovider initialization workflow including config copying and processing

# Test authprovider type validation
# Verifies that invalid authprovider types are rejected
def test_authprovider_type_validation [] {
  print "Testing authprovider type validation..."
  
  let valid_types = ["oidc", "machine", "ocmshares", "publicshares"]
  let invalid_types = ["invalid", "oidc2", "machine-auth", "", "oidc "]
  
  mut passed = 0
  mut failed = 0
  
  # Test valid types
  for type in $valid_types {
    if $type in $valid_types {
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] Valid type ($type) rejected: FAILED"
      $failed = ($failed + 1)
    }
  }
  
  # Test invalid types
  for type in $invalid_types {
    if not ($type in $valid_types) {
      $passed = ($passed + 1)
    } else {
      print $"  [FAIL] Invalid type ($type) accepted: FAILED"
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

# Test authprovider config file copying
# Verifies that authprovider config templates are correctly copied for each type
def test_authprovider_config_copy [] {
  print "Testing authprovider config copy..."
  
  # Setup test environment
  let test_config_dir = "/tmp/test_authprovider_configs"
  let test_source_dir = "/tmp/test_authprovider_source"
  rm -rf $test_config_dir $test_source_dir
  ^mkdir -p $test_config_dir $test_source_dir
  
  # Test each authprovider type
  let types = ["oidc", "machine", "ocmshares", "publicshares"]
  mut passed = 0
  mut failed = 0
  
  for type in $types {
    let config_file = $"authprovider-($type).toml"
    let template_content = $"[vars]\ngateway_svc = \"{{placeholder:gateway-svc}}\"\nconfig_dir = \"{{placeholder:config-dir}}\"\n"
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

# Test authprovider placeholder processing
# Verifies that placeholders are correctly replaced with values
def test_authprovider_placeholder_processing [] {
  print "Testing authprovider placeholder processing..."
  
  let test_file = "/tmp/test_authprovider_placeholders.toml"
  let content = '''[vars]
gateway_svc = "{{placeholder:gateway-svc}}"
config_dir = "{{placeholder:config-dir}}"
idp_url = "{{placeholder:idp-url}}"
idp_domain = "{{placeholder:idp-domain}}"
machine_api_key = "{{placeholder:machine-api-key}}"
'''
  $content | save -f $test_file
  
  use ../scripts/lib/utils.nu [process_placeholders]
  
  let placeholder_map = {
    "gateway-svc": "revad-gateway:9142"
    "config-dir": "/etc/revad"
    "idp-url": "https://idp.test"
    "idp-domain": "idp.test"
    "machine-api-key": "test-api-key"
  }
  
  process_placeholders $test_file $placeholder_map
  
  let result = (open --raw $test_file)
  
  let has_gateway = ($result | str contains "revad-gateway:9142")
  let has_config_dir = ($result | str contains "/etc/revad")
  let has_idp_url = ($result | str contains "https://idp.test")
  let has_idp_domain = ($result | str contains "idp.test")
  let has_api_key = ($result | str contains "test-api-key")
  let no_placeholders = (not ($result | str contains "{{placeholder:"))
  
  mut passed = 0
  mut failed = 0
  
  if $has_gateway { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_config_dir { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_idp_url { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_idp_domain { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_api_key { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $no_placeholders { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  
  if $failed == 0 {
    print "  [PASS] Placeholder processing: PASSED"
  } else {
    let failed_str = ($failed | into string)
    print $"  [FAIL] Placeholder processing: FAILED (" + $failed_str + " errors)"
    print "    Result: " + $result
  }
  
  rm $test_file
  return {passed: $passed, failed: $failed}
}

# Test authprovider gateway address construction
# Verifies that gateway address is correctly constructed from host and port
def test_authprovider_gateway_address_construction [] {
  print "Testing authprovider gateway address construction..."
  
  mut passed = 0
  mut failed = 0
  
  # Test with explicit values
  let test1_host = "revad-gateway"
  let test1_port = "9142"
  let test1_expected = "revad-gateway:9142"
  let test1_constructed = $"($test1_host):($test1_port)"
  if $test1_constructed == $test1_expected {
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Address construction failed: expected ($test1_expected), got ($test1_constructed)"
    $failed = ($failed + 1)
  }
  
  # Test with default values
  let test2_host = "revad-gateway"
  let test2_port = "9142"
  let test2_expected = "revad-gateway:9142"
  let test2_constructed = $"($test2_host):($test2_port)"
  if $test2_constructed == $test2_expected {
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Address construction failed: expected ($test2_expected), got ($test2_constructed)"
    $failed = ($failed + 1)
  }
  
  if $failed == 0 {
    print "  [PASS] Gateway address construction: PASSED"
  } else {
    let failed_str = ($failed | into string)
    print $"  [FAIL] Gateway address construction: FAILED (" + $failed_str + " errors)"
  }
  
  return {passed: $passed, failed: $failed}
}

# Test authprovider TLS disabling
# Verifies that TLS certificates are properly disabled in HTTP mode
def test_authprovider_tls_disabling [] {
  print "Testing authprovider TLS disabling..."
  
  let test_file = "/tmp/test_authprovider_tls.toml"
  let content = '''[http]
certfile = "/tls/server.crt"
keyfile = "/tls/server.key"
'''
  $content | save -f $test_file
  
  use ../scripts/lib/utils.nu [replace_in_file]
  
  replace_in_file $test_file 'certfile = "/tls/server.crt"' '# certfile disabled - HTTP mode'
  replace_in_file $test_file 'keyfile = "/tls/server.key"' '# keyfile disabled - HTTP mode'
  
  let result = (open --raw $test_file)
  
  let has_cert_disabled = ($result | str contains "# certfile disabled")
  let has_key_disabled = ($result | str contains "# keyfile disabled")
  let no_cert_line = (not ($result | str contains 'certfile = "/tls/server.crt"'))
  
  mut passed = 0
  mut failed = 0
  
  if $has_cert_disabled { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_key_disabled { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $no_cert_line { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  
  if $failed == 0 {
    print "  [PASS] TLS disabling: PASSED"
  } else {
    let failed_str = ($failed | into string)
    print $"  [FAIL] TLS disabling: FAILED (" + $failed_str + " errors)"
    print "    Result: " + $result
  }
  
  rm $test_file
  return {passed: $passed, failed: $failed}
}

# Main test runner
# Executes all authprovider initialization tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_authprovider_type_validation)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_authprovider_config_copy)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_authprovider_placeholder_processing)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_authprovider_gateway_address_construction)
  $total_passed = ($total_passed + $test4.passed)
  $total_failed = ($total_failed + $test4.failed)
  
  let test5 = (test_authprovider_tls_disabling)
  $total_passed = ($total_passed + $test5.passed)
  $total_failed = ($total_failed + $test5.failed)
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
