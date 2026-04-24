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

# Unit tests for seeded-users.nu functions
# Tests parsing, normalization, validation, and no-op behavior

use ../scripts/lib/seeded-users.nu [normalize_accounts, validate_account, seed_users]

# Local copy of sh_quote for command-construction tests (not exported from module)
def sh_quote [s: string] {
  let escaped = ($s | str replace --all "'" "'\\''")
  $"'($escaped)'"
}

# Test shell single-quote wrapping
def test_sh_quote [] {
  print "Testing sh_quote..."
  mut passed = 0
  mut failed = 0

  # Test 1: plain string
  let result1 = (sh_quote "hello")
  if $result1 == "'hello'" {
    print "  [PASS] sh_quote: plain string wrapped in single quotes"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] sh_quote: expected \"'hello'\", got ($result1)"
    $failed = ($failed + 1)
  }

  # Test 2: string with embedded single quote
  let result2 = (sh_quote "it's")
  if $result2 == "'it'\\''s'" {
    print "  [PASS] sh_quote: embedded single quote escaped correctly"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] sh_quote: expected \"'it'\\''s'\", got ($result2)"
    $failed = ($failed + 1)
  }

  # Test 3: empty string
  let result3 = (sh_quote "")
  if $result3 == "''" {
    print "  [PASS] sh_quote: empty string produces empty single-quoted pair"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] sh_quote: expected \"''\", got ($result3)"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

# Test normalize_accounts with all supported input shapes
def test_normalize_accounts [] {
  print "Testing normalize_accounts..."
  mut passed = 0
  mut failed = 0

  # Test 1: record-of-records under accounts key (OTS nextcloud.nuon shape)
  let ots_shape = {
    accounts: {
      michiel: {username: "michiel", password: "michiel", display_name: "Michiel de Jong", email: "michiel@example.test"}
      marie: {username: "marie", password: "marie", display_name: "Marie Curie", email: "marie@example.test"}
    }
  }
  let result1 = (normalize_accounts $ots_shape)
  let count1 = ($result1 | length)
  let usernames1 = ($result1 | each {|a| $a.username} | sort)
  if $count1 == 2 and ($usernames1 | get 0) == "marie" and ($usernames1 | get 1) == "michiel" {
    print "  [PASS] normalize_accounts: record-of-records produces flat list"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] normalize_accounts: expected 2 accounts michiel+marie, got ($count1) ($usernames1)"
    $failed = ($failed + 1)
  }

  # Test 2: list shape (bare list of account records)
  let list_shape = [
    {username: "alice", password: "pass1"}
    {username: "bob", password: "pass2"}
  ]
  let result2 = (normalize_accounts $list_shape)
  if ($result2 | length) == 2 {
    print "  [PASS] normalize_accounts: bare list passed through unchanged"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] normalize_accounts: bare list should pass through unchanged"
    $failed = ($failed + 1)
  }

  # Test 3: record missing accounts field -> error
  let no_accounts = {users: "wrong"}
  let result3 = (try { normalize_accounts $no_accounts; "no-error" } catch {|err| "error"})
  if $result3 == "error" {
    print "  [PASS] normalize_accounts: missing 'accounts' field raises error"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] normalize_accounts: missing 'accounts' field should raise error"
    $failed = ($failed + 1)
  }

  # Test 4: non-record, non-list root type -> error
  let bad_root = "just a string"
  let result4 = (try { normalize_accounts $bad_root; "no-error" } catch {|err| "error"})
  if $result4 == "error" {
    print "  [PASS] normalize_accounts: invalid root type raises error"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] normalize_accounts: invalid root type should raise error"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

# Test validate_account for required field enforcement
def test_validate_account [] {
  print "Testing validate_account..."
  mut passed = 0
  mut failed = 0

  # Test 1: valid account passes without error
  let valid = {username: "alice", password: "secret"}
  let result1 = (try { validate_account $valid; "ok" } catch {|err| "error"})
  if $result1 == "ok" {
    print "  [PASS] validate_account: valid account passes"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] validate_account: valid account should pass without error"
    $failed = ($failed + 1)
  }

  # Test 2: missing username -> error
  let no_user = {password: "secret"}
  let result2 = (try { validate_account $no_user; "ok" } catch {|err| "error"})
  if $result2 == "error" {
    print "  [PASS] validate_account: missing username raises error"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] validate_account: missing username should raise error"
    $failed = ($failed + 1)
  }

  # Test 3: missing password -> error
  let no_pass = {username: "alice"}
  let result3 = (try { validate_account $no_pass; "ok" } catch {|err| "error"})
  if $result3 == "error" {
    print "  [PASS] validate_account: missing password raises error"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] validate_account: missing password should raise error"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

