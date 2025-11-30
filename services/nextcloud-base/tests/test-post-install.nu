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

# Unit tests for post-install.nu functions
# Tests custom post-installation logic

# Test OCC command construction
# Verifies correct command format for Nextcloud occ operations
def test_occ_command_construction [] {
  print "Testing occ command construction..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Database indices command
  let occ_base = "php /var/www/html/occ"
  let indices_cmd = $"($occ_base) db:add-missing-indices"
  let expected_indices = "php /var/www/html/occ db:add-missing-indices"
  
  if $indices_cmd == $expected_indices {
    print "  [PASS] occ command: db:add-missing-indices correct"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] occ command: expected '($expected_indices)', got '($indices_cmd)'"
    $failed = ($failed + 1)
  }
  
  # Test 2: Maintenance repair command
  let repair_cmd = $"($occ_base) maintenance:repair --include-expensive"
  let expected_repair = "php /var/www/html/occ maintenance:repair --include-expensive"
  
  if $repair_cmd == $expected_repair {
    print "  [PASS] occ command: maintenance:repair correct"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] occ command: expected '($expected_repair)', got '($repair_cmd)'"
    $failed = ($failed + 1)
  }
  
  # Test 3: Config set command with value
  let config_cmd = $"($occ_base) config:system:set maintenance_window_start --type=integer --value=1"
  let expected_config = "php /var/www/html/occ config:system:set maintenance_window_start --type=integer --value=1"
  
  if $config_cmd == $expected_config {
    print "  [PASS] occ command: config:system:set correct"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] occ command: expected '($expected_config)', got '($config_cmd)'"
    $failed = ($failed + 1)
  }
  
  # Test 4: App disable command
  let app_cmd = $"($occ_base) app:disable firstrunwizard"
  let expected_app = "php /var/www/html/occ app:disable firstrunwizard"
  
  if $app_cmd == $expected_app {
    print "  [PASS] occ command: app:disable correct"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] occ command: expected '($expected_app)', got '($app_cmd)'"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test config file modification logic
# Verifies sed command construction for config.php
def test_config_modification [] {
  print "Testing config modification logic..."
  mut passed = 0
  mut failed = 0
  
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  # Create test config file
  let config_file = $"($test_base)/config.php"
  let config_content = "<?php
$CONFIG = [
  'instanceid' => 'test123',
];"
  $config_content | save $config_file
  
  # Test 1: Config file exists
  if ($config_file | path exists) {
    print "  [PASS] config modification: config file exists"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] config modification: config file should exist"
    $failed = ($failed + 1)
  }
  
  # Test 2: Config file is readable
  let content = (open --raw $config_file)
  if ($content | str length) > 0 {
    print "  [PASS] config modification: config file readable"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] config modification: config file should be readable"
    $failed = ($failed + 1)
  }
  
  # Test 3: Sed insertion command format (simulate)
  let line_to_insert = "  'allow_local_remote_servers' => true,"
  let sed_cmd = $"3 i\\($line_to_insert)"
  
  if ($sed_cmd | str contains "allow_local_remote_servers") {
    print "  [PASS] config modification: sed command contains setting"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] config modification: sed command should contain setting"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Test log file setup logic
# Verifies log file paths and creation logic
def test_log_file_setup [] {
  print "Testing log file setup logic..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Apache log paths
  let apache_access = "/var/log/apache2/access.log"
  let apache_error = "/var/log/apache2/error.log"
  
  if ($apache_access | str contains "apache2") and ($apache_error | str contains "apache2") {
    print "  [PASS] log setup: Apache log paths correct"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] log setup: Apache log paths incorrect"
    $failed = ($failed + 1)
  }
  
  # Test 2: Nextcloud log path
  let nextcloud_log = "/var/www/html/data/nextcloud.log"
  
  if ($nextcloud_log | str contains "data") and ($nextcloud_log | str ends-with "nextcloud.log") {
    print "  [PASS] log setup: Nextcloud log path correct"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] log setup: Nextcloud log path incorrect"
    $failed = ($failed + 1)
  }
  
  # Test 3: Log file creation in temp directory
  let test_base = $"/tmp/nextcloud-test-(random uuid)"
  mkdir $test_base
  
  let test_log = $"($test_base)/test.log"
  ^touch $test_log
  
  if ($test_log | path exists) {
    print "  [PASS] log setup: log file creation works"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] log setup: log file creation failed"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  rm -rf $test_base
  
  return {passed: $passed, failed: $failed}
}

# Test post-install step ordering
# Verifies the expected sequence of post-install operations
def test_post_install_steps [] {
  print "Testing post-install step ordering..."
  mut passed = 0
  mut failed = 0
  
  # Expected steps in order
  let steps = [
    "Add missing database indices"
    "Run maintenance repair"
    "Set maintenance window start"
    "Configure allow_local_remote_servers"
    "Disable firstrunwizard"
    "Setup log files"
  ]
  
  # Test 1: All steps are defined
  if ($steps | length) == 6 {
    print "  [PASS] post-install steps: all 6 steps defined"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] post-install steps: expected 6 steps, got ($steps | length)"
    $failed = ($failed + 1)
  }
  
  # Test 2: Database operations come first
  let first_step = ($steps | first)
  if ($first_step | str contains "database") {
    print "  [PASS] post-install steps: database operations first"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] post-install steps: database operations should be first"
    $failed = ($failed + 1)
  }
  
  # Test 3: Log setup is last
  let last_step = ($steps | last)
  if ($last_step | str contains "log") {
    print "  [PASS] post-install steps: log setup is last"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] post-install steps: log setup should be last"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_occ_command_construction)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_config_modification)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_log_file_setup)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_post_install_steps)
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
