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

# Topology error cases: unsupported root, symlink, unreadable dir, hidden entry, etc.

use ../../lib/plane/guard.nu [guard-local-plane-presence]
use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../../lib/plane/audit.nu [audit-local-root-topology LOCAL_MIRROR_FILE require-services-directory]
use ../lib.nu [run-test]
use ./_fixtures.nu [
  make-temp-repo rm-temp-repo seed-tracked-service expect-guard-fail
  verify-unreadable-topology-contract
]

export def test-unsupported-root-file [verbose: bool] {
  run-test "unsupported local root file hard-errors" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    "" | save -f (local-root-path $repo | path join "notes.txt")
    let ok = (expect-guard-fail $repo "Unsupported local root file")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-unsupported-root-directory [verbose: bool] {
  run-test "unsupported local root directory hard-errors" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    mkdir (local-root-path $repo | path join "cache")
    let ok = (expect-guard-fail $repo "Unsupported local root directory")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-unknown-service-mirror [verbose: bool] {
  run-test "unknown local service mirror hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    mkdir (local-services-path $repo | path join "shadow-svc")
    let ok = (expect-guard-fail $repo "Unknown local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-unsupported-mirror-file [verbose: bool] {
  run-test "unsupported local mirror file hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    "" | save -f ($mirror | path join "platforms.nuon")
    let ok = (expect-guard-fail $repo "Unsupported file in local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-unsupported-mirror-subdirectory [verbose: bool] {
  run-test "unsupported local mirror subdirectory hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    mkdir ($mirror | path join "fragments")
    let ok = (expect-guard-fail $repo "Unsupported directory in local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-empty-tracked-mirror [verbose: bool] {
  run-test "empty tracked mirror hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    let ok = (expect-guard-fail $repo "Incomplete local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-unsupported-root-symlink [verbose: bool] {
  run-test "unsupported local root symlink hard-errors" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    ^ln -s /tmp (local-root-path $repo | path join "cache-link")
    let ok = (expect-guard-fail $repo "Unsupported local root item")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-tracked-mirror-symlink [verbose: bool] {
  run-test "tracked local service mirror symlink hard-errors" {
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
  } $verbose
}

export def test-unreadable-topology-dirs [verbose: bool] {
  run-test "unreadable local topology directories hard-error" {
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
  } $verbose
}

export def test-loose-file-under-services [verbose: bool] {
  run-test "loose file under local services hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    "" | save -f (local-services-path $repo | path join "loose-file.txt")
    let ok = (expect-guard-fail $repo "Mirror entries must be directories for tracked services")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-unreadable-tracked-mirror [verbose: bool] {
  run-test "unreadable tracked mirror directory hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    verify-unreadable-topology-contract $repo $mirror "unreadable tracked mirror directory"
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-non-directory-services-path [verbose: bool] {
  run-test "non-directory local services/ path hard-errors" {
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
  } $verbose
}

export def test-extra-mirror-sibling [verbose: bool] {
  run-test "legal versions.nuon with extra mirror sibling hard-errors" {
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
  } $verbose
}

export def test-hidden-root-entry [verbose: bool] {
  run-test "hidden dot-prefixed local root entry hard-errors" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    mkdir (local-root-path $repo | path join ".hidden-cache")
    let ok = (expect-guard-fail $repo "Unsupported local root directory")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-hidden-unknown-mirror [verbose: bool] {
  run-test "hidden dot-prefixed unknown local service mirror hard-errors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    mkdir (local-services-path $repo | path join ".shadow-svc")
    let ok = (expect-guard-fail $repo "Unknown local service mirror")
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-hidden-mirror-content [verbose: bool] {
  run-test "hidden dot-prefixed local mirror content hard-errors" {
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
  } $verbose
}

export def test-manifest-filename-name-mismatch [verbose: bool] {
  run-test "tracked service manifest filename name mismatch hard-errors" {
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
  } $verbose
}

export def test-unsupported-mirror-non-file-item [verbose: bool] {
  run-test "unsupported local mirror non-file item hard-errors" {
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
  } $verbose
}
