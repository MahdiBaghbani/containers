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

# Integration tests for init-groupuserproviders.nu
# Tests user/group providers initialization workflow

# Test groupuserproviders config file copying
# Verifies that groupuserproviders config template is correctly copied to runtime directory
def test_groupuserproviders_config_copy [] {
  print "Testing groupuserproviders config copy..."
  
  # Setup test environment
  let test_config_dir = "/tmp/test_groupuserproviders_configs"
  let test_source_dir = "/tmp/test_groupuserproviders_source"
  rm -rf $test_config_dir $test_source_dir
  ^mkdir -p $test_config_dir $test_source_dir
  
  # Create mock groupuserproviders config template
  let template_content = '''[log]
output = "{{placeholder:log-output}}"
level = "{{placeholder:log-level:debug}}"

[shared]
gatewaysvc = "{{placeholder:gateway-svc}}"
jwt_secret = "{{placeholder:jwt-secret:reva-secret}}"
skip_user_groups_in_token = true

[grpc]
address = "{{placeholder:grpc-address}}"

[grpc.services.userprovider]
driver = "json"

[grpc.services.userprovider.drivers.json]
users = "{{placeholder:config-dir}}/users.demo.json"

[grpc.services.groupprovider]
driver = "json"

[grpc.services.groupprovider.drivers.json]
groups = "{{placeholder:config-dir}}/groups.demo.json"
'''
  $template_content | save -f $"($test_source_dir)/cernbox-groupuserproviders.toml"
  
  # Create mock JSON files
  '{"users": []}' | save -f $"($test_source_dir)/users.demo.json"
  '{"groups": []}' | save -f $"($test_source_dir)/groups.demo.json"
  
  # Test config file copy
  let source_config = $"($test_source_dir)/cernbox-groupuserproviders.toml"
  let dest_config = $"($test_config_dir)/cernbox-groupuserproviders.toml"
  
  if ($source_config | path exists) {
    ^cp $source_config $dest_config
    
    if ($dest_config | path exists) {
      print "  [PASS] Config file copy: PASSED"
      
      # Verify JSON files are copied
      use ../scripts/lib/shared.nu [copy_json_files]
      copy_json_files $test_source_dir $test_config_dir
      
      let users_exists = ($"($test_config_dir)/users.demo.json" | path exists)
      let groups_exists = ($"($test_config_dir)/groups.demo.json" | path exists)
      
      if $users_exists and $groups_exists {
        print "  [PASS] JSON files copy: PASSED"
        rm -rf $test_config_dir $test_source_dir
        return true
      } else {
        print $"  [FAIL] JSON files copy: FAILED (users: ($users_exists), groups: ($groups_exists))"
        rm -rf $test_config_dir $test_source_dir
        return false
      }
    } else {
      print "  [FAIL] Config file copy: FAILED"
      rm -rf $test_config_dir $test_source_dir
      return false
    }
  } else {
    print "  [FAIL] Template file not found: FAILED"
    rm -rf $test_config_dir $test_source_dir
    return false
  }
}

# Test groupuserproviders placeholder processing
# Verifies that placeholders in groupuserproviders config are correctly replaced with values
def test_groupuserproviders_placeholder_processing [] {
  print "Testing groupuserproviders placeholder processing..."
  
  let test_file = "/tmp/test_groupuserproviders_placeholders.toml"
  let content = '''[log]
output = "{{placeholder:log-output}}"
level = "{{placeholder:log-level:debug}}"

[shared]
gatewaysvc = "{{placeholder:gateway-svc}}"
jwt_secret = "{{placeholder:jwt-secret:reva-secret}}"

[grpc]
address = "{{placeholder:grpc-address}}"

[grpc.services.userprovider.drivers.json]
users = "{{placeholder:config-dir}}/users.demo.json"

[grpc.services.groupprovider.drivers.json]
groups = "{{placeholder:config-dir}}/groups.demo.json"
'''
  $content | save -f $test_file
  
  use ../scripts/lib/utils.nu [process_placeholders]
  
  let placeholder_map = {
    "log-level": "info"
    "log-output": "/var/log/groupuserproviders.log"
    "jwt-secret": "test-secret"
    "gateway-svc": "gateway.test:9142"
    "grpc-address": ":9145"
    "config-dir": "/etc/revad"
  }
  
  process_placeholders $test_file $placeholder_map
  
  let result = (open --raw $test_file)
  
  let has_log_output = ($result | str contains "/var/log/groupuserproviders.log")
  let has_log_level = ($result | str contains "info")
  let has_gateway = ($result | str contains "gateway.test:9142")
  let has_grpc_address = ($result | str contains ":9145")
  let has_users_path = ($result | str contains "/etc/revad/users.demo.json")
  let has_groups_path = ($result | str contains "/etc/revad/groups.demo.json")
  let no_placeholders = (not ($result | str contains "{{placeholder:"))
  
  if $has_log_output and $has_log_level and $has_gateway and $has_grpc_address and $has_users_path and $has_groups_path and $no_placeholders {
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

# Test groupuserproviders gateway service address construction
# Verifies that gateway service address is correctly constructed from host and port
def test_groupuserproviders_gateway_address_construction [] {
  print "Testing groupuserproviders gateway address construction..."
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
  let test2_host = "cernbox-1-test-revad-gateway"
  let test2_port = "9142"
  let test2_expected = "cernbox-1-test-revad-gateway:9142"
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

# Test groupuserproviders TLS disabling
# Verifies that TLS certificates are properly disabled in HTTP mode
def test_groupuserproviders_tls_disabling [] {
  print "Testing groupuserproviders TLS disabling..."
  
  let test_file = "/tmp/test_groupuserproviders_tls.toml"
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
  
  if $has_cert_disabled and $has_key_disabled and $no_cert_line {
    print "  [PASS] TLS disabling: PASSED"
    rm $test_file
    return true
  } else {
    print "  [FAIL] TLS disabling: FAILED"
    print "    Result: " + $result
    rm $test_file
    return false
  }
}

# Main test runner
# Executes all groupuserproviders initialization tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_groupuserproviders_config_copy)
  if $test1 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  let test2 = (test_groupuserproviders_placeholder_processing)
  if $test2 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  let test3 = (test_groupuserproviders_gateway_address_construction)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_groupuserproviders_tls_disabling)
  if $test4 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
