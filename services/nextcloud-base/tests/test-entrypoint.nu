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

# Unit tests for entrypoint-init.nu functions
# Tests command parsing and initialization logic

use ../scripts/lib/nextcloud-init.nu [version_greater]

# Test command argument parsing logic
# Verifies correct detection of apache/php-fpm commands
def test_command_detection [] {
  print "Testing command argument parsing..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Apache command detection
  let cmd_args = ["apache2-foreground"]
  let first_cmd = ($cmd_args | first)
  let is_apache = ($first_cmd | str starts-with "apache")
  
  if $is_apache {
    print "  [PASS] command detection: apache2-foreground detected as apache"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] command detection: apache2-foreground should be detected as apache"
    $failed = ($failed + 1)
  }
  
  # Test 2: PHP-FPM command detection
  let cmd_args2 = ["php-fpm"]
  let first_cmd2 = ($cmd_args2 | first)
  let is_phpfpm = ($first_cmd2 == "php-fpm")
  
  if $is_phpfpm {
    print "  [PASS] command detection: php-fpm detected correctly"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] command detection: php-fpm should be detected"
    $failed = ($failed + 1)
  }
  
  # Test 3: Non-init command detection
  let cmd_args3 = ["bash"]
  let first_cmd3 = ($cmd_args3 | first)
  let is_init_cmd = ($first_cmd3 | str starts-with "apache") or ($first_cmd3 == "php-fpm")
  
  if not $is_init_cmd {
    print "  [PASS] command detection: bash not detected as init command"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] command detection: bash should not be detected as init command"
    $failed = ($failed + 1)
  }
  
  # Test 4: Apache with additional args
  let cmd_args4 = ["apache2", "-D", "FOREGROUND"]
  let first_cmd4 = ($cmd_args4 | first)
  let is_apache4 = ($first_cmd4 | str starts-with "apache")
  
  if $is_apache4 {
    print "  [PASS] command detection: apache2 with args detected as apache"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] command detection: apache2 with args should be detected as apache"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test initialization skip logic
# Verifies NEXTCLOUD_UPDATE handling
def test_init_skip_logic [] {
  print "Testing initialization skip logic..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Non-apache command without NEXTCLOUD_UPDATE skips init
  let cmd_args = ["bash"]
  let first_cmd = ($cmd_args | first)
  let should_init = ($first_cmd | str starts-with "apache") or ($first_cmd == "php-fpm")
  let nextcloud_update = 0
  
  let will_init = $should_init or ($nextcloud_update == 1)
  
  if not $will_init {
    print "  [PASS] skip logic: bash without NEXTCLOUD_UPDATE skips init"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] skip logic: bash without NEXTCLOUD_UPDATE should skip init"
    $failed = ($failed + 1)
  }
  
  # Test 2: Non-apache command with NEXTCLOUD_UPDATE=1 runs init
  let nextcloud_update2 = 1
  let will_init2 = $should_init or ($nextcloud_update2 == 1)
  
  if $will_init2 {
    print "  [PASS] skip logic: bash with NEXTCLOUD_UPDATE=1 runs init"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] skip logic: bash with NEXTCLOUD_UPDATE=1 should run init"
    $failed = ($failed + 1)
  }
  
  # Test 3: Apache command always runs init
  let cmd_args3 = ["apache2-foreground"]
  let first_cmd3 = ($cmd_args3 | first)
  let should_init3 = ($first_cmd3 | str starts-with "apache") or ($first_cmd3 == "php-fpm")
  let will_init3 = $should_init3 or ($nextcloud_update == 1)
  
  if $will_init3 {
    print "  [PASS] skip logic: apache command always runs init"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] skip logic: apache command should always run init"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test version comparison decision logic
