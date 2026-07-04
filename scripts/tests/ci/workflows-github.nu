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

# GitHub workflow generation drift tests

use ../../lib/ci/workflow.nu [get-workflows-for-target]
use ../lib.nu [run-test]

export def test-generated-workflows-match [verbose: bool] {
  run-test "Generated workflows match committed files" {
    let targets = ["build" "build-push" "orchestrator" "build-service" "image-purge"]
    for target in $targets {
      let workflows = (get-workflows-for-target $target)
      for wf in $workflows {
        if not ($wf.path | path exists) {
          error make {
            msg: $"Committed workflow missing for target ($target): ($wf.path)"
          }
        }
        let committed = (open --raw $wf.path)
        if $wf.contents != $committed {
          error make {
            msg: $"Workflow drift detected for target '($target)': ($wf.path) does not match generator output. Regenerate with: nu scripts/dockypody.nu ci workflow --target ($target)"
          }
        }
      }
    }
    true
  } $verbose
}
