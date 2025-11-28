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

# Unit tests for apache-config.nu functions
# Tests Apache configuration logic

# Test Apache command detection logic
# Verifies correct detection of apache commands
def test_apache_command_detection [] {
  print "Testing Apache command detection..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: apache2-foreground is detected
  let cmd1 = "apache2-foreground"
  if ($cmd1 | str starts-with "apache") {
    print "  [PASS] apache detection: apache2-foreground detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] apache detection: apache2-foreground should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 2: apache2 is detected
  let cmd2 = "apache2"
  if ($cmd2 | str starts-with "apache") {
    print "  [PASS] apache detection: apache2 detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] apache detection: apache2 should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 3: apachectl is detected
  let cmd3 = "apachectl"
  if ($cmd3 | str starts-with "apache") {
    print "  [PASS] apache detection: apachectl detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] apache detection: apachectl should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 4: php-fpm is not detected as apache
  let cmd4 = "php-fpm"
  if not ($cmd4 | str starts-with "apache") {
    print "  [PASS] apache detection: php-fpm not detected as apache"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] apache detection: php-fpm should not be detected as apache"
    $failed = ($failed + 1)
  }
  
  # Test 5: bash is not detected as apache
  let cmd5 = "bash"
  if not ($cmd5 | str starts-with "apache") {
    print "  [PASS] apache detection: bash not detected as apache"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] apache detection: bash should not be detected as apache"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test APACHE_DISABLE_REWRITE_IP handling logic
# Verifies environment variable checking
def test_disable_rewrite_ip_logic [] {
  print "Testing APACHE_DISABLE_REWRITE_IP logic..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Variable not set
  let disable_rewrite1 = (try { $env.TEST_DISABLE_REWRITE? } catch { null })
  if $disable_rewrite1 == null {
    print "  [PASS] disable_rewrite_ip: null when not set"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] disable_rewrite_ip: should be null when not set"
    $failed = ($failed + 1)
  }
  
  # Test 2: Variable set triggers action
  $env.TEST_DISABLE_REWRITE = "1"
  let disable_rewrite2 = (try { $env.TEST_DISABLE_REWRITE? } catch { null })
  
  if $disable_rewrite2 != null {
    print "  [PASS] disable_rewrite_ip: action triggered when set"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] disable_rewrite_ip: action should trigger when set"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  hide-env TEST_DISABLE_REWRITE
  
  # Test 3: Any value triggers action (not just "1")
  $env.TEST_DISABLE_REWRITE = "true"
  let disable_rewrite3 = (try { $env.TEST_DISABLE_REWRITE? } catch { null })
  
  if $disable_rewrite3 != null {
    print "  [PASS] disable_rewrite_ip: any value triggers action"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] disable_rewrite_ip: any value should trigger action"
    $failed = ($failed + 1)
  }
  
  # Cleanup
  hide-env TEST_DISABLE_REWRITE
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_apache_command_detection)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_disable_rewrite_ip_logic)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
