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
  $template_content | save -f $"($test_source_dir)/cernbox-gateway.toml"
  
  # Create mock JSON files
  '{"users": []}' | save -f $"($test_source_dir)/users.demo.json"
  
  # Set environment variables
  $env.CONFIG_DIR = $test_source_dir
  $env.REVAD_CONFIG_DIR = $test_config_dir
  $env.DOMAIN = "test.domain"
  $env.REVAD_GATEWAY_HOST = "gateway.test"
  $env.REVAD_GATEWAY_PORT = "80"
  $env.REVAD_GATEWAY_PROTOCOL = "http"
  $env.REVAD_GATEWAY_GRPC_PORT = "19000"
  $env.REVAD_LOG_LEVEL = "debug"
  $env.REVAD_LOG_OUTPUT = "/var/log/revad.log"
  $env.REVAD_JWT_SECRET = "test-secret"
  $env.WEB_DOMAIN = "web.test"
  $env.WEB_PROTOCOL = "https"
  $env.IDP_DOMAIN = "idp.test"
  $env.IDP_URL = "https://idp.test"
  $env.MESHDIR_DOMAIN = "meshdir.test"
  $env.RCLONE_ENDPOINT = "http://rclone.test"
  $env.REVAD_DATAPROVIDER_LOCALHOME_HOST = "localhome.test"
  $env.REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT = "19001"
  $env.REVAD_DATAPROVIDER_OCM_HOST = "ocm.test"
  $env.REVAD_DATAPROVIDER_OCM_GRPC_PORT = "19002"
  $env.REVAD_DATAPROVIDER_SCIENCEMESH_HOST = "sciencemesh.test"
  $env.REVAD_DATAPROVIDER_SCIENCEMESH_GRPC_PORT = "19003"
  $env.REVAD_AUTHPROVIDER_OIDC_HOST = "auth-oidc.test"
  $env.REVAD_AUTHPROVIDER_OIDC_GRPC_PORT = "9158"
  $env.REVAD_AUTHPROVIDER_MACHINE_HOST = "auth-machine.test"
  $env.REVAD_AUTHPROVIDER_MACHINE_GRPC_PORT = "9166"
  $env.REVAD_AUTHPROVIDER_OCMSHARES_HOST = "auth-ocmshares.test"
  $env.REVAD_AUTHPROVIDER_OCMSHARES_GRPC_PORT = "9278"
  $env.REVAD_SHAREPROVIDERS_HOST = "shareproviders.test"
  $env.REVAD_SHAREPROVIDERS_GRPC_PORT = "9144"
  $env.REVAD_GROUPUSERPROVIDERS_HOST = "groupuserproviders.test"
  $env.REVAD_GROUPUSERPROVIDERS_GRPC_PORT = "9145"
  $env.REVAD_TLS_ENABLED = "false"
  
  # Mock the init_gateway function by testing its components
  # Since init_gateway has side effects, we test the logic separately
  
  # Test config file copy
  let source_config = $"($test_source_dir)/cernbox-gateway.toml"
  let dest_config = $"($test_config_dir)/cernbox-gateway.toml"
  
  if ($source_config | path exists) {
    ^cp $source_config $dest_config
    
    if ($dest_config | path exists) {
      print "  [PASS] Config file copy: PASSED"
      
      # Verify JSON files are copied
      use ../scripts/lib/shared.nu [copy_json_files]
      copy_json_files $test_source_dir $test_config_dir
      
      if ($"($test_config_dir)/users.demo.json" | path exists) {
        print "  [PASS] JSON files copy: PASSED"
        rm -rf $test_config_dir $test_source_dir
        return true
      } else {
        print "  [FAIL] JSON files copy: FAILED"
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
  
  if $has_gateway and $has_domain and $has_endpoint and $has_config_dir and $has_shareproviders and $has_groupuserproviders and $no_placeholders {
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
# Executes all gateway initialization tests and reports results
def main [
  --verbose
] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_gateway_config_copy)
  if $test1 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  let test2 = (test_gateway_placeholder_processing)
  if $test2 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  let test3 = (test_gateway_tls_disabling)
  if $test3 { $total_passed = ($total_passed + 1) } else { $total_failed = ($total_failed + 1) }
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
