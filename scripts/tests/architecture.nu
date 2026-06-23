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
use ../lib/plane/guard.nu [
  guard-plane guard-local-plane-presence parse-plane PLANE_LOCAL
]
use ../lib/plane/effective-config.nu [apply-local-plane-effective-sources]
use ../lib/build/config.nu [load-service-config detect-all-source-types]
use ../lib/build/args.nu [generate-build-args]
use ../lib/manifest/core.nu [load-versions-manifest apply-version-defaults]
use ../lib/plane/presence.nu [local-root-path local-root-present local-services-path LOCAL_ROOT_DIR]
use ../lib/plane/audit.nu [audit-local-root-topology LOCAL_MIRROR_FILE require-services-directory]

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

def seed-tracked-service [repo: string, name: string = "test-svc"] {
  { name: $name } | save -f ($repo | path join $"services/($name).nuon")
}

def seed-service-with-git-source [repo: string, name: string = "test-svc"] {
  seed-tracked-service $repo $name
  mkdir ($repo | path join $"services/($name)")
  {
    default: "v1"
    versions: [{ name: "v1", overrides: {} }]
    defaults: {
      sources: {
        my_src: {
          url: "https://example.com/repo.git"
          ref: "main"
        }
      }
    }
  } | save -f ($repo | path join $"services/($name)/versions.nuon")
}

def run-in-temp-repo [repo: string, block: closure] {
  do -i { cd $repo; do $block }
}

def expect-effective-config-error [block: closure, needle: string] {
  let result = (try {
    do $block
    { ok: true }
  } catch {|err|
    { ok: false, msg: $err.msg }
  })
  if $result.ok {
    error make {msg: $"Expected effective-config to fail (needle: ($needle))"}
  }
  if not ($result.msg | str contains $needle) {
    error make {msg: $"Expected error to mention '($needle)', got: ($result.msg)"}
  }
  true
}

def expect-guard-fail [repo: string, needle: string] {
  let result = (try {
    guard-local-plane-presence $repo
    { ok: true }
  } catch {|err|
    { ok: false, msg: $err.msg }
  })
  if $result.ok {
    error make {msg: $"Expected guard to fail for topology violation (needle: ($needle))"}
  }
  if not ($result.msg | str contains $needle) {
    error make {msg: $"Expected error to mention '($needle)', got: ($result.msg)"}
  }
  true
}

def expect-guard-pass [repo: string] {
  let result = (try {
    guard-local-plane-presence $repo
    { ok: true }
  } catch {|err|
    { ok: false, msg: $err.msg }
  })
  if not $result.ok {
    error make {msg: $"Expected legal topology to pass, got: ($result.msg)"}
  }
  true
}

def nobody-drop-available [] {
  let runuser_ok = ((try { ^which runuser | complete | get exit_code } catch { 1 }) == 0)
  let sudo_ok = ((try { ^which sudo | complete | get exit_code } catch { 1 }) == 0)
  $runuser_ok or $sudo_ok
}

def can-verify-unreadable-topology-contract [] {
  (chmod-zero-blocks-reads) or (nobody-drop-available)
}

# chmod 000 is unreliable on privileged runners (DAC may be bypassed).
def chmod-zero-blocks-reads [] {
  let probe = (^mktemp -d | str trim)
  let blocked = (try {
    ^chmod 000 $probe
    let can_read = (try {
      ls $probe | ignore
      true
    } catch {
      false
    })
    try { ^chmod 700 $probe } catch { }
    not $can_read
  } catch {
    false
  })
  try { rm -rf $probe } catch { }
  $blocked
}