# Test seed_users no-op paths (no occ required)
def test_seed_users_noop [] {
  print "Testing seed_users no-op behavior..."
  mut passed = 0
  mut failed = 0

  # Test 1: env var not set -> no-op (no error)
  try { hide-env NEXTCLOUD_SEEDED_USERS_FILE } catch { }
  let result1 = (try { seed_users "www-data"; "ok" } catch {|err| "error"})
  if $result1 == "ok" {
    print "  [PASS] seed_users: returns no-op when env var is unset"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] seed_users: should be no-op when env var is unset"
    $failed = ($failed + 1)
  }

  # Test 2: env var set to empty string -> no-op (no error)
  $env.NEXTCLOUD_SEEDED_USERS_FILE = ""
  let result2 = (try { seed_users "www-data"; "ok" } catch {|err| "error"})
  hide-env NEXTCLOUD_SEEDED_USERS_FILE
  if $result2 == "ok" {
    print "  [PASS] seed_users: returns no-op when env var is empty string"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] seed_users: should be no-op when env var is empty string"
    $failed = ($failed + 1)
  }

  # Test 3: env var set to non-existent file -> fails fast with error
  $env.NEXTCLOUD_SEEDED_USERS_FILE = "/tmp/seeded-users-does-not-exist-xyzzy"
  let result3 = (try { seed_users "www-data"; "ok" } catch {|err| "error"})
  hide-env NEXTCLOUD_SEEDED_USERS_FILE
  if $result3 == "error" {
    print "  [PASS] seed_users: fails fast when file does not exist"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] seed_users: should fail fast when file does not exist"
    $failed = ($failed + 1)
  }

  # Test 4: env var set to file with invalid/unsupported structure -> fails fast
  let bad_file = $"/tmp/nextcloud-seeded-test-(random uuid).json"
  "\"just a string\"" | save $bad_file
  $env.NEXTCLOUD_SEEDED_USERS_FILE = $bad_file
  let result4 = (try { seed_users "www-data"; "ok" } catch {|err| "error"})
  hide-env NEXTCLOUD_SEEDED_USERS_FILE
  rm -f $bad_file
  if $result4 == "error" {
    print "  [PASS] seed_users: fails fast on unsupported file structure"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] seed_users: should fail fast on unsupported file structure"
    $failed = ($failed + 1)
  }

  # Test 5: valid nuon file parses to accounts list via open + normalize_accounts (no occ)
  let nuon_file = $"/tmp/nextcloud-seeded-test-(random uuid).nuon"
  '{ accounts: { alice: { username: "alice", password: "pass" } } }' | save $nuon_file
  let result5 = (try {
    let data = (open $nuon_file)
    let accounts = (normalize_accounts $data)
    ($accounts | length) == 1
  } catch {|err|
    false
  })
  rm -f $nuon_file
  if $result5 {
    print "  [PASS] seed_users: valid nuon file parses to accounts list without reaching occ"
    $passed = ($passed + 1)
  } else {
    print "  [FAIL] seed_users: valid nuon file should parse to non-empty accounts list"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

# Test that occ command strings are constructed correctly using sh_quote.
# These are pure string assertions - no external commands are invoked.
def test_command_building [] {
  print "Testing occ command string construction..."
  mut passed = 0
  mut failed = 0

  let username = "alice"
  let password = "secret"

  # Test 1: user:info existence-check command
  let check_cmd = $"php /var/www/html/occ user:info (sh_quote $username) --output=json"
  if $check_cmd == "php /var/www/html/occ user:info 'alice' --output=json" {
    print "  [PASS] command building: user:info command correct"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] command building: user:info wrong: ($check_cmd)"
    $failed = ($failed + 1)
  }

  # Test 2: user:add command with OC_PASS prefix
  let add_cmd = $"OC_PASS=(sh_quote $password) php /var/www/html/occ user:add --password-from-env (sh_quote $username)"
  if $add_cmd == "OC_PASS='secret' php /var/www/html/occ user:add --password-from-env 'alice'" {
    print "  [PASS] command building: user:add command correct"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] command building: user:add wrong: ($add_cmd)"
    $failed = ($failed + 1)
  }

  # Test 3: user:setting display_name command
  let display_name = "Alice B"
  let setting_cmd = $"php /var/www/html/occ user:setting (sh_quote $username) settings display_name (sh_quote $display_name)"
  if $setting_cmd == "php /var/www/html/occ user:setting 'alice' settings display_name 'Alice B'" {
    print "  [PASS] command building: user:setting display_name command correct"
    $passed = ($passed + 1)
  } else {
    print $"  [FAIL] command building: user:setting wrong: ($setting_cmd)"
    $failed = ($failed + 1)
  }

  {passed: $passed, failed: $failed}
}

def main [--verbose] {
  mut total_passed = 0
  mut total_failed = 0

  let r1 = (test_sh_quote)
  $total_passed = ($total_passed + $r1.passed)
  $total_failed = ($total_failed + $r1.failed)

  let r2 = (test_normalize_accounts)
  $total_passed = ($total_passed + $r2.passed)
  $total_failed = ($total_failed + $r2.failed)

  let r3 = (test_validate_account)
  $total_passed = ($total_passed + $r3.passed)
  $total_failed = ($total_failed + $r3.failed)

  let r4 = (test_seed_users_noop)
  $total_passed = ($total_passed + $r4.passed)
  $total_failed = ($total_failed + $r4.failed)

  let r5 = (test_command_building)
  $total_passed = ($total_passed + $r5.passed)
  $total_failed = ($total_failed + $r5.failed)

  print ""
  print $"Tests: ($total_passed) passed, ($total_failed) failed"

  if $total_failed == 0 { exit 0 } else { exit 1 }
}
