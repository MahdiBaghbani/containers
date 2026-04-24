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

# Idempotent test-user seeding via NEXTCLOUD_SEEDED_USERS_FILE

use ./utils.nu [run_as]

# Single-quote wrap for embedding values in sh -c command strings.
# Replaces embedded ' with '\'' (the standard POSIX escape).
def sh_quote [s: string] {
  let escaped = ($s | str replace --all "'" "'\\''")
  $"'($escaped)'"
}

# Normalize parsed file data to a flat list of account records.
# Accepts:
#   {accounts: <record-of-records>}  - e.g. the OTS nextcloud.nuon shape
#   {accounts: <list>}               - list under accounts key
#   <list>                           - bare list of account records
export def normalize_accounts [data: any] {
  let data_type = ($data | describe)

  if ($data_type | str starts-with "record") {
    let accts = ($data.accounts? | default null)
    if $accts == null {
      error make {msg: "Seeded users file missing required 'accounts' field"}
    }
    let accts_type = ($accts | describe)
    if ($accts_type | str starts-with "record") {
      $accts | transpose key val | each {|r| $r.val}
    } else if (($accts_type | str starts-with "list") or ($accts_type | str starts-with "table")) {
      $accts
    } else {
      error make {msg: "Seeded users 'accounts' field must be a record or list"}
    }
  } else if (($data_type | str starts-with "list") or ($data_type | str starts-with "table")) {
    $data
  } else {
    error make {msg: "Seeded users file must be a record with 'accounts' field or a list of account records"}
  }
}

# Validate that an account record has the required username and password fields.
export def validate_account [account: any] {
  let username = ($account.username? | default "")
  let password = ($account.password? | default "")

  if $username == "" {
    error make {msg: "Seeded user account missing required 'username' field"}
  }
  if $password == "" {
    error make {msg: $"Seeded user '($username)' missing required 'password' field"}
  }
}

# Create or skip a single user idempotently, then apply optional settings.
# Existence is checked via occ user:info. New users are created with
# OC_PASS + --password-from-env. display_name and email are applied via
# occ user:setting when present.
def seed_user [nc_user: string, account: any] {
  validate_account $account

  let username = ($account.username? | default "")
  let password = ($account.password? | default "")

  let check_cmd = $"php /var/www/html/occ user:info (sh_quote $username) --output=json"
  let check = (run_as $nc_user $check_cmd | complete)

  if $check.exit_code != 0 {
    print $"Creating seeded user: ($username)"
    let add_cmd = $"OC_PASS=(sh_quote $password) php /var/www/html/occ user:add --password-from-env (sh_quote $username)"
    let add = (run_as $nc_user $add_cmd | complete)
    if $add.exit_code != 0 {
      error make {msg: $"Failed to create seeded user '($username)': ($add.stderr)"}
    }
    print $"Seeded user created: ($username)"
  } else {
    print $"Seeded user already exists, skipping: ($username)"
  }

  let display_name = ($account.display_name? | default "")
  if $display_name != "" {
    let cmd = $"php /var/www/html/occ user:setting (sh_quote $username) settings display_name (sh_quote $display_name)"
    let result = (run_as $nc_user $cmd | complete)
    if $result.exit_code != 0 {
      print $"Warning: failed to set display_name for ($username): ($result.stderr)"
    }
  }

  let email = ($account.email? | default "")
  if $email != "" {
    let cmd = $"php /var/www/html/occ user:setting (sh_quote $username) settings email (sh_quote $email)"
    let result = (run_as $nc_user $cmd | complete)
    if $result.exit_code != 0 {
      print $"Warning: failed to set email for ($username): ($result.stderr)"
    }
  }
}

# Seed Nextcloud users from NEXTCLOUD_SEEDED_USERS_FILE.
# No-op when the env var is unset or empty. Fails fast on missing/invalid file.
# Designed for local/CI test stacks; not for production use.
export def seed_users [nc_user: string] {
  let file_path = ($env.NEXTCLOUD_SEEDED_USERS_FILE? | default "")

  if $file_path == "" {
    return
  }

  print $"Seeding users from: ($file_path)"

  if not ($file_path | path exists) {
    error make {msg: $"NEXTCLOUD_SEEDED_USERS_FILE is set but file not found: ($file_path)"}
  }

  let data = (try {
    open $file_path
  } catch {|err|
    error make {msg: $"NEXTCLOUD_SEEDED_USERS_FILE: failed to parse '($file_path)': ($err.msg)"}
  })

  let accounts = (normalize_accounts $data)

  for account in $accounts {
    seed_user $nc_user $account
  }

  let count = ($accounts | length)
  print $"Seeded ($count) users"
}