def try-nobody-guard-unreadable-topology [repo: string] {
  let guard_path = ("scripts/lib/plane/guard.nu" | path expand)
  let script_path = (^mktemp --suffix=.nu | str trim)
  [
    $"use '($guard_path)' [guard-local-plane-presence]"
    "try {"
    $"  guard-local-plane-presence '($repo)' | ignore"
    "  exit 2"
    "} catch {|err|"
    '  if ($err.msg | str contains "Unable to read local topology directory") {'
    "    exit 0"
    "  } else {"
    "    exit 1"
    "  }"
    "}"
  ] | str join (char nl) | save -f $script_path

  mut verified = false
  for cmd in [
    ["runuser", "-u", "nobody", "--", "nu", $script_path]
    ["sudo", "-n", "-u", "nobody", "nu", $script_path]
  ] {
    let result = (try { ^...$cmd | complete } catch { null })
    if $result != null and $result.exit_code == 0 {
      $verified = true
    }
  }

  try { rm $script_path } catch { }
  { verified: $verified }
}

def verify-unreadable-topology-contract [repo: string, dir: string, label: string] {
  if not (can-verify-unreadable-topology-contract) {
    print $"  SKIPPED: cannot verify unreadable ($label) on this runner (chmod 000 does not block reads and runuser/sudo nobody drop unavailable)"
    return true
  }

  ^chmod 000 $dir
  mut verified = false

  if (chmod-zero-blocks-reads) {
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    if not $result.ok and ($result.msg | str contains "Unable to read local topology directory") {
      $verified = true
    }
  }

  if not $verified and (nobody-drop-available) {
    $verified = (try-nobody-guard-unreadable-topology $repo).verified
  }

  try { ^chmod 700 $dir } catch { }

  if not $verified {
    error make {msg: $"Failed to verify unreadable ($label) fail-closed contract"}
  }
  true
}

def assert-audit-result-shape [repo: string, expected_mirrors: list<string>] {
  let result = (audit-local-root-topology $repo)
  if $result.local_root != (local-root-path $repo) {
    error make {msg: $"Expected local_root match, got: ($result.local_root)"}
  }
  let expected_services = (local-services-path $repo)
  if ($expected_services | path exists) {
    if $result.services_path != $expected_services {
      error make {msg: $"Expected services_path ($expected_services), got: ($result.services_path)"}
    }
  } else if not ($result.services_path | is-empty) {
    error make {msg: $"Expected null services_path when absent, got: ($result.services_path)"}
  }
  if $result.mirrors != $expected_mirrors {
    error make {msg: $"Expected mirrors ($expected_mirrors), got: ($result.mirrors)"}
  }
  $result
}

