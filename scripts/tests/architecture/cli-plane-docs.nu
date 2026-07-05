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

# --plane help coverage.

use ../lib.nu [run-test]

export def test-build-help-documents-plane [verbose: bool] {
  run-test "build help documents --plane" {
    let out = (nu -c "use scripts/lib/build/cli.nu [build-help]; build-help" | str join "\n")
    if not ($out | str contains "--plane") {
      error make {msg: "build-help should document --plane"}
    }
    true
  } $verbose
}

export def test-validate-help-documents-plane [verbose: bool] {
  run-test "validate help documents --plane" {
    let out = (nu -c "use scripts/lib/validate/cli.nu [validate-help]; validate-help" | str join "\n")
    if not ($out | str contains "--plane") {
      error make {msg: "validate-help should document --plane"}
    }
    true
  } $verbose
}
