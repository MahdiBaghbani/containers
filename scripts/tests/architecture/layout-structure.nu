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

# Static layout and required-file tests.

use ../../lib/plane/presence.nu [LOCAL_ROOT_DIR]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../lib.nu [run-test]

export def test-no-flat-nu-files-in-lib [verbose: bool] {
  run-test "No flat .nu files in scripts/lib/" {
    let lib_path = "scripts/lib"

    let flat_files = (ls $lib_path
      | where type == "file"
      | where {|f| ($f.name | str ends-with ".nu")}
      | get name)

    if ($flat_files | is-empty) {
      true
    } else {
      let file_list = ($flat_files | str join ", ")
      error make {msg: $"Found flat .nu files in scripts/lib/: ($file_list). All .nu files must be in domain subdirectories."}
    }
  } $verbose
}

export def test-lib-only-directories [verbose: bool] {
  run-test "scripts/lib/ contains only directories" {
    let lib_path = "scripts/lib"

    let non_dirs = (ls $lib_path
      | where type != "dir"
      | get name)

    if ($non_dirs | is-empty) {
      true
    } else {
      let items = ($non_dirs | str join ", ")
      error make {msg: $"Found non-directory items in scripts/lib/: ($items)"}
    }
  } $verbose
}

export def test-required-domain-dirs [verbose: bool] {
  run-test "Required domain directories exist" {
    let lib_path = "scripts/lib"
    let required_domains = ["build", "ci", "core", "docs", "inspect", "manifest", "plane", "platforms", "registries", "services", "test", "tls", "validate"]

    let existing = (ls $lib_path | where type == "dir" | get name | each {|p| $p | path basename})

    let missing = ($required_domains | where {|d| not ($d in $existing)})

    if ($missing | is-empty) {
      true
    } else {
      let list = ($missing | str join ", ")
      error make {msg: $"Missing required domain directories: ($list)"}
    }
  } $verbose
}

export def test-only-dockypody-at-scripts-root [verbose: bool] {
  run-test "Only dockypody.nu at scripts/ root" {
    let scripts_path = "scripts"

    let nu_files = (ls $scripts_path
      | where type == "file"
      | where {|f| ($f.name | str ends-with ".nu")}
      | get name
      | each {|p| $p | path basename})

    let allowed = ["dockypody.nu"]
    let extra_files = ($nu_files | where {|f| not ($f in $allowed)})

    if ($extra_files | is-empty) {
      true
    } else {
      let file_list = ($extra_files | str join ", ")
      error make {msg: $"Found extra .nu files at scripts/ root: ($file_list). Only dockypody.nu is allowed."}
    }
  } $verbose
}

export def test-cli-domains-have-cli-nu [verbose: bool] {
  run-test "CLI domains have cli.nu files" {
    let lib_path = "scripts/lib"
    let cli_domains = ["build", "ci", "docs", "inspect", "registries", "services", "ssh", "test", "tls", "validate"]

    let missing_clis = ($cli_domains | where {|domain|
      let cli_path = $"($lib_path)/($domain)/cli.nu"
      not ($cli_path | path exists)
    })

    if ($missing_clis | is-empty) {
      true
    } else {
      let list = ($missing_clis | str join ", ")
      error make {msg: $"Missing cli.nu in domains: ($list)"}
    }
  } $verbose
}

export def test-plane-module-exposes-helpers [verbose: bool] {
  run-test "plane module exposes local root and audit helpers" {
    if not ("scripts/lib/plane/presence.nu" | path exists) {
      error make {msg: "Missing scripts/lib/plane/presence.nu"}
    }
    if not ("scripts/lib/plane/guard.nu" | path exists) {
      error make {msg: "Missing scripts/lib/plane/guard.nu"}
    }
    if not ("scripts/lib/plane/audit.nu" | path exists) {
      error make {msg: "Missing scripts/lib/plane/audit.nu"}
    }
    if not ("scripts/lib/plane/effective-config.nu" | path exists) {
      error make {msg: "Missing scripts/lib/plane/effective-config.nu"}
    }
    if $LOCAL_ROOT_DIR != ".dockypody.local" {
      error make {msg: $"LOCAL_ROOT_DIR must be .dockypody.local, got ($LOCAL_ROOT_DIR)"}
    }
    if $LOCAL_MIRROR_FILE != "versions.nuon" {
      error make {msg: $"LOCAL_MIRROR_FILE must be versions.nuon, got ($LOCAL_MIRROR_FILE)"}
    }
    true
  } $verbose
}