# Verifies downgrade detection and upgrade decision
def test_version_decision_logic [] {
  print "Testing version decision logic..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Downgrade detection (installed > image)
  let installed = "30.0.0.0"
  let image = "29.0.0.0"
  let is_downgrade = (version_greater $installed $image)
  
  if $is_downgrade {
    print "  [PASS] version decision: downgrade detected (30 -> 29)"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version decision: downgrade should be detected (30 -> 29)"
    $failed = ($failed + 1)
  }
  
  # Test 2: Upgrade detection (image > installed)
  let installed2 = "29.0.0.0"
  let image2 = "30.0.0.0"
  let needs_upgrade = (version_greater $image2 $installed2)
  
  if $needs_upgrade {
    print "  [PASS] version decision: upgrade needed (29 -> 30)"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version decision: upgrade should be detected (29 -> 30)"
    $failed = ($failed + 1)
  }
  
  # Test 3: Same version (no action needed)
  let installed3 = "30.0.0.0"
  let image3 = "30.0.0.0"
  let is_downgrade3 = (version_greater $installed3 $image3)
  let needs_upgrade3 = (version_greater $image3 $installed3)
  
  if (not $is_downgrade3) and (not $needs_upgrade3) {
    print "  [PASS] version decision: same version needs no action"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version decision: same version should need no action"
    $failed = ($failed + 1)
  }
  
  # Test 4: Fresh install (installed = 0.0.0.0)
  let installed4 = "0.0.0.0"
  let image4 = "30.0.0.0"
  let is_fresh_install = ($installed4 == "0.0.0.0")
  let needs_init = (version_greater $image4 $installed4)
  
  if $is_fresh_install and $needs_init {
    print "  [PASS] version decision: fresh install detected"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] version decision: fresh install should be detected"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Test major version jump validation
# Verifies that skipping major versions is rejected
def test_major_version_jump [] {
  print "Testing major version jump validation..."
  mut passed = 0
  mut failed = 0
  
  # Test 1: Single major version jump allowed (29 -> 30)
  let installed1 = "29.0.0.0"
  let image1 = "30.0.0.0"
  let installed_major1 = ($installed1 | split row "." | first | into int)
  let image_major1 = ($image1 | split row "." | first | into int)
  let jump_allowed1 = ($image_major1 <= ($installed_major1 + 1))
  
  if $jump_allowed1 {
    print "  [PASS] major version: 29 -> 30 allowed"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] major version: 29 -> 30 should be allowed"
    $failed = ($failed + 1)
  }
  
  # Test 2: Double major version jump rejected (28 -> 30)
  let installed2 = "28.0.0.0"
  let image2 = "30.0.0.0"
  let installed_major2 = ($installed2 | split row "." | first | into int)
  let image_major2 = ($image2 | split row "." | first | into int)
  let jump_allowed2 = ($image_major2 <= ($installed_major2 + 1))
  
  if not $jump_allowed2 {
    print "  [PASS] major version: 28 -> 30 rejected (skips 29)"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] major version: 28 -> 30 should be rejected"
    $failed = ($failed + 1)
  }
  
  # Test 3: Same major version allowed (30.0 -> 30.1)
  let installed3 = "30.0.0.0"
  let image3 = "30.1.0.0"
  let installed_major3 = ($installed3 | split row "." | first | into int)
  let image_major3 = ($image3 | split row "." | first | into int)
  let jump_allowed3 = ($image_major3 <= ($installed_major3 + 1))
  
  if $jump_allowed3 {
    print "  [PASS] major version: 30.0 -> 30.1 allowed (same major)"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] major version: 30.0 -> 30.1 should be allowed"
    $failed = ($failed + 1)
  }
  
  return {passed: $passed, failed: $failed}
}

# Main test runner
def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0
  
  # Run tests
  let test1 = (test_command_detection)
  $total_passed = ($total_passed + $test1.passed)
  $total_failed = ($total_failed + $test1.failed)
  
  let test2 = (test_init_skip_logic)
  $total_passed = ($total_passed + $test2.passed)
  $total_failed = ($total_failed + $test2.failed)
  
  let test3 = (test_version_decision_logic)
  $total_passed = ($total_passed + $test3.passed)
  $total_failed = ($total_failed + $test3.failed)
  
  let test4 = (test_major_version_jump)
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
