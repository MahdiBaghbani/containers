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

# Local-root and plane parsing guard behavior.

use ../../lib/plane/guard.nu [guard-local-plane-presence guard-plane parse-plane]
use ../../lib/plane/presence.nu [local-root-path local-root-present local-services-path]
use ../lib.nu [run-test]
use ./_fixtures.nu [
  make-temp-repo rm-temp-repo expect-guard-pass
]

export def test-plane-local-requires-root [verbose: bool] {
  run-test "--plane local requires .dockypody.local/ presence" {
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
  } $verbose
}

export def test-empty-local-root-valid [verbose: bool] {
  run-test "empty .dockypody.local/ root alone is valid" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-empty-local-services-valid [verbose: bool] {
  run-test "optional empty .dockypody.local/services/ is valid" {
    let repo = (make-temp-repo)
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-tracked-plane-no-local-root [verbose: bool] {
  run-test "tracked plane does not require local root" {
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
  } $verbose
}

export def test-parse-plane-rejects-unknown [verbose: bool] {
  run-test "parse-plane rejects unknown values" {
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
  } $verbose
}

export def test-file-local-root-invalid [verbose: bool] {
  run-test "file .dockypody.local does not count as local root" {
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
  } $verbose
}
