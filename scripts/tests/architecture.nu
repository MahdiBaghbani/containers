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

# Architecture enforcement tests
# Ensures CLI pattern: dockypody.nu routes through domain-local cli.nu files

use ./lib.nu [run-test print-test-summary]
use ../lib/plane/guard.nu [guard-plane guard-local-plane-presence parse-plane]
use ../lib/plane/presence.nu [local-root-path local-root-present local-services-path LOCAL_ROOT_DIR]

def make-temp-repo [] {
  let tmp = (^mktemp -d | str trim)
  mkdir $tmp
  mkdir ($tmp | path join "services")
  mkdir ($tmp | path join "scripts")
  ^git -C $tmp init -q
  $tmp
}

def dockypody-entry [] {
  "scripts/dockypody.nu" | path expand
}

def run-dockypody-in-repo [repo: string, args: list<string>] {
  let entry = (dockypody-entry)
  do -i { cd $repo; ^nu $entry ...$args } | complete
}

def rm-temp-repo [dir: string] {
  try { rm -rf $dir } catch { }
}

def main [--verbose] {
  let verbose_flag = $verbose
  
  print "Architecture Enforcement Tests\n"
  
  # Test 1: No flat .nu files under scripts/lib/
  let test1 = (run-test "No flat .nu files in scripts/lib/" {
    let lib_path = "scripts/lib"
    
    # Get all files directly under scripts/lib/ (not in subdirectories)
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
  } $verbose_flag)
  
  # Test 2: All entries in scripts/lib/ are directories
  let test2 = (run-test "scripts/lib/ contains only directories" {
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
  } $verbose_flag)
  
  # Test 3: Expected domain directories exist
  let test3 = (run-test "Required domain directories exist" {
    let lib_path = "scripts/lib"
    let required_domains = ["build", "ci", "core", "docs", "manifest", "plane", "platforms", "registries", "services", "test", "tls", "validate"]
    
    let existing = (ls $lib_path | where type == "dir" | get name | each {|p| $p | path basename})
    
    let missing = ($required_domains | where {|d| not ($d in $existing)})
    
    if ($missing | is-empty) {
      true
    } else {
      let list = ($missing | str join ", ")
      error make {msg: $"Missing required domain directories: ($list)"}
    }
  } $verbose_flag)
  
  # Test 4: Only dockypody.nu at scripts/ root (no other .nu files)
  let test4 = (run-test "Only dockypody.nu at scripts/ root" {
    let scripts_path = "scripts"
    
    # Get all .nu files directly under scripts/ (not in subdirectories)
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
  } $verbose_flag)
  
  # Test 5: CLI domains have cli.nu files
  let test5 = (run-test "CLI domains have cli.nu files" {
    let lib_path = "scripts/lib"
    # Domains that must have CLI entrypoints
    let cli_domains = ["build", "ci", "docs", "registries", "services", "ssh", "test", "tls", "validate"]
    
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
  } $verbose_flag)
  
  # Test 6: plane module exposes root presence helpers
  let test6 = (run-test "plane module exposes local root helpers" {
    if not ("scripts/lib/plane/presence.nu" | path exists) {
      error make {msg: "Missing scripts/lib/plane/presence.nu"}
    }
    if not ("scripts/lib/plane/guard.nu" | path exists) {
      error make {msg: "Missing scripts/lib/plane/guard.nu"}
    }
    if $LOCAL_ROOT_DIR != ".dockypody.local" {
      error make {msg: $"LOCAL_ROOT_DIR must be .dockypody.local, got ($LOCAL_ROOT_DIR)"}
    }
    true
  } $verbose_flag)

  # Test 7: --plane local hard-errors when local root is missing
  let test7 = (run-test "--plane local requires .dockypody.local/ presence" {
    let repo = (make-temp-repo)
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected guard to fail when local root is missing"}
    }
    if not ($result.msg | str contains ".dockypody.local") {
      error make {msg: $"Expected error to mention .dockypody.local, got: ($result.msg)"}
    }
    true
  } $verbose_flag)

  # Test 8: empty local root alone is valid
  let test8 = (run-test "empty .dockypody.local/ root alone is valid" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if not $result.ok {
      error make {msg: $"Root-only topology should pass, got: ($result.msg)"}
    }
    true
  } $verbose_flag)

  # Test 9: optional empty services/ subtree is valid
  let test9 = (run-test "optional empty .dockypody.local/services/ is valid" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if not $result.ok {
      error make {msg: $"Root with empty services/ should pass, got: ($result.msg)"}
    }
    true
  } $verbose_flag)

  # Test 10: tracked plane does not require local root
  let test10 = (run-test "tracked plane does not require local root" {
    let repo = (make-temp-repo)
    let result = (try {
      guard-plane "tracked" $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if not $result.ok {
      error make {msg: $"Tracked plane should not require local root, got: ($result.msg)"}
    }
    true
  } $verbose_flag)

  # Test 11: parse-plane rejects unknown values
  let test11 = (run-test "parse-plane rejects unknown values" {
    let result = (try {
      parse-plane "shadow"
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    if $result.ok {
      error make {msg: "Expected parse-plane to reject unknown plane values"}
    }
    true
  } $verbose_flag)

  # Test 12: build help documents --plane
  let test12 = (run-test "build help documents --plane" {
    let out = (nu -c "use scripts/lib/build/cli.nu [build-help]; build-help" | str join "\n")
    if not ($out | str contains "--plane") {
      error make {msg: "build-help should document --plane"}
    }
    true
  } $verbose_flag)

  # Test 13: validate help documents --plane
  let test13 = (run-test "validate help documents --plane" {
    let out = (nu -c "use scripts/lib/validate/cli.nu [validate-help]; validate-help" | str join "\n")
    if not ($out | str contains "--plane") {
      error make {msg: "validate-help should document --plane"}
    }
    true
  } $verbose_flag)

  # Test 14: file named .dockypody.local is not a valid local root
  let test14 = (run-test "file .dockypody.local does not count as local root" {
    let repo = (make-temp-repo)
    "" | save -f (local-root-path $repo)
    if (local-root-present $repo) {
      rm-temp-repo $repo
      error make {msg: "local-root-present must be false when .dockypody.local is a file"}
    }
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected guard to fail when .dockypody.local is a file, not a directory"}
    }
    if not ($result.msg | str contains ".dockypody.local") {
      error make {msg: $"Expected error to mention .dockypody.local, got: ($result.msg)"}
    }
    true
  } $verbose_flag)

  # Test 15: build CLI routes --plane local through dockypody.nu guard
  let test15 = (run-test "build --plane local enforces root guard via dockypody.nu" {
    let repo = (make-temp-repo)
    let result = (run-dockypody-in-repo $repo [build --plane local --show-build-order --service test-svc])
    rm-temp-repo $repo
    if $result.exit_code == 0 {
      error make {msg: "Expected build --plane local to fail without local root directory"}
    }
    let combined = ($result.stdout + $result.stderr)
    if not ($combined | str contains ".dockypody.local") {
      error make {msg: $"Expected guard error mentioning .dockypody.local, got: ($combined)"}
    }
    true
  } $verbose_flag)

  # Test 16: validate CLI routes --plane local through dockypody.nu guard
  let test16 = (run-test "validate --plane local --service x enforces root guard via dockypody.nu" {
    let repo = (make-temp-repo)
    let result = (run-dockypody-in-repo $repo [validate --plane local --service test-svc])
    rm-temp-repo $repo
    if $result.exit_code == 0 {
      error make {msg: "Expected validate --plane local with a service to fail without local root directory"}
    }
    let combined = ($result.stdout + $result.stderr)
    if not ($combined | str contains ".dockypody.local") {
      error make {msg: $"Expected guard error mentioning .dockypody.local, got: ($combined)"}
    }
    true
  } $verbose_flag)

  # Test 17: validate --plane local with no target shows help, not guard error
  let test17 = (run-test "validate --plane local with no target shows help via dockypody.nu" {
    let repo = (make-temp-repo)
    let result = (run-dockypody-in-repo $repo [validate --plane local])
    rm-temp-repo $repo
    if $result.exit_code != 0 {
      error make {msg: $"Expected help fallback exit 0, got ($result.exit_code): ($result.stderr)"}
    }
    if not ($result.stdout | str contains "Usage: nu scripts/dockypody.nu validate") {
      error make {msg: $"Expected validate help output, got: ($result.stdout)"}
    }
    true
  } $verbose_flag)
  
  # Collect results
  let results = [$test1, $test2, $test3, $test4, $test5, $test6, $test7, $test8, $test9, $test10, $test11, $test12, $test13, $test14, $test15, $test16, $test17]
  
  print-test-summary $results
  
  if ($results | all {|r| $r}) {
    exit 0
  } else {
    exit 1
  }
}
