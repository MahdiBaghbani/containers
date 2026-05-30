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

# CI domain test suite

use ../lib/ci/deps.nu [get-direct-dependency-services get-all-dependency-services]
use ../lib/ci/workflow.nu [get-workflows-for-target]
use ../lib/services/core.nu [list-service-names]
use ./lib.nu [run-test print-test-summary]

# Build dep_id -> service_name mapping from infra manifests (independent of library).
# Uses platforms.nuon (defaults + per-platform deps) when present,
# otherwise falls back to the base service .nuon dependencies record.
def local-build-dep-mapping [svc: string] {
    let platforms_path = $"services/($svc)/platforms.nuon"
    mut mapping = {}
    if ($platforms_path | path exists) {
        let pm = (open $platforms_path)
        let defaults_deps = (try { $pm.defaults.dependencies } catch { {} })
        if not ($defaults_deps | is-empty) {
            for dep_id in ($defaults_deps | columns) {
                let dep = ($defaults_deps | get $dep_id)
                $mapping = ($mapping | upsert $dep_id (try { $dep.service } catch { $dep_id }))
            }
        }
        let platforms = (try { $pm.platforms } catch { [] })
        for platform in $platforms {
            let pdeps = (try { $platform.dependencies } catch { {} })
            if not ($pdeps | is-empty) {
                for dep_id in ($pdeps | columns) {
                    let dep = ($pdeps | get $dep_id)
                    $mapping = ($mapping | upsert $dep_id (try { $dep.service } catch { $dep_id }))
                }
            }
        }
    } else {
        let service_path = $"services/($svc).nuon"
        if ($service_path | path exists) {
            let sc = (open $service_path)
            let deps = (try { $sc.dependencies } catch { {} })
            if not ($deps | is-empty) {
                for dep_id in ($deps | columns) {
                    let dep = ($deps | get $dep_id)
                    $mapping = ($mapping | upsert $dep_id (try { $dep.service } catch { $dep_id }))
                }
            }
        }
    }
    $mapping
}

# Compute expected direct dependency service names by walking a service's
# versions.nuon at exactly four locations:
#   defaults.dependencies
#   defaults.platforms.<platform>.dependencies
#   each version overrides.dependencies
#   each version overrides.platforms.<platform>.dependencies
# Resolves dep_ids to service names using infra manifests (independent reimplementation).
def compute-expected-deps [svc: string] {
  use ../lib/manifest/core.nu [check-versions-manifest-exists load-versions-manifest]

  if not (check-versions-manifest-exists $svc) { return [] }

  let manifest = (load-versions-manifest $svc)
  let mapping = (local-build-dep-mapping $svc)

  # Resolve dep_ids to service names; unknown dep_ids fall back to the key itself.
  let resolve_ids = {|deps: record|
    if ($deps | is-empty) { return [] }
    $deps | columns | each {|dep_id|
      ($mapping | get --optional $dep_id) | default $dep_id
    }
  }

  let default_names = (do $resolve_ids (try { $manifest.defaults.dependencies } catch { {} }))

  let dp = (try { $manifest.defaults.platforms } catch { {} })
  let default_plat_names = (if ($dp | is-empty) {
    []
  } else {
    $dp | columns | each {|pname|
      do $resolve_ids (try { ($dp | get $pname).dependencies } catch { {} })
    } | flatten
  })

  let version_names = ((try { $manifest.versions } catch { [] }) | each {|version|
    let ver_names = (do $resolve_ids (try { $version.overrides.dependencies } catch { {} }))
    let platforms = (try { $version.overrides.platforms } catch { {} })
    let plat_names = (if ($platforms | is-empty) {
      []
    } else {
      $platforms | columns | each {|pname|
        do $resolve_ids (try { ($platforms | get $pname).dependencies } catch { {} })
      } | flatten
    })
    $ver_names | append $plat_names
  } | flatten)

  ($default_names | append $default_plat_names | append $version_names) | uniq
}

