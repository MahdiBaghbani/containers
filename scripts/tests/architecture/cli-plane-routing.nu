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

# Routed build / validate local-plane guard behavior.

use ../lib.nu [run-test]
use ./_fixtures.nu [make-temp-repo rm-temp-repo run-dockypody-in-repo]

export def test-build-plane-local-guard [verbose: bool] {
  run-test "build --plane local enforces root guard via dockypody.nu" {
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
  } $verbose
}

export def test-validate-plane-local-service-guard [verbose: bool] {
  run-test "validate --plane local --service x enforces root guard via dockypody.nu" {
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
  } $verbose
}

export def test-validate-plane-local-help [verbose: bool] {
  run-test "validate --plane local with no target shows help via dockypody.nu" {
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
  } $verbose
}
