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

# Tracked-only / --plane local rejection and CI isolation tests

use ../../lib/ci/deps.nu [get-direct-dependency-services]
use ../lib.nu [run-test]
use ./_fixtures.nu [
  ISOLATION_LEAK_DEP ISOLATION_SVC ISOLATION_TRACKED_DEP
  make-temp-repo rm-temp-repo run-in-temp-repo seed-tracked-plane-isolation-fixture
]
use ./_repo.nu [run-dockypody-in-repo]

export def test-tracked-only-build-matrix-json-rejected [entry: string, verbose: bool] {
  run-test "tracked-only: build --matrix-json --plane local is rejected" {
    let out = (^nu $entry build --service revad-base --matrix-json --plane local | complete)
    if $out.exit_code == 0 {
      error make {msg: "Expected build --matrix-json --plane local to exit non-zero"}
    }
    if not ($out.stderr | str contains "--plane local is not supported") {
      error make {msg: $"Expected local-plane rejection for matrix-json; got: ($out.stderr)"}
    }
    true
  } $verbose
}

export def test-tracked-only-ci-workflow-rejected [entry: string, verbose: bool] {
  run-test "tracked-only: ci workflow --plane local is rejected" {
    let out = (^nu $entry ci workflow --target build --plane local --dry-run | complete)
    if $out.exit_code == 0 {
      error make {msg: "Expected ci workflow --plane local to exit non-zero"}
    }
    if not ($out.stderr | str contains "--plane local is not supported") {
      error make {msg: $"Expected local-plane rejection for ci workflow; got: ($out.stderr)"}
    }
    true
  } $verbose
}

export def test-tracked-only-ci-ghcr-purge-rejected [entry: string, verbose: bool] {
  run-test "tracked-only: ci ghcr-purge --plane local is rejected" {
    let out = (^nu $entry ci ghcr-purge --plane local --dry-run | complete)
    if $out.exit_code == 0 {
      error make {msg: "Expected ci ghcr-purge --plane local to exit non-zero"}
    }
    if not ($out.stderr | str contains "--plane local is not supported") {
      error make {msg: $"Expected local-plane rejection for ci ghcr-purge; got: ($out.stderr)"}
    }
    true
  } $verbose
}

export def test-tracked-only-ci-deps-ignore-local-fragment [verbose: bool] {
  run-test "tracked-only: CI deps ignore local fragment version and collision overrides" {
    let repo = (make-temp-repo)
    seed-tracked-plane-isolation-fixture $repo
    let deps = (run-in-temp-repo $repo {||
      get-direct-dependency-services $ISOLATION_SVC
    })
    rm-temp-repo $repo
    if $ISOLATION_LEAK_DEP in $deps {
      error make {msg: $"Local-only dependency leaked into CI deps: ($deps | str join ', ')"}
    }
    if not ($ISOLATION_TRACKED_DEP in $deps) {
      error make {msg: $"Tracked dependency missing from CI deps: ($deps | str join ', ')"}
    }
    true
  } $verbose
}

export def test-tracked-only-build-matrix-json-with-fragment [entry: string, verbose: bool] {
  run-test "tracked-only: build --matrix-json --plane local rejected with local fragment present" {
    let repo = (make-temp-repo)
    seed-tracked-plane-isolation-fixture $repo
    let out = (run-dockypody-in-repo $repo $entry [
      build --service $ISOLATION_SVC --matrix-json --plane local
    ])
    rm-temp-repo $repo
    if $out.exit_code == 0 {
      error make {msg: "Expected build --matrix-json --plane local to exit non-zero"}
    }
    if not ($out.stderr | str contains "--plane local is not supported") {
      error make {msg: $"Expected local-plane rejection for matrix-json; got: ($out.stderr)"}
    }
    true
  } $verbose
}

export def test-tracked-only-ci-workflow-with-fragment [entry: string, verbose: bool] {
  run-test "tracked-only: ci workflow --plane local rejected with local fragment present" {
    let repo = (make-temp-repo)
    seed-tracked-plane-isolation-fixture $repo
    let out = (run-dockypody-in-repo $repo $entry [
      ci workflow --target build --plane local --dry-run
    ])
    rm-temp-repo $repo
    if $out.exit_code == 0 {
      error make {msg: "Expected ci workflow --plane local to exit non-zero"}
    }
    if not ($out.stderr | str contains "--plane local is not supported") {
      error make {msg: $"Expected local-plane rejection for ci workflow; got: ($out.stderr)"}
    }
    true
  } $verbose
}

export def test-tracked-only-ci-ghcr-purge-with-fragment [entry: string, verbose: bool] {
  run-test "tracked-only: ci ghcr-purge --plane local rejected with local fragment present" {
    let repo = (make-temp-repo)
    seed-tracked-plane-isolation-fixture $repo
    let out = (run-dockypody-in-repo $repo $entry [
      ci ghcr-purge --plane local --dry-run
    ])
    rm-temp-repo $repo
    if $out.exit_code == 0 {
      error make {msg: "Expected ci ghcr-purge --plane local to exit non-zero"}
    }
    if not ($out.stderr | str contains "--plane local is not supported") {
      error make {msg: $"Expected local-plane rejection for ci ghcr-purge; got: ($out.stderr)"}
    }
    true
  } $verbose
}