def main [--verbose] {
  mut results = []

  # Test 1: list-service-names returns a non-empty list
  let test1 = (run-test "list-service-names returns services" {
    let services = (list-service-names)
    ($services | length) > 0
  } $verbose)
  $results = ($results | append $test1)

  # Test 2: For each service with a versions manifest, sorted(actual library deps)
  # must equal sorted(expected deps from independent manifest scan).
  let test2 = (run-test "Direct dep resolution matches independent manifest scan" {
    use ../lib/manifest/core.nu [check-versions-manifest-exists]
    let all_services = (list-service-names)
    for svc in $all_services {
      if not (check-versions-manifest-exists $svc) { continue }
      let actual = ((get-direct-dependency-services $svc) | sort)
      let expected = ((compute-expected-deps $svc) | sort)
      if $actual != $expected {
        error make {
          msg: $"($svc): dep mismatch. actual=($actual | str join ',') expected=($expected | str join ',')"
        }
      }
    }
    true
  } $verbose)
  $results = ($results | append $test2)

  # Test 3: All direct dependencies of every service are known service names.
  let test3 = (run-test "All direct deps are known services" {
    use ../lib/manifest/core.nu [check-versions-manifest-exists]
    let known = (list-service-names)
    let all_services = (list-service-names)
    for svc in $all_services {
      if not (check-versions-manifest-exists $svc) { continue }
      let deps = (get-direct-dependency-services $svc)
      for dep in $deps {
        if not ($dep in $known) {
          error make {msg: $"($svc): dependency '($dep)' is not a known service"}
        }
      }
    }
    true
  } $verbose)
  $results = ($results | append $test3)

  # Test 4: get-all-dependency-services returns a superset of direct deps
  # and never includes the service itself.
  let test4 = (run-test "Transitive deps are superset of direct deps, exclude self" {
    use ../lib/manifest/core.nu [check-versions-manifest-exists]
    let all_services = (list-service-names)
    for svc in $all_services {
      if not (check-versions-manifest-exists $svc) { continue }
      let direct = (get-direct-dependency-services $svc)
      if ($direct | is-empty) { continue }
      let all_deps = (get-all-dependency-services $svc)
      for dep in $direct {
        if not ($dep in $all_deps) {
          error make {msg: $"($svc): direct dep '($dep)' missing from transitive deps"}
        }
      }
      if $svc in $all_deps {
        error make {msg: $"($svc): service appears in its own transitive deps \(cycle\)"}
      }
    }
    true
  } $verbose)
  $results = ($results | append $test4)

  # Test 5: kasm-base must declare common-tools as a direct dependency.
  # Regression for defaults.platforms.*.dependencies being missed.
  let test5 = (run-test "kasm-base direct deps include common-tools" {
    let deps = (get-direct-dependency-services "kasm-base")
    if ($deps | is-empty) {
      error make {msg: "kasm-base has no direct deps (expected common-tools)"}
    }
    if not ("common-tools" in $deps) {
      error make {msg: $"kasm-base deps missing common-tools: ($deps | str join ',')"}
    }
    true
  } $verbose)
  $results = ($results | append $test5)

  # Test 6: cypress must declare common-tools and kasm-base as direct dependencies.
  # Regression for defaults.platforms.*.dependencies being missed.
  let test6 = (run-test "cypress direct deps include common-tools and kasm-base" {
    let deps = (get-direct-dependency-services "cypress")
    if not ("common-tools" in $deps) {
      error make {msg: $"cypress deps missing common-tools: ($deps | str join ',')"}
    }
    if not ("kasm-base" in $deps) {
      error make {msg: $"cypress deps missing kasm-base: ($deps | str join ',')"}
    }
    true
  } $verbose)
  $results = ($results | append $test6)

  # Test 7: Generated workflow output matches the committed .github/workflows/ files.
  # Fails on any drift between the generator and the file on disk.
  let test7 = (run-test "Generated workflows match committed files" {
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
  } $verbose)
  $results = ($results | append $test7)

  # Test 8: Forgejo workflow files exist and still invoke expected commands.
  # Protects against silent drift in .forgejo/workflows/ committed files.
  let test8 = (run-test "Forgejo workflow files exist and invoke expected commands" {
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
      "scripts/dockypody.nu test --suite ci"
      "scripts/dockypody.nu test --suite ghcr-purge"
      "scripts/dockypody.nu test --suite docs-lint"
      "scripts/dockypody.nu test --suite routed-smoke"
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
  } $verbose)
  $results = ($results | append $test8)

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
