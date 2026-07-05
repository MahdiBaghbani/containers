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

# Architecture suite-local fixtures and guard helpers.

use ../../lib/plane/guard.nu [guard-local-plane-presence PLANE_LOCAL]
use ../../lib/plane/presence.nu [
  local-root-path local-root-present local-services-path
]
use ../../lib/plane/audit.nu [audit-local-root-topology]

export def make-temp-repo [] {
  let tmp = (^mktemp -d | str trim)
  mkdir $tmp
  mkdir ($tmp | path join "services")
  mkdir ($tmp | path join "scripts")
  ^git -C $tmp init -q
  $tmp
}

export def dockypody-entry [] {
  "scripts/dockypody.nu" | path expand
}

export def run-dockypody-in-repo [repo: string, args: list<string>] {
  let entry = (dockypody-entry)
  do -i { cd $repo; ^nu $entry ...$args } | complete
}

export def rm-temp-repo [dir: string] {
  try { rm -rf $dir } catch { }
}

export def seed-tracked-service [repo: string, name: string = "test-svc"] {
  { name: $name } | save -f ($repo | path join $"services/($name).nuon")
}

export def seed-service-with-git-source [repo: string, name: string = "test-svc"] {
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

export def run-in-temp-repo [repo: string, block: closure] {
  do -i { cd $repo; do $block }
}

export def expect-effective-config-error [block: closure, needle: string] {
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

export def expect-guard-fail [repo: string, needle: string] {
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

export def expect-guard-pass [repo: string] {
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

export def verify-unreadable-topology-contract [repo: string, dir: string, label: string] {
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

export def assert-audit-result-shape [repo: string, expected_mirrors: list<string>] {
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

export def assert-guard-result-shape [repo: string, expected_mirrors: list<string>] {
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