def assert-guard-result-shape [repo: string, expected_mirrors: list<string>] {
  let result = (guard-local-plane-presence $repo)
  if $result.plane != $PLANE_LOCAL {
    error make {msg: $"Expected plane '($PLANE_LOCAL)', got: ($result.plane)"}
  }
  let expected_repo = ($repo | path expand)
  if $result.repo_root != $expected_repo {
    error make {msg: $"Expected repo_root ($expected_repo), got: ($result.repo_root)"}
  }
  if $result.local_root != (local-root-path $repo) {
    error make {msg: $"Expected local_root match, got: ($result.local_root)"}
  }
  let expected_services = (local-services-path $repo)
  if ($expected_services | path exists) {
    if $result.services_path != $expected_services {
      error make {msg: $"Expected services_path ($expected_services), got: ($result.services_path)"}
    }
  } else if not ($result.services_path | is-empty) {
    error make {msg: $"Expected null services_path when absent, got: ($result.services_path)"}
  }
  if $result.mirrors != $expected_mirrors {
    error make {msg: $"Expected mirrors ($expected_mirrors), got: ($result.mirrors)"}
  }
  $result
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
    let required_domains = ["build", "ci", "core", "docs", "inspect", "manifest", "plane", "platforms", "registries", "services", "test", "tls", "validate"]
    
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
  } $verbose_flag)
  
  # Test 6: plane module exposes root presence and topology audit helpers
  let test6 = (run-test "plane module exposes local root and audit helpers" {
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
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 9: optional empty services/ subtree is valid
  let test9 = (run-test "optional empty .dockypody.local/services/ is valid" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
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

  # Test 18: unsupported root file hard-errors
  let test18 = (run-test "unsupported local root file hard-errors" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    "" | save -f (local-root-path $repo | path join "notes.txt")
    let ok = (expect-guard-fail $repo "Unsupported local root file")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 19: unsupported root directory hard-errors
  let test19 = (run-test "unsupported local root directory hard-errors" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    mkdir (local-root-path $repo | path join "cache")
    let ok = (expect-guard-fail $repo "Unsupported local root directory")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 20: unknown service mirror hard-errors
  let test20 = (run-test "unknown local service mirror hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    mkdir (local-services-path $repo | path join "shadow-svc")
    let ok = (expect-guard-fail $repo "Unknown local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 21: unsupported mirror file hard-errors
  let test21 = (run-test "unsupported local mirror file hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    "" | save -f ($mirror | path join "platforms.nuon")
    let ok = (expect-guard-fail $repo "Unsupported file in local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 22: unsupported mirror subdirectory hard-errors
  let test22 = (run-test "unsupported local mirror subdirectory hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    mkdir ($mirror | path join "fragments")
    let ok = (expect-guard-fail $repo "Unsupported directory in local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 23: empty tracked mirror hard-errors
  let test23 = (run-test "empty tracked mirror hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    let ok = (expect-guard-fail $repo "Incomplete local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 24: legal tracked mirror with versions.nuon passes
  let test24 = (run-test "legal tracked mirror with versions.nuon passes" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 25: unsupported root symlink hard-errors
  let test25 = (run-test "unsupported local root symlink hard-errors" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    ^ln -s /tmp (local-root-path $repo | path join "cache-link")
    let ok = (expect-guard-fail $repo "Unsupported local root item")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 26: tracked mirror symlink hard-errors
  let test26 = (run-test "tracked local service mirror symlink hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir ($repo | path join "mirror-target")
    ^ln -s ($repo | path join "mirror-target") $mirror
    let ok = (expect-guard-fail $repo "Mirror entries must be directories for tracked services")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 27: unreadable local topology directories hard-error
  let test27 = (run-test "unreadable local topology directories hard-error" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    let root = (local-root-path $repo)
    mkdir $root
    verify-unreadable-topology-contract $repo $root "unreadable local root topology"
    mkdir $root
    let services = (local-services-path $repo)
    mkdir $services
    verify-unreadable-topology-contract $repo $services "unreadable local services topology"
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 28: loose file directly under services/ hard-errors
  let test28 = (run-test "loose file under local services hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    "" | save -f (local-services-path $repo | path join "loose-file.txt")
    let ok = (expect-guard-fail $repo "Mirror entries must be directories for tracked services")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 29: unreadable tracked mirror directory hard-errors
  let test29 = (run-test "unreadable tracked mirror directory hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    verify-unreadable-topology-contract $repo $mirror "unreadable tracked mirror directory"
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 30: audit-local-root-topology returns mirror list on legal topology
  let test30 = (run-test "audit-local-root-topology reports legal mirrors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    assert-audit-result-shape $repo ["test-svc"]
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 31: guard-local-plane-presence merges audit fields on legal topology
  let test31 = (run-test "guard-local-plane-presence returns merged audit shape" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    assert-guard-result-shape $repo ["test-svc"]
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 32: tracked service with absent local mirrors passes
  let test32 = (run-test "tracked service with absent local mirrors passes" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    assert-guard-result-shape $repo []
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 33: tracked service with empty services/ passes
  let test33 = (run-test "tracked service with empty local services/ passes" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    assert-guard-result-shape $repo []
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 34: tracked manifest missing name hard-errors when mirror exists
  let test34 = (run-test "tracked service manifest missing name hard-errors when mirror exists" {
    let repo = (make-temp-repo)
    { platforms: [] } | save -f ($repo | path join "services/nameless-svc.nuon")
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    mkdir (local-services-path $repo | path join "nameless-svc")
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected guard to fail when tracked manifest omits name"}
    }
    if not ($result.msg | str contains "Tracked service manifest missing 'name'") {
      error make {msg: $"Expected missing-name manifest error, got: ($result.msg)"}
    }
    true
  } $verbose_flag)

  # Test 35: non-directory services/ at local root hard-errors
  let test35 = (run-test "non-directory local services/ path hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let services = (local-services-path $repo)
    "" | save -f $services
    let dir_err = (try {
      require-services-directory $services
      null
    } catch {|err|
      $err.msg
    })
    if $dir_err == null {
      error make {msg: "Expected require-services-directory to fail for file path"}
    }
    if not ($dir_err | str contains "Local path must be a directory") {
      error make {msg: $"Expected directory requirement error, got: ($dir_err)"}
    }
    let audit_err = (try {
      audit-local-root-topology $repo
      null
    } catch {|err|
      $err.msg
    })
    if $audit_err == null {
      error make {msg: "Expected audit-local-root-topology to fail for file services path"}
    }
    if not ($audit_err | str contains "Local path must be a directory") {
      error make {msg: $"Expected directory requirement error from audit, got: ($audit_err)"}
    }
    let ok = (expect-guard-fail $repo "Local path must be a directory")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 36: legal versions.nuon plus extra sibling file hard-errors
  let test36 = (run-test "legal versions.nuon with extra mirror sibling hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    "" | save -f ($mirror | path join "extra.txt")
    let ok = (expect-guard-fail $repo "Unsupported file in local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 37: hidden dot-prefixed root entry hard-errors
  let test37 = (run-test "hidden dot-prefixed local root entry hard-errors" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    mkdir (local-root-path $repo | path join ".hidden-cache")
    let ok = (expect-guard-fail $repo "Unsupported local root directory")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 38: hidden dot-prefixed unknown mirror hard-errors
  let test38 = (run-test "hidden dot-prefixed unknown local service mirror hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    mkdir (local-services-path $repo | path join ".shadow-svc")
    let ok = (expect-guard-fail $repo "Unknown local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 39: hidden dot-prefixed mirror content hard-errors
  let test39 = (run-test "hidden dot-prefixed local mirror content hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    "" | save -f ($mirror | path join ".hidden-extra")
    let ok = (expect-guard-fail $repo "Unsupported file in local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 41: empty legal local root ignores broken tracked manifests
  let test41 = (run-test "empty legal local root passes despite broken tracked manifest" {
    let repo = (make-temp-repo)
    "not valid nuon {" | save -f ($repo | path join "services/test-svc.nuon")
    mkdir (local-root-path $repo)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 42: empty services/ ignores broken tracked manifests
  let test42 = (run-test "empty local services/ passes despite broken tracked manifest" {
    let repo = (make-temp-repo)
    "not valid nuon {" | save -f ($repo | path join "services/test-svc.nuon")
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 43: local mirror for one service passes when another manifest is broken
  let test43 = (run-test "local mirror passes when unrelated tracked manifest is broken" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "svc-a"
    "not valid nuon {" | save -f ($repo | path join "services/svc-b.nuon")
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "svc-a")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 44: audit resolves only local mirror manifests, not whole services/
  let test44 = (run-test "audit-local-root-topology ignores broken unrelated manifest" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "svc-a"
    "not valid nuon {" | save -f ($repo | path join "services/svc-b.nuon")
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "svc-a")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    assert-audit-result-shape $repo ["svc-a"]
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 45: manifest filename vs name mismatch hard-errors with specific message
  let test45 = (run-test "tracked service manifest filename name mismatch hard-errors" {
    let repo = (make-temp-repo)
    { name: "other-name" } | save -f ($repo | path join "services/foo-svc.nuon")
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "foo-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected guard to fail when manifest name mismatches filename"}
    }
    if not ($result.msg | str contains "Tracked service manifest name mismatch") {
      error make {msg: $"Expected name mismatch error, got: ($result.msg)"}
    }
    if ($result.msg | str contains "Unknown local service mirror") {
      error make {msg: $"Name mismatch must not surface as unknown mirror: ($result.msg)"}
    }
    true
  } $verbose_flag)

  # Test 40: broken tracked manifest surfaces manifest error
  let test40 = (run-test "broken tracked service manifest hard-errors before mirror audit" {
    let repo = (make-temp-repo)
    "not valid nuon {" | save -f ($repo | path join "services/test-svc.nuon")
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    mkdir (local-services-path $repo | path join "test-svc")
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected guard to fail on broken tracked service manifest"}
    }
    if not ($result.msg | str contains "Unable to read tracked service manifest") {
      error make {msg: $"Expected manifest read error, got: ($result.msg)"}
    }
    if ($result.msg | str contains "Unknown local service mirror") {
      error make {msg: $"Manifest failure must not surface as unknown mirror: ($result.msg)"}
    }
    true
  } $verbose_flag)

  # Test 46: unsupported non-file item inside tracked mirror hard-errors
  let test46 = (run-test "unsupported local mirror non-file item hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    ^ln -s /tmp ($mirror | path join "cache-link")
    let ok = (expect-guard-fail $repo "Unsupported item in local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 47: env-only SOURCE_PATH materializes with empty legal topology
  let test47 = (run-test "env-only SOURCE_PATH materializes with empty legal topology" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    mkdir ($repo | path join "local-src")
    let plane_ctx = (guard-local-plane-presence $repo)
    let merged = {
      sources: {
        my_src: {
          url: "https://example.com/repo.git"
          ref: "main"
        }
      }
    }
    let expected_path = ($repo | path join "local-src" | path expand)
    let out = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
      apply-local-plane-effective-sources $merged "test-svc" { name: "v1" } $plane_ctx
    })
    let materialized = (try { $out.sources.my_src.path | path expand } catch { "" })
    if $materialized != $expected_path {
      error make {msg: $"Expected exact env path ($expected_path), got: ($materialized)"}
    }
    if ("url" in ($out.sources.my_src | columns)) or ("ref" in ($out.sources.my_src | columns)) {
      error make {msg: "Env-only materialization must replace git fields with path only"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 56: invalid env SOURCE_PATH hard-errors
  let test56 = (run-test "invalid env SOURCE_PATH hard-errors" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    let plane_ctx = (guard-local-plane-presence $repo)
    let merged = {
      sources: {
        my_src: {
          url: "https://example.com/repo.git"
          ref: "main"
        }
      }
    }
    let ok = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = "/etc/passwd"
      expect-effective-config-error {||
        apply-local-plane-effective-sources $merged "test-svc" { name: "v1" } $plane_ctx
      } "invalid path"
    })
    rm-temp-repo $repo
    $ok
  } $verbose_flag)

  # Test 57: load-service-config applies env-only materialization under local plane
  let test57 = (run-test "load-service-config env-only materialization under local plane" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    mkdir ($repo | path join "local-src")
    let plane_ctx = (guard-local-plane-presence $repo)
    let manifest = (run-in-temp-repo $repo {|| load-versions-manifest "test-svc" })
    let version_spec = (apply-version-defaults $manifest { name: "v1", overrides: {} })
    let expected_path = ($repo | path join "local-src" | path expand)
    let out = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
      load-service-config "test-svc" $version_spec "" null $plane_ctx
    })
    let materialized = (try { $out.sources.my_src.path | path expand } catch { "" })
    if $materialized != $expected_path {
      error make {msg: $"Expected load-service-config env path ($expected_path), got: ($materialized)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 58: local plane build args ignore post-guard env PATH and MODE overrides
  let test58 = (run-test "local plane build args ignore post-guard env PATH and MODE overrides" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    mkdir ($repo | path join "local-src")
    let plane_ctx = (guard-local-plane-presence $repo)
    let manifest = (run-in-temp-repo $repo {|| load-versions-manifest "test-svc" })
    let version_spec = (apply-version-defaults $manifest { name: "v1", overrides: {} })
    let cfg = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
      load-service-config "test-svc" $version_spec "" null $plane_ctx
    })
    let guarded_path = (try { $cfg.sources.my_src.path } catch { "" })
    let build_args = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = "/etc/passwd"
      $env.MY_SRC_MODE = "git"
      let source_types = (detect-all-source-types $cfg.sources $PLANE_LOCAL)
      generate-build-args "v1" $cfg {sha: "abc", is_local: true, platforms: []} {} {enabled: false} {enabled: false} "" false {} $source_types {} $PLANE_LOCAL
    })
    let arg_path = (try { $build_args.MY_SRC_PATH } catch { "" })
    if $arg_path != $guarded_path {
      error make {msg: $"Expected build arg path to match guard-owned path '($guarded_path)', got: '($arg_path)'"}
    }
    let arg_mode = (try { $build_args.MY_SRC_MODE } catch { "" })
    if $arg_mode != "local" {
      error make {msg: $"Expected build arg mode 'local', got: '($arg_mode)'"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 60: inspect effective-config success path on local plane
  let test60 = (run-test "inspect effective-config returns guard-owned merged config on local plane" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    mkdir (local-root-path $repo)
    mkdir ($repo | path join "local-src")
    let expected_path = ($repo | path join "local-src" | path expand)
    let entry = (dockypody-entry)
    let out = (run-in-temp-repo $repo {||
      $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
      ^nu $entry inspect effective-config --service test-svc --plane local | complete
    })
    if $out.exit_code != 0 {
      error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
    }
    let cfg = (try {
      $out.stdout | from json
    } catch {
      error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
    })
    let materialized = (try { $cfg.sources.my_src.path | path expand } catch { "" })
    if $materialized != $expected_path {
      error make {msg: $"Expected inspect env path ($expected_path), got: ($materialized)"}
    }
    rm-temp-repo $repo
    true
  } $verbose_flag)

  # Test 61: missing root failure names presence contract before topology audit
  let test61 = (run-test "missing root failure names presence contract before topology audit" {
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
    if not ($result.msg | str contains "requires local root directory") {
      error make {msg: $"Expected presence contract error, got: ($result.msg)"}
    }
    for forbidden in ["Unsupported local root", "Unknown local service mirror", "Incomplete local service mirror"] {
      if ($result.msg | str contains $forbidden) {
        error make {msg: $"Missing root must not surface topology audit error '($forbidden)': ($result.msg)"}
      }
    }
    true
  } $verbose_flag)

  # Test 59: inspect effective-config routes through guard on local plane
  let test59 = (run-test "inspect effective-config routes through guard on local plane" {
    let repo = (make-temp-repo)
    seed-service-with-git-source $repo
    let out = (run-dockypody-in-repo $repo ["inspect" "effective-config" "--service" "test-svc" "--plane" "local"])
    rm-temp-repo $repo
    if $out.exit_code == 0 {
      error make {msg: "Expected inspect to fail when local root is missing"}
    }
    if not (($out.stderr | str join " ") | str contains ".dockypody.local") {
      error make {msg: $"Expected guard error mentioning .dockypody.local, got: ($out.stderr)"}
    }
    true
  } $verbose_flag)

  # Collect results
  let results = [$test1, $test2, $test3, $test4, $test5, $test6, $test7, $test8, $test9, $test10, $test11, $test12, $test13, $test14, $test15, $test16, $test17, $test18, $test19, $test20, $test21, $test22, $test23, $test24, $test25, $test26, $test27, $test28, $test29, $test30, $test31, $test32, $test33, $test34, $test35, $test36, $test37, $test38, $test39, $test40, $test41, $test42, $test43, $test44, $test45, $test46, $test47, $test56, $test57, $test58, $test59, $test60, $test61]
  
  print-test-summary $results
  
  if ($results | all {|r| $r}) {
    exit 0
  } else {
    exit 1
  }
}
