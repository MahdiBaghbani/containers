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

# GitHub PR signal workflow contract tests

use ../lib.nu [run-test]

export def test-pr-signal-workflow [verbose: bool] {
  run-test "PR signal workflow metadata and command contract" {
    let wf = ".github/workflows/pr-signal.yml"
    if not ($wf | path exists) {
      error make {msg: $"Missing workflow: ($wf)"}
    }

    let wf_data = (open $wf)

    let on_block = ($wf_data."on"? | default null)
    if ($on_block == null) {
      error make {msg: $"($wf) missing 'on:' trigger block in parsed YAML"}
    }
    let pr_block = ($on_block.pull_request? | default null)
    if ($pr_block == null) {
      error make {msg: $"($wf) missing pull_request: trigger"}
    }
    let pr_paths = ($pr_block.paths? | default [])
    if ($pr_paths | is-empty) {
      error make {
        msg: $"($wf) missing paths array in pull_request trigger"
      }
    }

    let cancel_in_progress = (
      $wf_data.concurrency?."cancel-in-progress"? | default false
    )
    if $cancel_in_progress != true {
      error make {
        msg: $"($wf) concurrency.cancel-in-progress mismatch. got=($cancel_in_progress) expected=true"
      }
    }

    let contents_perm = ($wf_data.permissions?.contents? | default "")
    if $contents_perm != "read" {
      error make {
        msg: $"($wf) permissions.contents mismatch. got=($contents_perm) expected=read"
      }
    }

    let signal_job = ($wf_data.jobs?.signal? | default {})
    if ($signal_job | is-empty) {
      error make {msg: $"($wf) missing jobs.signal"}
    }
    let timeout_minutes = ($signal_job | get --optional "timeout-minutes") | default null
    if $timeout_minutes != 10 {
      error make {
        msg: $"($wf) jobs.signal.timeout-minutes mismatch. got=($timeout_minutes) expected=10"
      }
    }

    let steps = ($signal_job.steps? | default [])
    if ($steps | is-empty) {
      error make {msg: $"($wf) jobs.signal.steps is empty"}
    }

    let checkout_steps = (
      $steps
      | where {|s| ($s.uses? | default "") == "actions/checkout@v5"}
    )
    if ($checkout_steps | is-empty) {
      error make {msg: $"($wf) missing actions/checkout@v5 step"}
    }

    let nu_steps = (
      $steps
      | where {|s| ($s.name? | default "") == "Install Nushell"}
    )
    if ($nu_steps | is-empty) {
      error make {msg: $"($wf) missing 'Install Nushell' step"}
    }
    let nu_version = (($nu_steps | first).env?.NU_VERSION? | default "")
    if $nu_version != "0.113.1" {
      error make {
        msg: $"($wf) Install Nushell NU_VERSION mismatch. got=($nu_version) expected=0.113.1"
      }
    }

    let expected_commands = [
      "nu scripts/dockypody.nu validate --all-services"
      "nu scripts/dockypody.nu build --all-services --matrix-json --latest-only | jq . >/dev/null"
      "nu scripts/dockypody.nu ci workflow --target all --dry-run >/dev/null"
      "nu scripts/dockypody.nu test --suite ci"
      "nu scripts/dockypody.nu docs lint"
    ]
    let dockypody_runs = (
      $steps
      | each {|s| ($s.run? | default "") | str trim}
      | where {|r| $r | str contains "scripts/dockypody.nu"}
    )
    if $dockypody_runs != $expected_commands {
      error make {
        msg: $"($wf) dockypody command order mismatch. got=[($dockypody_runs | str join ' | ')] expected=[($expected_commands | str join ' | ')]"
      }
    }

    # Matrix-json build is allowed; bare/service/image-building build is not.
    for cmd in $dockypody_runs {
      if ($cmd | str contains "dockypody.nu build") {
        if not ($cmd | str contains "--matrix-json") {
          error make {
            msg: $"($wf) forbids image-building build step without --matrix-json: ($cmd)"
          }
        }
      }
    }

    # test --suite all indirectly builds images via e2e-smoke; forbidden in static PR gate.
    for cmd in $dockypody_runs {
      if ($cmd == "nu scripts/dockypody.nu test --suite all") or ($cmd | str contains "test --suite all") {
        error make {
          msg: $"($wf) forbids 'test --suite all' in static PR gate: it builds images via e2e-smoke (needs Docker + origin remote + network) and violates the no-image-builds contract: ($cmd)"
        }
      }
    }

    # Reject raw docker/image-build run commands and common image-build actions.
    # Allowed matrix command keeps --matrix-json and is not matched here.
    let forbidden_run_needles = [
      "docker build"
      "docker buildx build"
      "buildx build"
    ]
    let forbidden_action_needles = [
      "docker/build-push-action"
      "docker/bake-action"
    ]
    for step in $steps {
      let run_cmd = ($step.run? | default "")
      let uses_ref = ($step.uses? | default "")
      for needle in $forbidden_run_needles {
        if ($run_cmd | str contains $needle) {
          error make {
            msg: $"($wf) forbids image-building run step containing '($needle)': ($run_cmd)"
          }
        }
      }
      for needle in $forbidden_action_needles {
        if ($uses_ref | str contains $needle) {
          error make {
            msg: $"($wf) forbids image-building action step: ($uses_ref)"
          }
        }
      }
    }

    true
  } $verbose
}
