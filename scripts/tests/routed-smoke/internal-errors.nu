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

# Unsupported/internal suite-name error cases.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]

export def test-smoke-internal-suite-errors [verbose: bool] {
    run-test "smoke: unsupported/internal suite name errors clearly" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry test --suite helpers | complete)
        let expected_stderr = "Unsupported test suite: 'helpers'. Run: nu scripts/dockypody.nu test help"
        if $out.exit_code == 0 {
            error make {msg: "test --suite helpers should fail but exited 0"}
        }
        if (($out.stdout | str trim) != "") {
            error make {msg: $"internal suite error should not print stdout; got: ($out.stdout | str trim)"}
        }
        if (($out.stderr | str trim) != $expected_stderr) {
            error make {msg: $"internal suite stderr mismatch. Expected: '($expected_stderr)'. Got: '($out.stderr | str trim)'"}
        }
        true
    } $verbose
}
