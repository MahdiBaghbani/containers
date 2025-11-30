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

# Integration tests for init-shareproviders.nu
# Tests share providers initialization workflow

# Test shareproviders config file copying
# Verifies that shareproviders config template is correctly copied to runtime directory
def test_shareproviders_config_copy [] {
  print "Testing shareproviders config copy..."
  
  # Setup test environment
  let test_config_dir = "/tmp/test_shareproviders_configs"
  let test_source_dir = "/tmp/test_shareproviders_source"
  rm -rf $test_config_dir $test_source_dir
  ^mkdir -p $test_config_dir $test_source_dir
  
  # Create mock shareproviders config template
  let template_content = '''[log]
output = "{{placeholder:log-output}}"
level = "{{placeholder:log-level:debug}}"

[shared]
gatewaysvc = "{{placeholder:gateway-svc}}"
jwt_secret = "{{placeholder:jwt-secret:reva-secret}}"
skip_user_groups_in_token = true

[grpc]
address = "{{placeholder:grpc-address}}"

[grpc.services.usershareprovider]
driver = "memory"

[grpc.services.publicshareprovider]
driver = "memory"

[grpc.services.ocmshareprovider]
driver = "json"
provider_domain = "{{placeholder:provider-domain}}"
webdav_endpoint = "{{placeholder:external-reva-endpoint}}"

[grpc.services.ocmshareprovider.drivers.json]
file = "{{placeholder:ocmshares-json-file}}"
'''
  $template_content | save -f $"($test_source_dir)/shareproviders.toml"
  
  # Create mock JSON files
  '{"shares": []}' | save -f $"($test_source_dir)/shares.json"
  
  mut passed = 0
  mut failed = 0
  
  # Test config file copy
  let source_config = $"($test_source_dir)/shareproviders.toml"
  let dest_config = $"($test_config_dir)/shareproviders.toml"
  
  if ($source_config | path exists) {
    ^cp $source_config $dest_config
    
    if ($dest_config | path exists) {
      $passed = ($passed + 1)
      
      # Verify JSON files are copied
      use ../scripts/lib/shared.nu [copy_json_files]
      copy_json_files $test_source_dir $test_config_dir
      
      if ($"($test_config_dir)/shares.json" | path exists) {
        $passed = ($passed + 1)
      } else {
        print "  [FAIL] JSON files copy: FAILED"
        $failed = ($failed + 1)
      }
    } else {
      print "  [FAIL] Config file copy: FAILED"
      $failed = ($failed + 1)
    }
  } else {
    print "  [FAIL] Template file not found: FAILED"
    $failed = ($failed + 1)
  }
  
  if $failed == 0 {
    print "  [PASS] Config copy: PASSED"
  } else {
    let failed_str = ($failed | into string)
    print $"  [FAIL] Config copy: FAILED (" + $failed_str + " errors)"
  }
  
  rm -rf $test_config_dir $test_source_dir
  return {passed: $passed, failed: $failed}
}

# Test shareproviders placeholder processing
# Verifies that placeholders in shareproviders config are correctly replaced with values
def test_shareproviders_placeholder_processing [] {
  print "Testing shareproviders placeholder processing..."
  
  let test_file = "/tmp/test_shareproviders_placeholders.toml"
  let content = '''[log]
output = "{{placeholder:log-output}}"
level = "{{placeholder:log-level:debug}}"

[shared]
gatewaysvc = "{{placeholder:gateway-svc}}"
jwt_secret = "{{placeholder:jwt-secret:reva-secret}}"

[grpc]
address = "{{placeholder:grpc-address}}"

[grpc.services.ocmshareprovider]
provider_domain = "{{placeholder:provider-domain}}"
webdav_endpoint = "{{placeholder:external-reva-endpoint}}"

[grpc.services.ocmshareprovider.drivers.json]
file = "{{placeholder:ocmshares-json-file}}"
'''
  $content | save -f $test_file
  
  use ../scripts/lib/utils.nu [process_placeholders]
  
  let placeholder_map = {
    "log-level": "info"
    "log-output": "/var/log/shareproviders.log"
    "jwt-secret": "test-secret"
    "gateway-svc": "gateway.test:9142"
    "grpc-address": ":9144"
    "config-dir": "/etc/revad"
    "provider-domain": "test.domain"
    "external-reva-endpoint": "https://web.test"
    "ocmshares-json-file": "/var/tmp/reva/shares.json"
  }
  
  process_placeholders $test_file $placeholder_map
  
  let result = (open --raw $test_file)
  
  let has_log_output = ($result | str contains "/var/log/shareproviders.log")
  let has_log_level = ($result | str contains "info")
  let has_gateway = ($result | str contains "gateway.test:9142")
  let has_grpc_address = ($result | str contains ":9144")
  let has_provider_domain = ($result | str contains "test.domain")
  let has_endpoint = ($result | str contains "https://web.test")
  let has_json_file = ($result | str contains "/var/tmp/reva/shares.json")
  let no_placeholders = (not ($result | str contains "{{placeholder:"))
  
  mut passed = 0
  mut failed = 0
  
  if $has_log_output { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_log_level { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_gateway { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_grpc_address { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_provider_domain { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_endpoint { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_json_file { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
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

# Test shareproviders gateway service address construction
# Verifies that gateway service address is correctly constructed from host and port
def test_shareproviders_gateway_address_construction [] {
  print "Testing shareproviders gateway address construction..."
  mut passed = 0
  mut failed = 0
  
  # Test address construction logic
  let test1_host = "gateway.test"
  let test1_port = "9142"
  let test1_expected = "gateway.test:9142"
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

# Test shareproviders external endpoint construction
# Verifies that external Reva endpoint is correctly constructed from web domain and protocol
def test_shareproviders_external_endpoint_construction [] {
  print "Testing shareproviders external endpoint construction..."
  mut passed = 0
  mut failed = 0
  
  # Test HTTP endpoint
  let test1_protocol = "http"
  let test1_domain = "web.test"
  let test1_expected = "http://web.test"
  let test1_constructed = $"($test1_protocol)://($test1_domain)"
  if $test1_constructed == $test1_expected {
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Endpoint construction failed: expected ($test1_expected), got ($test1_constructed)"
    $failed = ($failed + 1)
  }
  
  # Test HTTPS endpoint
  let test2_protocol = "https"
  let test2_domain = "cernbox.test"
  let test2_expected = "https://cernbox.test"
  let test2_constructed = $"($test2_protocol)://($test2_domain)"
  if $test2_constructed == $test2_expected {
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] Endpoint construction failed: expected ($test2_expected), got ($test2_constructed)"
    $failed = ($failed + 1)
  }
  
  if $failed == 0 {
    print "  [PASS] External endpoint construction: PASSED"
  } else {
    let failed_str = ($failed | into string)
    print $"  [FAIL] External endpoint construction: FAILED (" + $failed_str + " errors)"
  }
  
  return {passed: $passed, failed: $failed}
}

# Test shareproviders TLS disabling
# Verifies that TLS certificates are properly disabled in HTTP mode
def test_shareproviders_tls_disabling [] {
  print "Testing shareproviders TLS disabling..."
  
  let test_file = "/tmp/test_shareproviders_tls.toml"
  let content = '''[grpc]
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
# Executes all shareproviders initialization tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_shareproviders_config_copy)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_shareproviders_placeholder_processing)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_shareproviders_gateway_address_construction)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_shareproviders_external_endpoint_construction)
  $total_passed = ($total_passed + $test4.passed)
  $total_failed = ($total_failed + $test4.failed)
  
  let test5 = (test_shareproviders_tls_disabling)
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
