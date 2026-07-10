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

# Forgejo workflow contract tests

use ../lib.nu [run-test]

export def test-forgejo-workflows [verbose: bool] {
  run-test "Forgejo workflow files exist and invoke expected commands" {
    let build_wf = ".forgejo/workflows/build-containers.yml"
    let validate_wf = ".forgejo/workflows/validate-schemas.yml"
    if not ($build_wf | path exists) {
      error make {msg: $"Missing workflow: ($build_wf)"}
    }
    if not ($validate_wf | path exists) {
      error make {msg: $"Missing workflow: ($validate_wf)"}
    }
    let build_contents = (open --raw $build_wf)
    if not ($build_contents | str contains "scripts/dockypody.nu build") {
      error make {
        msg: $"($build_wf) does not invoke 'scripts/dockypody.nu build'"
      }
    }
    let validate_contents = (open --raw $validate_wf)
    let expected_commands = [
      "scripts/dockypody.nu docs lint"
      "scripts/dockypody.nu test --suite all"
    ]
    for cmd in $expected_commands {
      if not ($validate_contents | str contains $cmd) {
        error make {
          msg: $"($validate_wf) does not invoke '($cmd)'"
        }
      }
    }
    # Parse the YAML and inspect trigger paths arrays directly.
    let wf_data = (open $validate_wf)
    let on_block = ($wf_data."on"? | default null)
    if ($on_block == null) {
      error make {msg: $"($validate_wf) missing 'on:' trigger block in parsed YAML"}
    }
    let push_block = ($on_block.push? | default null)
    if ($push_block == null) {
      error make {msg: $"($validate_wf) missing push: trigger"}
    }
    let push_branches = ($push_block.branches? | default [])
    if ($push_branches | sort) != (["main" "master"] | sort) {
      error make {
        msg: $"($validate_wf) push.branches mismatch. got=($push_branches | str join ',') expected=main,master"
      }
    }
    let push_paths = ($push_block.paths? | default [])
    if ($push_paths | is-empty) {
      error make {msg: $"($validate_wf) missing paths array in push trigger"}
    }
    let expected_trigger_paths = [
      ".forgejo/workflows/**"
      ".github/workflows/**"
      "Makefile"
      "README.md"
      "docs/**"
      "schemas/**"
      "services/**/Dockerfile*"
      "services/**/scripts/**"
      "services/**/*.nuon"
      "scripts/**"
    ]
    if ($push_paths | sort) != ($expected_trigger_paths | sort) {
      error make {
        msg: $"($validate_wf) push.paths mismatch. got=($push_paths | sort | str join ',') expected=($expected_trigger_paths | sort | str join ',')"
      }
    }
    let pr_block = ($on_block.pull_request? | default null)
    if ($pr_block == null) {
      error make {msg: $"($validate_wf) missing pull_request: trigger"}
    }
    let pr_paths = ($pr_block.paths? | default [])
    if ($pr_paths | is-empty) {
      error make {
        msg: $"($validate_wf) missing paths array in pull_request trigger"
      }
    }
    if ($pr_paths | sort) != ($expected_trigger_paths | sort) {
      error make {
        msg: $"($validate_wf) pull_request.paths mismatch. got=($pr_paths | sort | str join ',') expected=($expected_trigger_paths | sort | str join ',')"
      }
    }
    let job_name = ($wf_data.jobs?.validate?.name? | default "")
    if $job_name != "Lightweight Non-Image Validation" {
      error make {
        msg: $"($validate_wf) jobs.validate.name mismatch. got=($job_name)"
      }
    }
    let validate_job = ($wf_data.jobs?.validate? | default {})
    let job_runs_on = ($validate_job | get --optional "runs-on") | default ""
    if $job_runs_on != "ubuntu-latest" {
      error make {
        msg: $"($validate_wf) jobs.validate.runs-on mismatch. got=($job_runs_on)"
      }
    }
    let steps = ($wf_data.jobs?.validate?.steps? | default [])
    let step_names = ($steps | each {|s| $s.name? | default ""})
    let required_step_names = [
      "Checkout code"
      "Install Nushell"
      "Validate schema example files"
      "Validate all service configs"
      "Validate schema file references"
    ]
    for name in $required_step_names {
      if not ($name in $step_names) {
        error make {msg: $"($validate_wf) missing required step: ($name)"}
      }
    }
    # Structured checks for build-containers.yml.
    let build_data = (open $build_wf)

    # 1. Nushell-version parity: both workflows must pin the same NU_VERSION.
    let build_nu_steps = (
      ($build_data.jobs?.build?.steps? | default [])
      | where {|s| ($s.name? | default "") == "Install Nushell"}
    )
    if ($build_nu_steps | is-empty) {
      error make {msg: $"($build_wf) missing 'Install Nushell' step"}
    }
    let build_nu_step = ($build_nu_steps | first)
    let build_nu_version = ($build_nu_step.env?.NU_VERSION? | default "")
    if $build_nu_version == "" {
      error make {
        msg: $"($build_wf) Install Nushell step missing NU_VERSION"
      }
    }
    let github_build_wf = ".github/workflows/build-service.yml"
    if not ($github_build_wf | path exists) {
      error make {msg: $"Missing GitHub build workflow: ($github_build_wf)"}
    }
    let github_build_data = (open $github_build_wf)
    let github_nu_steps = (
      ($github_build_data.jobs?.build?.steps? | default [])
      | where {|s| ($s.name? | default "") == "Install Nushell"}
    )
    if ($github_nu_steps | is-empty) {
      error make {
        msg: $"($github_build_wf) missing 'Install Nushell' step in build job"
      }
    }
    let github_nu_version = (($github_nu_steps | first).env?.NU_VERSION? | default "")
    if $build_nu_version != $github_nu_version {
      error make {
        msg: $"NU_VERSION mismatch: ($build_wf)=($build_nu_version) ($github_build_wf)=($github_nu_version)"
      }
    }

    let build_steps = (
      ($build_data.jobs?.build?.steps? | default [])
      | where {|s| ($s.name? | default "") == "Build"}
    )
    if ($build_steps | is-empty) {
      error make {msg: $"($build_wf) missing 'Build' step"}
    }
    let build_step = ($build_steps | first)
    let build_run = ($build_step.run? | default "")

    # 2. Default-service fallback: YAML input default and shell fallback.
    let wd_svc = (
      $build_data."on"?.workflow_dispatch?.inputs?.service? | default {}
    )
    let svc_default = ($wd_svc."default"? | default "")
    if $svc_default != "cernbox-web" {
      error make {
        msg: $"($build_wf) workflow_dispatch service default mismatch. got=($svc_default)"
      }
    }
    if not ($build_run | str contains 'SERVICE="cernbox-web"') {
      error make {
        msg: $"($build_wf) Build step missing SERVICE fallback to cernbox-web"
      }
    }

    # 3. workflow_dispatch push input assertions.
    let wd_push = (
      $build_data."on"?.workflow_dispatch?.inputs?.push? | default {}
    )
    if ($wd_push | is-empty) {
      error make {msg: $"($build_wf) missing workflow_dispatch input: push"}
    }
    let push_type = ($wd_push."type"? | default "")
    if $push_type != "boolean" {
      error make {
        msg: $"($build_wf) workflow_dispatch push type mismatch. got=($push_type) expected=boolean"
      }
    }
    let push_required = ($wd_push."required"? | default false)
    if not $push_required {
      error make {
        msg: $"($build_wf) workflow_dispatch push should be required=true. got=($push_required)"
      }
    }
    let push_default = ($wd_push."default"? | default null)
    if $push_default != true {
      error make {
        msg: $"($build_wf) workflow_dispatch push default mismatch. got=($push_default) expected=true"
      }
    }

    # 4. workflow_dispatch extra_tag input assertions.
    let wd_extra_tag = (
      $build_data."on"?.workflow_dispatch?.inputs?.extra_tag? | default {}
    )
    if ($wd_extra_tag | is-empty) {
      error make {msg: $"($build_wf) missing workflow_dispatch input: extra_tag"}
    }
    let extra_tag_required = ($wd_extra_tag."required"? | default true)
    if $extra_tag_required {
      error make {
        msg: $"($build_wf) workflow_dispatch extra_tag should be required=false. got=($extra_tag_required)"
      }
    }

    # 5. Conditional --push forwarding.
    if not ($build_run | str contains '[ "${{ steps.flags.outputs.push }}" = "true" ]') {
      error make {
        msg: $"($build_wf) Build step missing push condition on steps.flags.outputs.push"
      }
    }
    if not ($build_run | str contains 'set -- "$@" --push') {
      error make {
        msg: $"($build_wf) Build step missing conditional '--push' append"
      }
    }

    # 6. Optional --extra-tag forwarding.
    if not ($build_run | str contains '[ -n "$EXTRA_TAG" ]') {
      error make {
        msg: $"($build_wf) Build step missing non-empty EXTRA_TAG guard"
      }
    }
    if not ($build_run | str contains 'set -- "$@" --extra-tag "$EXTRA_TAG"') {
      error make {
        msg: $"($build_wf) Build step missing '--extra-tag' forwarding"
      }
    }
    true
  } $verbose
}
