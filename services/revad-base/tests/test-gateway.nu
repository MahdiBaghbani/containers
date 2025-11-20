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

# Integration tests for init-gateway.nu
# Tests gateway initialization workflow including config copying and processing

use ../scripts/lib/merge-partials.nu [merge_partial_configs]

# Test gateway config file copying
# Verifies that gateway config template is correctly copied to runtime directory
def test_gateway_config_copy [] {
  print "Testing gateway config copy..."
  
  # Setup test environment
  let test_config_dir = "/tmp/test_gateway_configs"
  let test_source_dir = "/tmp/test_gateway_source"
  rm -rf $test_config_dir $test_source_dir
  ^mkdir -p $test_config_dir $test_source_dir
  
  # Create mock gateway config template
  let template_content = '''[vars]
internal_gateway = "{{placeholder:internal-gateway}}"
provider_domain = "{{placeholder:provider-domain}}"
external_reva_endpoint = "{{placeholder:external-reva-endpoint}}"
config_dir = "{{placeholder:config-dir}}"
'''
  $template_content | save -f $"($test_source_dir)/gateway.toml"
  
  # Create mock JSON files
  '{"users": []}' | save -f $"($test_source_dir)/users.demo.json"
  
  mut passed = 0
  mut failed = 0
  
  # Test config file copy
  let source_config = $"($test_source_dir)/gateway.toml"
  let dest_config = $"($test_config_dir)/gateway.toml"
  
  if ($source_config | path exists) {
    ^cp $source_config $dest_config
    
    if ($dest_config | path exists) {
      $passed = ($passed + 1)
      
      # Verify JSON files are copied
      use ../scripts/lib/shared.nu [copy_json_files]
      copy_json_files $test_source_dir $test_config_dir
      
      if ($"($test_config_dir)/users.demo.json" | path exists) {
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

# Test gateway partial config merging
# Verifies that partial configs are merged before placeholder processing
def test_gateway_partial_merge [] {
  print "Testing gateway partial config merge..."
  
  # Setup test environment
  let test_config_dir = "/tmp/test_gateway_partials"
  let test_partials_dir = $"($test_config_dir)/partial"
  rm -rf $test_config_dir
  ^mkdir -p $test_config_dir $test_partials_dir
  
  # Create base gateway config
  let base_config = '''[vars]
internal_gateway = "{{placeholder:internal-gateway}}"
provider_domain = "{{placeholder:provider-domain}}"

[http.services.gateway]
address = ":80"
'''
  $base_config | save -f $"($test_config_dir)/gateway.toml"
  
  # Create partial config (must have [target] section first, then content)
  # Match the format used in test-merge-partials.nu
  "[target]
file = 'gateway.toml'
order = 10

[http.services.thumbnails]
address = ':8080'" | save -f $"($test_partials_dir)/thumbnails.toml"
  
  # Set environment variable for config directory
  $env.REVAD_CONFIG_DIR = $test_config_dir
  
  mut passed = 0
  mut failed = 0
  
  # Test merge_partial_configs
  let merge_result = (try {
    merge_partial_configs "gateway.toml"
    true
  } catch {|err|
    print $"  [FAIL] Partial merge: FAILED with error: ($err.msg)"
    false
  })
  
  if $merge_result {
    # Verify partial was merged
    let result = (open --raw $"($test_config_dir)/gateway.toml")
    let has_thumbnails = ($result | str contains "[http.services.thumbnails]")
    let has_marker = ($result | str contains "# === Merged from:")
    
    if $has_thumbnails and $has_marker {
      $passed = ($passed + 1)
      print "  [PASS] Partial merge: PASSED"
    } else {
      print "  [FAIL] Partial merge: FAILED (partial not merged or marker missing)"
      print $"    Has thumbnails: ($has_thumbnails), Has marker: ($has_marker)"
      print $"    Config content: ($result | str substring 0..200)"
      $failed = ($failed + 1)
    }
  } else {
    $failed = ($failed + 1)
  }
  
  # Test that merge works when no partials exist (should not fail)
  rm -rf $test_partials_dir
  ^mkdir -p $test_partials_dir
  
  let no_partials_result = (try {
    merge_partial_configs "gateway.toml"
    true
  } catch {|err|
    print $"  [FAIL] No partials handling: FAILED with error: ($err.msg)"
    false
  })
  
  if $no_partials_result {
    $passed = ($passed + 1)
    print "  [PASS] No partials handling: PASSED"
  } else {
    $failed = ($failed + 1)
  }
  
  rm -rf $test_config_dir
  $env.REVAD_CONFIG_DIR = null
  
  return {passed: $passed, failed: $failed}
}

# Test gateway placeholder processing
# Verifies that placeholders in gateway config are correctly replaced with values
# Includes new provider addresses (shareproviders, groupuserproviders)
def test_gateway_placeholder_processing [] {
  print "Testing gateway placeholder processing..."
  
  let test_file = "/tmp/test_gateway_placeholders.toml"
  let content = '''[vars]
internal_gateway = "{{placeholder:internal-gateway}}"
provider_domain = "{{placeholder:provider-domain}}"
external_reva_endpoint = "{{placeholder:external-reva-endpoint}}"
config_dir = "{{placeholder:config-dir}}"

[grpc.services.gateway]
usershareprovidersvc = "{{placeholder:shareproviders.address}}"
publicshareprovidersvc = "{{placeholder:shareproviders.address}}"
ocmshareprovidersvc = "{{placeholder:shareproviders.address}}"
userprovidersvc = "{{placeholder:groupuserproviders.address}}"
groupprovidersvc = "{{placeholder:groupuserproviders.address}}"
'''
  $content | save -f $test_file
  
  use ../scripts/lib/utils.nu [process_placeholders]
  
  let placeholder_map = {
    "internal-gateway": "gateway.test"
    "provider-domain": "test.domain"
    "external-reva-endpoint": "https://web.test"
    "config-dir": "/etc/revad"
    "shareproviders.address": "shareproviders.test:9144"
    "groupuserproviders.address": "groupuserproviders.test:9145"
  }
  
  process_placeholders $test_file $placeholder_map
  
  let result = (open --raw $test_file)
  
  let has_gateway = ($result | str contains "gateway.test")
  let has_domain = ($result | str contains "test.domain")
  let has_endpoint = ($result | str contains "https://web.test")
  let has_config_dir = ($result | str contains "/etc/revad")
  let has_shareproviders = ($result | str contains "shareproviders.test:9144")
  let has_groupuserproviders = ($result | str contains "groupuserproviders.test:9145")
  let no_placeholders = (not ($result | str contains "{{placeholder:"))
  
  mut passed = 0
  mut failed = 0
  
  if $has_gateway { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_domain { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_endpoint { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_config_dir { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_shareproviders { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
  if $has_groupuserproviders { $passed = ($passed + 1) } else { $failed = ($failed + 1) }
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

# Test gateway TLS certificate disabling
# Verifies that TLS certificates are properly disabled in HTTP mode
def test_gateway_tls_disabling [] {
  print "Testing gateway TLS disabling..."
  
  let test_file = "/tmp/test_gateway_tls.toml"
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
# Executes all gateway initialization tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_gateway_config_copy)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_gateway_partial_merge)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_gateway_placeholder_processing)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_gateway_tls_disabling)
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
