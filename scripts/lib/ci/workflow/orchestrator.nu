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

# Generator for build-orchestrator.yml and entry workflows

use ../../services/core.nu [list-service-names]
use ../deps.nu [get-direct-dependency-services get-all-dependency-services]
use ./constants.nu [gen-workflow-header service-to-job-id services-to-job-ids format-needs-list]

def get-services-with-deps [] {
    let services = (list-service-names)
    $services | each {|svc|
        let direct_deps = (get-direct-dependency-services $svc)
        let all_deps = (get-all-dependency-services $svc)
        {
            name: $svc,
            job_id: (service-to-job-id $svc),
            direct_deps: $direct_deps,
            all_deps: $all_deps,
            needs_job_ids: (services-to-job-ids $direct_deps)
        }
    }
}

def gen-dependency-graph-comment [services_with_deps: list] {
    mut lines = ["# Service dependency graph:"]
    $lines = ($lines | append "#")
    
    for svc in $services_with_deps {
        let deps_str = (if ($svc.direct_deps | is-empty) {
            "(root service)"
        } else {
            $"depends on: ($svc.direct_deps | str join ', ')"
        })
        $lines = ($lines | append $"#   ($svc.name) - ($deps_str)")
    }
    
    $lines = ($lines | append "#")
    ($lines | str join "\n") + "\n"
}

def gen-orchestrator-service-job [svc_info: record] {
    let job_id = $svc_info.job_id
    let name = $svc_info.name
    let deps_str = ($svc_info.all_deps | str join ",")
    let needs_yaml = (format-needs-list $svc_info.needs_job_ids)

    $"  ($job_id):
    name: ($name)
($needs_yaml)    uses: ./.github/workflows/build-service.yml
    with:
      service: ($name)
      push: ${{ inputs.push }}
      dependencies: \"($deps_str)\"
      disk_monitor_mode: basic
      prune_build_cache: true
"
}

def gen-build-complete-job [all_job_ids: list] {
    let needs_yaml = (format-needs-list $all_job_ids)

    $"  build_complete:
    name: Build Complete
($needs_yaml)    if: always\(\)
    runs-on: ubuntu-latest
    steps:
      - name: Clean up shard artifacts
        uses: geekyeggo/delete-artifact@v5
        with:
          name: shard-*
          failOnError: false

      - name: All builds completed
        run: echo \"Build orchestration finished\"
"
}

export def generate-orchestrator [] {
    let services_with_deps = (get-services-with-deps)
    
    let header = (gen-workflow-header 
        "Reusable workflow for orchestrating service builds"
        "nu scripts/dockypody.nu ci workflow --target orchestrator"
        "Build Orchestrator"
        'on:
  workflow_call:
    inputs:
      push:
        description: "Push images to registry"
        required: false
        type: boolean
        default: false
')
    let graph_comment = (gen-dependency-graph-comment $services_with_deps)
    
    mut jobs_yaml = "jobs:\n"
    
    for svc_info in $services_with_deps {
        let job_yaml = (gen-orchestrator-service-job $svc_info)
        $jobs_yaml = $jobs_yaml + $job_yaml + "\n"
    }
    
    let all_job_ids = ($services_with_deps | get job_id)
    let complete_job = (gen-build-complete-job $all_job_ids)
    $jobs_yaml = $jobs_yaml + $complete_job
    
    $header + $graph_comment + "\n" + $jobs_yaml
}

export def generate-build-push [] {
    let header = (gen-workflow-header 
        "Build and push all services - Manual workflow for pushing to ghcr.io"
        "nu scripts/dockypody.nu ci workflow --target build-push"
        "Build and Push All"
        "on:\n  workflow_dispatch:")
    
    $header + '
jobs:
  run_build_push_all:
    name: Build and Push All Services
    uses: ./.github/workflows/build-orchestrator.yml
    with:
      push: true
'
}

export def generate-build [] {
    let header = (gen-workflow-header 
        "Build all services - Use this for build verification without pushing"
        "nu scripts/dockypody.nu ci workflow --target build"
        "Build All"
        "on:\n  workflow_dispatch:")
    
    $header + '
jobs:
  run_build_all:
    name: Build All Services
    uses: ./.github/workflows/build-orchestrator.yml
    with:
      push: false
'
}
