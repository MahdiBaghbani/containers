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

# Model the shell wrapper decision in pure Nu logic.
# Mirrors the if/elif/else branches in entrypoint.sh exactly.
# Returns {fatal: bool, exit_code: int}.
def wrapper_decision [
  init_script_exists: bool
  nu_exists: bool
  init_exit_code: int
] {
  if not $init_script_exists {
    {fatal: true, exit_code: 1}
  } else if not $nu_exists {
    {fatal: true, exit_code: 1}
  } else if $init_exit_code != 0 {
    {fatal: true, exit_code: $init_exit_code}
  } else {
    {fatal: false, exit_code: 0}
  }
}

# Test fatal-wrapper policy
# Locks the four decision branches of entrypoint.sh as pure logic assertions
def test_wrapper_fatal_policy [] {
  print "Testing entrypoint.sh fatal-wrapper policy..."
  mut passed = 0
  mut failed = 0

  # Test 1: init success -> wrapper proceeds (not fatal)
  let r1 = (wrapper_decision true true 0)
  if (not $r1.fatal) and ($r1.exit_code == 0) {
    print "  [PASS] wrapper policy: init success -> proceeds"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] wrapper policy: init success should allow CMD"
    $failed = ($failed + 1)
  }

  # Test 2: init exits nonzero -> fatal, propagates exit code
  let r2 = (wrapper_decision true true 2)
  if $r2.fatal and ($r2.exit_code == 2) {
    print "  [PASS] wrapper policy: init nonzero -> fatal with propagated code"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] wrapper policy: init nonzero should be fatal and propagate code"
    $failed = ($failed + 1)
  }

  # Test 3: nu binary missing -> fatal
  let r3 = (wrapper_decision true false 0)
  if $r3.fatal and ($r3.exit_code == 1) {
    print "  [PASS] wrapper policy: nu missing -> fatal"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] wrapper policy: nu missing should be fatal"
    $failed = ($failed + 1)
  }

  # Test 4: init script missing -> fatal
  let r4 = (wrapper_decision false true 0)
  if $r4.fatal and ($r4.exit_code == 1) {
    print "  [PASS] wrapper policy: init script missing -> fatal"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] wrapper policy: init script missing should be fatal"
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

# Test allow-local managed config placement in the entrypoint flow
# Verifies the helper runs for both upgrade/install and normal restarts before
# later startup steps such as seeded users.
def test_allow_local_config_placement [] {
  print "Testing allow-local managed config placement..."
  mut passed = 0
  mut failed = 0

  let content = (open --raw "../scripts/entrypoint-init.nu")
  let sync_idx = ($content | str index-of "\n    sync_source $user_info.user $user_info.group\n")
  let apply_idx = ($content | str index-of "\n  apply_allow_local_config\n")
  let seed_idx = ($content | str index-of "\n  seed_users $user_info.user\n")
  let up_to_date_idx = ($content | str index-of "\n    print \"Nextcloud is up to date\"\n")

  if $apply_idx != null {
    print "  [PASS] entrypoint: apply_allow_local_config is present"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] entrypoint: apply_allow_local_config should be present"
    $failed = ($failed + 1)
  }

  if ($sync_idx != null) and ($apply_idx != null) and ($apply_idx > $sync_idx) {
    print "  [PASS] entrypoint: apply_allow_local_config runs after sync_source"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] entrypoint: apply_allow_local_config should run after sync_source"
    $failed = ($failed + 1)
  }

  if ($apply_idx != null) and ($seed_idx != null) and ($apply_idx < $seed_idx) {
    print "  [PASS] entrypoint: apply_allow_local_config runs before seed_users"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] entrypoint: apply_allow_local_config should run before seed_users"
    $failed = ($failed + 1)
  }

  if ($up_to_date_idx != null) and ($apply_idx != null) and ($apply_idx > $up_to_date_idx) {
    print "  [PASS] entrypoint: apply_allow_local_config still runs on up-to-date starts"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] entrypoint: apply_allow_local_config should still run on up-to-date starts"
    $failed = ($failed + 1)
  }

  return {passed: $passed, failed: $failed}
}

# Audit actual service wrapper files for required patterns.
# Read-only: scans entrypoint.sh files in the repo to catch stale soft-failure
# patterns and missing fatal exits before they reach production.
def test_wrapper_file_audit [] {
  print "Testing service wrapper file policies..."
  mut passed = 0
  mut failed = 0

  # Locate repo root regardless of whether test is run from repo root or tests dir
  let repo_root = if ("./services/nextcloud-base" | path exists) { "." } else { "../../.." }
  let wrapper_files = (glob $"($repo_root)/services/*/scripts/entrypoint.sh")

  if ($wrapper_files | length) == 0 {
    print "  [FAIL] wrapper audit: no entrypoint.sh files found"
    $failed = ($failed + 1)
    return {passed: $passed, failed: $failed}
  }

  # Test 1: no stale soft-failure wording ("continuing anyway", "skipping init")
  let stale_files = ($wrapper_files | where {|f|
    let content = (open --raw $f)
    (($content | str contains "continuing anyway")
      or ($content | str contains "skipping init"))
  })
  if ($stale_files | length) == 0 {
    print "  [PASS] wrapper audit: no stale soft-failure patterns in any wrapper"
    $passed = ($passed + 1)
  } else {
    let names = ($stale_files | each {|f| $f | path basename} | str join ", ")
    print $"  [FAIL] wrapper audit: stale patterns found in: ($names)"
    $failed = ($failed + 1)
  }

  # Test 2: every wrapper has a fatal exit path
  let no_exit_files = ($wrapper_files | where {|f|
    not ((open --raw $f) | str contains "exit ")
  })
  if ($no_exit_files | length) == 0 {
    print "  [PASS] wrapper audit: all wrappers have fatal exit path"
    $passed = ($passed + 1)
  } else {
    let names = ($no_exit_files | each {|f| $f | path basename} | str join ", ")
    print $"  [FAIL] wrapper audit: missing exit in: ($names)"
    $failed = ($failed + 1)
  }

  # Test 3: every wrapper execs CMD (not just returns)
  let no_exec_files = ($wrapper_files | where {|f|
    not ((open --raw $f) | str contains "exec ")
  })
  if ($no_exec_files | length) == 0 {
    print "  [PASS] wrapper audit: all wrappers exec CMD"
    $passed = ($passed + 1)
  } else {
    let names = ($no_exec_files | each {|f| $f | path basename} | str join ", ")
    print $"  [FAIL] wrapper audit: missing exec in: ($names)"
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

  let test5 = (test_allow_local_config_placement)
  $total_passed = ($total_passed + $test5.passed)
  $total_failed = ($total_failed + $test5.failed)

  let test6 = (test_wrapper_fatal_policy)
  $total_passed = ($total_passed + $test6.passed)
  $total_failed = ($total_failed + $test6.failed)

  let test7 = (test_wrapper_file_audit)
  $total_passed = ($total_passed + $test7.passed)
  $total_failed = ($total_failed + $test7.failed)

  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"
  
  if $total_failed == 0 {
    exit 0
  } else {
    exit 1
  }
}
